import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app_services.dart';
import '../platform/launch_at_login.dart';
import '../models/account.dart';
import '../models/switch_result.dart';
import '../services/account_resolver.dart';
import 'account_slab.dart';
import 'add_account_dialog.dart';
import 'auto_switch_section.dart';
import 'theme/glass.dart';
import 'tray_controller.dart';
import 'widgets/glass_slab.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.services,
    required this.tray,
  });

  final AppServices services;
  final TrayController tray;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WindowListener {
  List<ResolvedAccount> _accounts = const [];
  bool _loading = true;
  StreamSubscription<void>? _profileSubscription;
  StreamSubscription<void>? _switchSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Avatars arrive after the first paint; redraw when they do.
    _profileSubscription = widget.services.profiles.changes.listen((_) {
      if (mounted) setState(() {});
    });
    // A switch made from the menu changes which account is live here too.
    _switchSubscription = widget.tray.switched.listen((_) {
      if (mounted) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _switchSubscription?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  /// The active account can change while this window is hidden — from the menu,
  /// from a folder rule, or from `gh auth switch` in a terminal. Re-reading on
  /// focus means the window is never showing a stale answer.
  @override
  void onWindowFocus() {
    _reload();
  }

  /// The app keeps running when this window is closed — the menu bar icon is
  /// its real home.
  @override
  void onWindowClose() {
    windowManager.hide();
  }

  Future<void> _reload() async {
    final resolved = AccountResolver.merge(
      stored: await widget.services.store.load(),
      discovered: await widget.services.gh.discover(),
    );
    if (!mounted) return;
    setState(() {
      _accounts = resolved;
      _loading = false;
    });

    unawaited(widget.services.profiles
        .refresh(resolved.map((r) => r.account.ghUsername)));
  }

  Future<void> _save(Account updated) async {
    // Nothing here may throw silently: this runs from a button handler, where
    // an unhandled exception would leave the user staring at a Save button
    // that appears to do nothing at all.
    try {
      final stored = await widget.services.store.load();
      final index = stored.indexWhere((a) => a.ghUsername == updated.ghUsername);
      if (index == -1) {
        stored.add(updated);
      } else {
        stored[index] = updated;
      }

      await widget.services.store.save(stored);
      // Folder rules and signing read these fields from ~/.gitconfig's block.
      final step = await widget.services.syncGitConfig();
      await widget.tray.refreshMenu();
      await _reload();

      if (!mounted) return;
      if (step.status == StepStatus.failed) {
        _tell('Saved, but ~/.gitconfig was not updated: ${step.message}',
            isError: true);
      } else {
        _tell('Saved ${updated.displayName}');
      }
    } catch (error) {
      if (!mounted) return;
      _tell('Could not save: $error', isError: true);
    }
  }

  Future<void> _addAccount() async {
    // Signing in as an account gh already knows replaces its token rather than
    // adding anything, which quietly drops any scopes granted earlier. Worth a
    // warning, because the failure shows up much later as a rejected push.
    if (_accounts.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => _ReplaceWarningDialog(
          existing: _accounts.map((r) => r.account.ghUsername).toList(),
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final added = await AddAccountDialog.show(context, widget.services);
    if (!mounted) return;

    if (added) {
      await _reload();
      await widget.tray.refreshMenu();
      if (mounted) _tell('Account added.');
    } else {
      _tell('Login was not completed.', isError: true);
    }
  }

  Future<void> _applyToRepo(Account account) async {
    final directory = await getDirectoryPath(confirmButtonText: 'Use this repo');
    if (directory == null) return;

    final step = await widget.services.repoIdentity.apply(account, directory);
    if (!mounted) return;

    final folder = directory.split('/').last;
    if (step.status == StepStatus.ok) {
      _tell('$folder now commits as ${account.displayName}');
    } else {
      _tell(step.message ?? 'Could not set the repo identity', isError: true);
    }
  }

  Future<void> _testSsh(Account account) async {
    final step = await widget.services.sshTester.test(account);
    if (!mounted) return;
    if (step.status == StepStatus.ok) {
      _tell('GitHub accepts this key as ${account.ghUsername}.');
    } else {
      _tell(step.message ?? 'SSH test failed', isError: true);
    }
  }

  void _tell(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xF2FF453A) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // The title bar is hidden, so this strip both labels the window and
          // gives it somewhere to be dragged from.
          DragToMoveArea(
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(84, 0, 18, 0),
                child: Row(
                  children: [
                    Text('GITSWITCHER', style: Glass.eyebrow(context)),
                    const Spacer(),
                    _HeaderAction(
                      icon: Icons.refresh,
                      tooltip: 'Reload from gh',
                      onPressed: _reload,
                    ),
                    const SizedBox(width: 6),
                    _HeaderAction(
                      icon: Icons.add,
                      tooltip: 'Add a GitHub account',
                      onPressed: _addAccount,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final setup = _SetupSlab(
      services: widget.services,
      onMessage: (message, {bool isError = false}) =>
          _tell(message, isError: isError),
      onInstalled: () async {
        await _reload();
        await widget.tray.refreshMenu();
      },
    );

    if (_accounts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [setup, const _EmptyState()],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        setup,
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('IDENTITIES', style: Glass.eyebrow(context)),
        ),
        for (var i = 0; i < _accounts.length; i++) ...[
          AccountSlab(
            key: ValueKey(_accounts[i].account.ghUsername),
            resolved: _accounts[i],
            profile:
                widget.services.profiles[_accounts[i].account.ghUsername],
            accent: Glass.accentFor(i),
            onSave: _save,
            onApplyToRepo: _applyToRepo,
            onTestSsh: _testSsh,
          ),
          const SizedBox(height: Glass.gutter),
        ],
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text('AUTOMATION', style: Glass.eyebrow(context)),
        ),
        _LaunchAtLoginSlab(
          onError: (message) => _tell(message, isError: true),
        ),
        const SizedBox(height: Glass.gutter),
        AutoSwitchSection(
          services: widget.services,
          accounts: _accounts.map((r) => r.account).toList(),
          onMessage: (message, {bool isError = false}) =>
              _tell(message, isError: isError),
        ),
      ],
    );
  }
}

/// Installs what GitSwitcher drives — gh and git — when either is missing.
/// Invisible once both are present.
class _SetupSlab extends StatefulWidget {
  const _SetupSlab({
    required this.services,
    required this.onMessage,
    required this.onInstalled,
  });

  final AppServices services;
  final void Function(String message, {bool isError}) onMessage;
  final Future<void> Function() onInstalled;

  @override
  State<_SetupSlab> createState() => _SetupSlabState();
}

class _SetupSlabState extends State<_SetupSlab> {
  bool? _gh;
  bool? _git;
  bool _installingGh = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final gh = await widget.services.gh.isInstalled();
    final git = await widget.services.tools.gitInstalled();
    if (!mounted) return;
    setState(() {
      _gh = gh;
      _git = git;
    });
  }

  Future<void> _installGh() async {
    setState(() => _installingGh = true);
    try {
      final version = await widget.services.tools.installGh();
      widget.onMessage('GitHub CLI $version installed. Add an account next.');
      await _check();
      await widget.onInstalled();
    } catch (error) {
      widget.onMessage('Could not install the GitHub CLI: $error',
          isError: true);
    } finally {
      if (mounted) setState(() => _installingGh = false);
    }
  }

  Future<void> _installGit() async {
    await widget.services.tools.installGit();
    widget.onMessage(
        "Follow Apple's installer, then press Check again when it finishes.");
  }

  @override
  Widget build(BuildContext context) {
    if (_gh == null || (_gh! && _git!)) return const SizedBox.shrink();

    Widget row(String name, String why, bool ok, Widget action) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(ok ? Icons.check_circle_outline : Icons.download_outlined,
                  size: 16,
                  color: ok ? Glass.live : Glass.secondaryText(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Glass.mono(context)),
                    Text(why, style: Glass.body(context, size: 12)),
                  ],
                ),
              ),
              if (!ok) action,
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: Glass.gutter),
      child: GlassSlab(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('Finish setting up',
                        style: Glass.display(context))),
                TextButton(onPressed: _check, child: const Text('Check again')),
              ],
            ),
            row(
              'GitHub CLI (gh)',
              'Switches accounts and signs you in. Downloaded from GitHub '
                  'and checked before it runs.',
              _gh!,
              FilledButton(
                onPressed: _installingGh ? null : _installGh,
                child: Text(_installingGh ? 'Installing…' : 'Install'),
              ),
            ),
            row(
              'git',
              "Sets your commit identity. Installed by Apple's Command Line "
                  'Tools; takes a few minutes.',
              _git!,
              FilledButton(onPressed: _installGit, child: const Text('Install')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaunchAtLoginSlab extends StatefulWidget {
  const _LaunchAtLoginSlab({required this.onError});

  final void Function(String message) onError;

  @override
  State<_LaunchAtLoginSlab> createState() => _LaunchAtLoginSlabState();
}

class _LaunchAtLoginSlabState extends State<_LaunchAtLoginSlab> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    LaunchAtLogin.isEnabled()
        .then((v) => mounted ? setState(() => _enabled = v) : null)
        .catchError((_) => null);
  }

  Future<void> _set(bool value) async {
    try {
      final result = await LaunchAtLogin.setEnabled(value);
      if (mounted) setState(() => _enabled = result);
    } on PlatformException catch (e) {
      widget.onError('Could not change Login Items: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassSlab(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open at login', style: Glass.display(context)),
                const SizedBox(height: 3),
                Text(
                  'Starts GitSwitcher when you log in or restart your Mac.',
                  style: Glass.body(context, size: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled ?? false,
            onChanged: _enabled == null ? null : _set,
            activeThumbColor: Glass.live,
          ),
        ],
      ),
    );
  }
}

