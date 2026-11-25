import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../app_services.dart';
import '../platform/process_runner.dart';
import '../services/update_checker.dart';
import '../platform/host.dart';
import '../services/account_resolver.dart';
import 'settings_window.dart';

/// One switch made from the menu.
class SwitchRecord {
  const SwitchRecord({
    required this.fromLogin,
    required this.fromName,
    required this.toName,
    required this.at,
  });

  /// The account active before, to go back to. Null when there was none.
  final String? fromLogin;
  final String? fromName;
  final String toName;
  final DateTime at;
}

/// "just now", "4 min ago", "2 h ago".
String timeAgo(DateTime at, [DateTime? now]) {
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  return '${elapsed.inDays} d ago';
}

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
  static const String _updateKey = '__update';

  AvailableUpdate? _update;

  static const String _undoKey = '__undo';

  /// How long after a switch the menu offers to undo it.
  static const Duration undoWindow = Duration(minutes: 30);

  final List<SwitchRecord> _history = [];

  /// Switches back to the account active before the last switch.
  Future<void> undoLastSwitch() async {
    final back = _history.isEmpty ? null : _history.last.fromLogin;
    if (back != null) await _switchTo(back);
  }

  /// Menu switches this session, newest first.
  List<SwitchRecord> get history => List.unmodifiable(_history.reversed);

  /// Adds an "Update to …" item that downloads [update].
  Future<void> setUpdate(AvailableUpdate update) async {
    _update = update;
    await refreshMenu();
  }

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
    // macOS wants a black template image it can recolour for the menu bar;
    // the Windows tray takes a colour .ico.
    if (Host.current.isMacOS) {
      await trayManager.setIcon('assets/tray_icon.png', isTemplate: true);
    } else {
      await trayManager.setIcon('assets/tray_icon.ico');
    }
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
    if (Host.current.isMacOS) {
      await trayManager.setTitle(
        active == null ? '' : ' ${active.account.displayName}',
      );
    } else {
      // The Windows tray has no room for text; the hover tip says it instead.
      await trayManager.setToolTip(active == null
          ? 'GitSwitcher'
          : 'GitSwitcher — ${active.account.displayName}');
    }

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
    if (config.autoSwitchEnabled &&
        (config.rules.isNotEmpty || config.orgRules.isNotEmpty)) {
      final names = {
        for (final r in resolved) r.account.ghUsername: r.account.displayName,
      };
      final home = Host.current.home;
      items.add(MenuItem.separator());
      items.add(MenuItem(key: '__folders', label: 'Rules', disabled: true));
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
      for (final rule in config.orgRules) {
        items.add(MenuItem(
          key: '__org_${rule.org}',
          label: 'github.com/${rule.org} → '
              '${names[rule.ghUsername] ?? rule.ghUsername}',
          disabled: true,
        ));
      }
    }

    final update = _update;
    final last = _history.isEmpty ? null : _history.last;
    final canUndo = last != null &&
        last.fromLogin != null &&
        DateTime.now().difference(last.at) < undoWindow &&
        resolved.any((r) => r.account.ghUsername == last.fromLogin);
    items.addAll([
      MenuItem.separator(),
      if (canUndo)
        MenuItem(
          key: _undoKey,
          label: 'Back to ${last.fromName} (switched ${timeAgo(last.at)})',
        ),
      if (update != null)
        MenuItem(key: _updateKey, label: 'Update to ${update.version}…'),
      MenuItem(
        key: _settingsKey,
        label: 'Settings…',
        toolTip: Host.current.isMacOS
            ? '⌃⌥⌘G opens this menu'
            : 'Ctrl+Alt+G opens this menu',
      ),
      MenuItem(key: _quitKey, label: 'Quit GitSwitcher'),
    ]);

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _settingsKey || _installKey:
        SettingsWindow.open();
      case _undoKey:
        undoLastSwitch();
      case _updateKey:
        final url = _update?.downloadUrl;
        if (url != null) {
          Host.current.openUrl(const RealProcessRunner(), url);
        }
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
    final previous = resolved.where((r) => r.isActive).firstOrNull;

    final result = await _services.switcher.switchTo(entry.account);
    // Picking the account already active re-applies it, which is a repair,
    // not a switch: nothing to undo.
    if (previous?.account.ghUsername != username) {
      _history.add(SwitchRecord(
        fromLogin: previous?.account.ghUsername,
        fromName: previous?.account.displayName,
        toName: entry.account.displayName,
        at: DateTime.now(),
      ));
      // ponytail: in memory, this session only; persist if people want it
      // across restarts.
      if (_history.length > 20) _history.removeAt(0);
    }
    await _services.notifier
        .showSwitchResult(result, entry.account.displayName);
    await refreshMenu();
    _announceSwitch();
  }
}
