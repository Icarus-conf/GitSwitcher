import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/account.dart';
import '../models/app_config.dart';
import '../models/directory_rule.dart';
import 'theme/glass.dart';
import 'widgets/glass_slab.dart';

/// Settings panel for directory-based automatic switching.
class AutoSwitchSection extends StatefulWidget {
  const AutoSwitchSection({
    super.key,
    required this.services,
    required this.accounts,
    required this.onMessage,
  });

  final AppServices services;
  final List<Account> accounts;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<AutoSwitchSection> createState() => _AutoSwitchSectionState();
}

class _AutoSwitchSectionState extends State<AutoSwitchSection> {
  AppConfig _config = const AppConfig();
  bool _hookInstalled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await widget.services.store.loadConfig();
    final installed = await widget.services.hooks.isInstalled();
    if (!mounted) return;
    setState(() {
      _config = config;
      _hookInstalled = installed;
      _loading = false;
    });
  }

  Future<void> _update(AppConfig config) async {
    await widget.services.store.saveConfig(config);
    if (!mounted) return;
    setState(() => _config = config);
  }

  Future<void> _setEnabled(bool enabled) async {
    await _update(_config.copyWith(autoSwitchEnabled: enabled));
    if (enabled && !_hookInstalled) await _installHook();
  }

  Future<void> _installHook() async {
    try {
      await widget.services.hooks.install();
      await _reload();
      widget.onMessage(
        'Shell hook installed. Open a new terminal tab for it to take effect.',
      );
    } on FormatException catch (error) {
      widget.onMessage(error.message, isError: true);
    } catch (error) {
      widget.onMessage('Could not edit ~/.zshrc: $error', isError: true);
    }
  }

  Future<void> _removeHook() async {
    try {
      await widget.services.hooks.uninstall();
      await _reload();
      widget.onMessage('Shell hook removed from ~/.zshrc.');
    } catch (error) {
      widget.onMessage('Could not edit ~/.zshrc: $error', isError: true);
    }
  }

  Future<void> _addRule() async {
    if (widget.accounts.isEmpty) return;

    final directory = await getDirectoryPath(confirmButtonText: 'Use folder');
    if (directory == null || !mounted) return;

    final account = await showDialog<Account>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Which account for ${directory.split('/').last}?'),
        children: [
          for (final account in widget.accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, account),
              child: Text(account.displayName),
            ),
        ],
      ),
    );
    if (account == null) return;

    // One rule per folder: adding the same folder twice replaces the mapping
    // rather than creating a silent conflict.
    final rules = List<DirectoryRule>.of(_config.rules)
      ..removeWhere((r) => r.pathPrefix == directory)
      ..add(DirectoryRule(
        pathPrefix: directory,
        ghUsername: account.ghUsername,
      ));

    await _update(_config.copyWith(rules: rules));
  }

  Future<void> _removeRule(DirectoryRule rule) async {
    final rules = List<DirectoryRule>.of(_config.rules)..remove(rule);
    await _update(_config.copyWith(rules: rules));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    return GlassSlab(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Switch by folder', style: Glass.display(context)),
                    const SizedBox(height: 3),
                    Text(
                      'Changes account when your terminal enters a folder.',
                      style: Glass.body(context, size: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _config.autoSwitchEnabled,
                onChanged: _setEnabled,
                activeThumbColor: Glass.live,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                _hookInstalled ? Icons.check_circle_outline : Icons.terminal,
                size: 14,
                color: _hookInstalled
                    ? Glass.live
                    : Glass.secondaryText(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _hookInstalled
                      ? 'Shell hook installed in ~/.zshrc'
                      : 'Shell hook not installed',
                  style: Glass.mono(context, size: 11.5),
                ),
              ),
              _MiniButton(
                label: _hookInstalled ? 'Remove hook' : 'Install hook',
                onPressed: _hookInstalled ? _removeHook : _installHook,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('FOLDER RULES', style: Glass.eyebrow(context)),
              const Spacer(),
              _MiniButton(
                label: 'Add folder',
                onPressed: widget.accounts.isEmpty ? null : _addRule,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_config.rules.isEmpty)
            Text(
              'No rules yet. Nothing switches automatically until you add one.',
              style: Glass.body(context, size: 12),
            )
          else
            for (final rule in _config.rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _shorten(rule.pathPrefix),
                        style: Glass.mono(
                          context,
                          color: Glass.primaryText(context)
                              .withValues(alpha: 0.78),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('→  ', style: Glass.body(context, size: 12)),
                    Text(
                      _labelFor(rule.ghUsername),
                      style: Glass.body(context, size: 12),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Remove rule',
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints.tightFor(width: 26, height: 26),
                      icon: const Icon(Icons.close),
                      color: Glass.secondaryText(context),
                      onPressed: () => _removeRule(rule),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _shorten(String path) {
    final home = Platform.environment['HOME'];
    if (home != null && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  String _labelFor(String ghUsername) {
    for (final account in widget.accounts) {
      if (account.ghUsername == ghUsername) return account.displayName;
    }
    return '$ghUsername (unknown account)';
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Glass.primaryText(context).withValues(alpha: 0.8),
        disabledForegroundColor:
            Glass.primaryText(context).withValues(alpha: 0.3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(
            color: Glass.primaryText(context).withValues(alpha: 0.14),
          ),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
