
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_services.dart';
import '../platform/host.dart';
import '../models/account.dart';
import '../models/app_config.dart';
import '../models/directory_rule.dart';
import '../models/switch_result.dart';
import '../services/repo_checker.dart';
import 'theme/glass.dart';
import 'widgets/glass_slab.dart';

/// Settings panel for per-folder identities, applied through git's own
/// `includeIf` so they hold in every terminal and editor at once.
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final config = await widget.services.store.loadConfig();
    if (!mounted) return;
    setState(() {
      _config = config;
      _loading = false;
    });
  }

  /// Saves, then rewrites ~/.gitconfig to match. A failed rewrite is reported
  /// rather than swallowed: the rule would look active while doing nothing.
  Future<void> _update(AppConfig config) async {
    try {
      await widget.services.store.saveConfig(config);
      if (mounted) setState(() => _config = config);
      final step = await widget.services.syncGitConfig();
      if (step.status == StepStatus.failed) {
        widget.onMessage('Could not update ~/.gitconfig: ${step.message}',
            isError: true);
      }
    } catch (error) {
      widget.onMessage('Could not save: $error', isError: true);
    }
  }

  Future<void> _setEnabled(bool enabled) =>
      _update(_config.copyWith(autoSwitchEnabled: enabled));

  Future<void> _addRule() async {
    if (widget.accounts.isEmpty) return;

    final directory = await getDirectoryPath(confirmButtonText: 'Use folder');
    if (directory == null || !mounted) return;

    final account =
        await _pickAccount(directory.split(RegExp(r'[/\\]')).last);
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

  bool _checking = false;

  Future<void> _checkRepos() async {
    setState(() => _checking = true);
    try {
      final result = await widget.services.repoChecker.check(_config);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _RepoCheckDialog(
          checked: result.checked,
          findings: result.findings,
          onFix: widget.services.repoChecker.removeLocalIdentity,
        ),
      );
    } catch (error) {
      widget.onMessage('Could not check repos: $error', isError: true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<Account?> _pickAccount(String what) => showDialog<Account>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Which account for $what?'),
          children: [
            for (final account in widget.accounts)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, account),
                child: Text(account.displayName),
              ),
          ],
        ),
      );

  Future<void> _addOrgRule() async {
    if (widget.accounts.isEmpty) return;
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub organization'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'acme, or a link to one of its repos',
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.trim().isEmpty || !mounted) return;

    final parsed = OrgRule.parse(input, '');
    if (!parsed.isValid) {
      widget.onMessage('"${input.trim()}" is not a GitHub organization name.',
          isError: true);
      return;
    }
    final account = await _pickAccount(parsed.org);
    if (account == null) return;

    // One rule per organization, as with folders.
    final orgRules = List<OrgRule>.of(_config.orgRules)
      ..removeWhere((r) => r.org.toLowerCase() == parsed.org.toLowerCase())
      ..add(OrgRule(org: parsed.org, ghUsername: account.ghUsername));
    await _update(_config.copyWith(orgRules: orgRules));
  }

  Future<void> _removeOrgRule(OrgRule rule) async {
    final orgRules = List<OrgRule>.of(_config.orgRules)..remove(rule);
    await _update(_config.copyWith(orgRules: orgRules));
  }

  Widget _ruleRow(String label, String ghUsername, VoidCallback onRemove) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Glass.mono(
                  context,
                  color: Glass.primaryText(context).withValues(alpha: 0.78),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('→  ', style: Glass.body(context, size: 12)),
            Text(_labelFor(ghUsername), style: Glass.body(context, size: 12)),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Remove rule',
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              icon: const Icon(Icons.close),
              color: Glass.secondaryText(context),
              onPressed: onRemove,
            ),
          ],
        ),
      );

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
                    Text('Identity by folder or organization',
                        style: Glass.display(context)),
                    const SizedBox(height: 3),
                    Text(
                      'Repos inside a folder, or from a GitHub organization, '
                      'commit, sign and push as its account — in every '
                      'terminal and editor. An organization beats a folder. '
                      'The menu account and gh are not changed.',
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
              'No folders yet. Add one to give its repos their own identity.',
              style: Glass.body(context, size: 12),
            )
          else
            for (final rule in _config.rules)
              _ruleRow(_shorten(rule.pathPrefix), rule.ghUsername,
                  () => _removeRule(rule)),
          if (_config.rules.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MiniButton(
              label: _checking ? 'Checking…' : 'Check repos in these folders',
              onPressed: _checking ? null : _checkRepos,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Text('ORGANIZATIONS', style: Glass.eyebrow(context)),
              const Spacer(),
              _MiniButton(
                label: 'Add organization',
                onPressed: widget.accounts.isEmpty ? null : _addOrgRule,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_config.orgRules.isEmpty)
            Text(
              'None yet. "acme" here sends every acme repo to one account, '
              'wherever it is cloned.',
              style: Glass.body(context, size: 12),
            )
          else
            for (final rule in _config.orgRules)
              _ruleRow('github.com/${rule.org}', rule.ghUsername,
                  () => _removeOrgRule(rule)),
        ],
      ),
    );
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

/// Results of a repo check, with a fix for each repo whose own settings
/// override its rule.
class _RepoCheckDialog extends StatefulWidget {
  const _RepoCheckDialog({
    required this.checked,
    required this.findings,
    required this.onFix,
  });

  final int checked;
  final List<RepoFinding> findings;
  final Future<void> Function(String repo) onFix;

  @override
  State<_RepoCheckDialog> createState() => _RepoCheckDialogState();
}

class _RepoCheckDialogState extends State<_RepoCheckDialog> {
  final _fixed = <String>{};

  @override
  Widget build(BuildContext context) {
    final findings = widget.findings;
    return AlertDialog(
      title: Text(findings.isEmpty
          ? 'All ${widget.checked} repos look right'
          : '${findings.length} of ${widget.checked} repos need a look'),
      content: SizedBox(
        width: 480,
        child: findings.isEmpty
            ? const Text('Every repo in your folders uses the account its rule '
                'gives it, and none has recent commits from your other '
                'accounts.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final f in findings)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_shorten(f.path),
                          style: Glass.mono(context)),
                      subtitle: Text(
                        'Should be ${f.expected.displayName}, but ${f.problem}.'
                        '${f.localOverride ? '' : ' Past commits stay as they are.'}',
                      ),
                      trailing: !f.localOverride
                          ? null
                          : _fixed.contains(f.path)
                              ? const Icon(Icons.check, color: Glass.live)
                              : TextButton(
                                  onPressed: () async {
                                    await widget.onFix(f.path);
                                    setState(() => _fixed.add(f.path));
                                  },
                                  child: const Text('Use the rule'),
                                ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// [path] with the home folder written as `~`.
String _shorten(String path) {
  final home = Host.current.home;
  if (home.isNotEmpty && path.startsWith(home)) {
    return '~${path.substring(home.length)}';
  }
  return path;
}
