import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../models/account.dart';
import '../platform/host.dart';
import '../services/git_config_writer.dart';
import 'theme/glass.dart';
import 'widgets/glass_slab.dart';

/// "Clone as…": a repository URL and an account, and the clone belongs to
/// that account from its first commit.
class CloneDialog extends StatefulWidget {
  const CloneDialog({super.key, required this.services, required this.accounts});

  final AppServices services;
  final List<Account> accounts;

  /// Returns the cloned repo's path, or null when cancelled.
  static Future<String?> show(
    BuildContext context,
    AppServices services,
    List<Account> accounts,
  ) =>
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CloneDialog(services: services, accounts: accounts),
      );

  @override
  State<CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<CloneDialog> {
  final _url = TextEditingController();
  late Account _account = widget.accounts.first;
  bool _cloning = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// The account's first folder rule, if it has one; otherwise ask.
  Future<String?> _destination() async {
    final config = await widget.services.store.loadConfig();
    final home = Host.current.home;
    for (final rule in config.rules) {
      if (rule.ghUsername == _account.ghUsername) {
        return expandTilde(rule.pathPrefix, home);
      }
    }
    return getDirectoryPath(confirmButtonText: 'Clone here');
  }

  Future<void> _clone() async {
    if (_url.text.trim().isEmpty) return;
    final parent = await _destination();
    if (parent == null || !mounted) return;

    setState(() {
      _cloning = true;
      _error = null;
    });
    try {
      // Make sure the account's include file is current before git reads it.
      await widget.services.syncGitConfig();
      final path = await widget.services.cloner.clone(
        input: _url.text,
        account: _account,
        parentDir: parent,
      );
      if (mounted) Navigator.of(context).pop(path);
    } catch (error) {
      if (mounted) {
        setState(() {
          _cloning = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SizedBox(
          width: 440,
          child: GlassSlab(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CLONE AS', style: Glass.eyebrow(context)),
                const SizedBox(height: 10),
                Text('Clone a repository', style: Glass.display(context, size: 18)),
                const SizedBox(height: 14),
                TextField(
                  controller: _url,
                  autofocus: true,
                  enabled: !_cloning,
                  style: Glass.mono(context, size: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'acme/api, or a GitHub URL',
                  ),
                  onSubmitted: (_) => _clone(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final account in widget.accounts)
                      ChoiceChip(
                        label: Text(account.displayName),
                        selected: account == _account,
                        onSelected: _cloning
                            ? null
                            : (_) => setState(() => _account = account),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Goes into this account\'s folder if it has one. The repo '
                  'commits, signs and pushes as ${_account.displayName} '
                  'wherever it is.',
                  style: Glass.body(context, size: 12),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: Glass.body(context, size: 12)
                          .copyWith(color: const Color(0xFFFF453A))),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    TextButton(
                      onPressed:
                          _cloning ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _cloning ? null : _clone,
                      child: Text(_cloning ? 'Cloning…' : 'Clone'),
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
