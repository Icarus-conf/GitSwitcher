import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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
  static const String _installKey = '__install';

  StreamSubscription<void>? _profileSubscription;

  final _switched = StreamController<void>.broadcast();

  /// Fires after any switch from the menu.
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
    // ⌃⌥⌘G, registered in MainFlutterWindow.swift, opens the menu.
    const MethodChannel('gitswitcher/hotkey').setMethodCallHandler((call) async {
      if (call.method == 'pressed') onTrayIconMouseDown();
    });
    await refreshMenu();
  }

  void dispose() {
    _profileSubscription?.cancel();
    _switched.close();
    trayManager.removeListener(this);
  }

  void _announceSwitch() {
    if (!_switched.isClosed) _switched.add(null);
  }

  @override
  void onTrayIconMouseDown() {
    // Rebuild before showing so the checkmark reflects gh's current state.
    refreshMenu().then((_) => trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() => onTrayIconMouseDown();

  Future<void> refreshMenu() async {
    final config = await _services.store.loadConfig();
    final resolved = AccountResolver.merge(
      stored: List.of(config.accounts),
      discovered: await _services.gh.discover(),
    );

    // The active account's name next to the icon, so you never have to open
    // the menu to find out who you are about to push as.
    final active = resolved.where((r) => r.isActive).firstOrNull;
    await trayManager.setTitle(
      active == null ? '' : ' ${active.account.displayName}',
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
      items.add(ghInstalled
          ? MenuItem(key: '__hint', label: 'Run: gh auth login', disabled: true)
          // Settings installs it, with progress and errors it can show.
          : MenuItem(key: _installKey, label: 'Install GitHub CLI…'));
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

    // Why commits in some folders use another identity than the one ticked.
    if (config.autoSwitchEnabled && config.rules.isNotEmpty) {
      final names = {
        for (final r in resolved) r.account.ghUsername: r.account.displayName,
      };
      final home = Platform.environment['HOME'] ?? '';
      items.add(MenuItem.separator());
      items.add(MenuItem(key: '__folders', label: 'Folders', disabled: true));
      for (final rule in config.rules) {
        final path = home.isNotEmpty && rule.pathPrefix.startsWith(home)
            ? '~${rule.pathPrefix.substring(home.length)}'
            : rule.pathPrefix;
        items.add(MenuItem(
          key: '__rule_${rule.pathPrefix}',
          label: '$path → ${names[rule.ghUsername] ?? rule.ghUsername}',
          disabled: true,
        ));
      }
    }

    items.addAll([
      MenuItem.separator(),
      MenuItem(key: _settingsKey, label: 'Settings…', toolTip: '⌃⌥⌘G opens this menu'),
      MenuItem(key: _quitKey, label: 'Quit GitSwitcher'),
    ]);

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _settingsKey || _installKey:
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
