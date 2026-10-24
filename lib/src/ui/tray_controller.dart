import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../app_services.dart';
import '../services/account_resolver.dart';
import 'settings_window.dart';

/// Owns the menu bar icon and its menu.
///
/// gh state is re-read every time the menu opens, so the checkmark stays
/// correct even when `gh auth switch` is run directly in a terminal.
class TrayController with TrayListener {
  TrayController(this._services);

  final AppServices _services;

  static const String _settingsKey = '__settings';
  static const String _quitKey = '__quit';

  StreamSubscription<void>? _profileSubscription;
  StreamSubscription<String>? _directorySubscription;

  final _switched = StreamController<void>.broadcast();

  /// Fires after any switch, manual or automatic.
  ///
  /// The settings window renders which account is active, so it has to be told
  /// when that changes — otherwise it keeps showing the previous account as
  /// live while the menu shows the new one.
  Stream<void> get switched => _switched.stream;

  Future<void> start() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    await trayManager.setToolTip('GitSwitcher');
    // Redraw once when late-arriving avatars land.
    _profileSubscription = _services.profiles.changes.listen((_) {
      refreshMenu();
    });
    _directorySubscription =
        _services.watcher.directories.listen(_onDirectoryChanged);
    _services.watcher.start();
    await refreshMenu();
  }

  void dispose() {
    _profileSubscription?.cancel();
    _directorySubscription?.cancel();
    _switched.close();
    _services.watcher.stop();
    trayManager.removeListener(this);
  }

  void _announceSwitch() {
    if (!_switched.isClosed) _switched.add(null);
  }

  /// The shell reported a new working directory.
  ///
  /// The policy decides whether anything should happen; this only performs the
  /// switch it is told to. Auto-switches are announced, because a silent change
  /// to which account you are pushing as would be alarming to discover later.
  Future<void> _onDirectoryChanged(String directory) async {
    final config = await _services.store.loadConfig();
    final discovered = await _services.gh.discover();

    final target = _services.policy.accountFor(
      directory: directory,
      enabled: config.autoSwitchEnabled,
      rules: config.rules,
      accounts: config.accounts,
      activeUsername: discovered.activeUsername,
    );
    if (target == null) return;

    final result = await _services.switcher.switchTo(target);
    await _services.notifier.showSwitchResult(result, target.displayName);
    await refreshMenu();
    _announceSwitch();
  }

  @override
  void onTrayIconMouseDown() {
    // Rebuild before showing so the checkmark reflects gh's current state.
    refreshMenu().then((_) => trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() => onTrayIconMouseDown();

  Future<void> refreshMenu() async {
    final resolved = AccountResolver.merge(
      stored: await _services.store.load(),
      discovered: await _services.gh.discover(),
    );

    final items = <MenuItem>[];

    if (resolved.isEmpty) {
      // "gh is missing" and "gh has no accounts" need different advice.
      final ghInstalled = await _services.gh.isInstalled();
      items.add(MenuItem(
        key: '__empty',
        label: ghInstalled ? 'No GitHub accounts found' : 'GitHub CLI not found',
        disabled: true,
      ));
      items.add(MenuItem(
        key: '__hint',
        label: ghInstalled
            ? 'Run: gh auth login'
            : 'Install it from cli.github.com',
        disabled: true,
      ));
    } else {
      for (final entry in resolved) {
        final note = entry.disabledReason ?? entry.setupHint;
        final profile = _services.profiles[entry.account.ghUsername];
        items.add(MenuItem.checkbox(
          key: entry.account.ghUsername,
          label: entry.account.displayName,
          toolTip: note,
          icon: profile?.avatarPath,
          checked: entry.isActive,
          disabled: !entry.isSelectable,
        ));
      }

      // Fill in anything missing. This never blocks the menu: the store only
      // fetches logins it does not already have, and emits on `changes` when
      // something new arrived, which triggers exactly one redraw.
      unawaited(
        _services.profiles.refresh(resolved.map((r) => r.account.ghUsername)),
      );
    }

    items.addAll([
      MenuItem.separator(),
      MenuItem(key: _settingsKey, label: 'Settings…'),
      MenuItem(key: _quitKey, label: 'Quit GitSwitcher'),
    ]);

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _settingsKey:
        SettingsWindow.open();
      case _quitKey:
        trayManager.destroy().then((_) => exit(0));
      case final String key when key.startsWith('__'):
        break;
      case final String username:
        _switchTo(username);
      case null:
        break;
    }
  }

  Future<void> _switchTo(String username) async {
    final stored = await _services.store.load();
    final resolved = AccountResolver.merge(
      stored: stored,
      discovered: await _services.gh.discover(),
    );
    final entry = resolved.firstWhere((r) => r.account.ghUsername == username);

    final result = await _services.switcher.switchTo(entry.account);
    await _services.notifier
        .showSwitchResult(result, entry.account.displayName);
    await refreshMenu();
    _announceSwitch();
  }
}