/// Shown before starting a login, because signing in as an account that is
/// already present overwrites its token instead of adding a new account.
class _ReplaceWarningDialog extends StatelessWidget {
  const _ReplaceWarningDialog({required this.existing});

  final List<String> existing;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SizedBox(
          width: 400,
          child: GlassSlab(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BEFORE YOU SIGN IN', style: Glass.eyebrow(context)),
                const SizedBox(height: 10),
                Text('Sign in as a new account',
                    style: Glass.display(context, size: 18)),
                const SizedBox(height: 12),
                Text(
                  'Signing in again as an account you already have replaces '
                  'its token, and any extra permissions you granted before are '
                  'lost. Pick a different account on the GitHub page.',
                  style: Glass.body(context, size: 12.5),
                ),
                const SizedBox(height: 12),
                Text('ALREADY SIGNED IN', style: Glass.eyebrow(context)),
                const SizedBox(height: 6),
                for (final login in existing)
                  Text(login, style: Glass.mono(context)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Glass.primaryText(context)
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Glass.accents.first,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Continue',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Glass.primaryText(context).withValues(alpha: 0.07),
            border: Border.all(
              color: Glass.primaryText(context).withValues(alpha: 0.12),
            ),
          ),
          child: Icon(icon, size: 15, color: Glass.primaryText(context)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No identities yet', style: Glass.display(context, size: 19)),
            const SizedBox(height: 8),
            Text(
              'Press + above to sign in to a GitHub account. Add one for '
              'each account you want to switch between.',
              textAlign: TextAlign.center,
              style: Glass.body(context),
            ),
          ],
        ),
      ),
    );
  }
}
