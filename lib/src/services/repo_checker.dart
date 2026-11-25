import 'dart:io';

import '../models/account.dart';
import '../models/app_config.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';
import 'git_config_writer.dart';

/// One repository whose identity does not match its rule.
class RepoFinding {
  const RepoFinding({
    required this.path,
    required this.expected,
    required this.problem,
    this.localOverride = false,
  });

  final String path;
  final Account expected;
  final String problem;

  /// True when the repo's own `.git/config` sets an identity that beats the
  /// rule. That one is fixable: removing it lets the rule apply.
  final bool localOverride;
}

/// Looks through the folders that have rules for repos that will commit, or
/// already did commit, as the wrong one of the user's accounts.
///
/// Only the user's own accounts count as "wrong": commits by teammates in a
/// shared repo are normal and never flagged.
class RepoChecker {
  RepoChecker({
    required ProcessRunner runner,
    required BinaryLocator locator,
    required String home,
  })  : _runner = runner,
        _locator = locator,
        _home = home;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
  final String _home;

  /// Folders never worth descending into; they can hold thousands of entries
  /// and never the user's own repos.
  static const _skip = {
    'node_modules', 'build', 'dist', 'Pods', 'vendor', '.venv', 'venv',
    'target', '.dart_tool', 'Library',
  };

  // ponytail: depth-limited walk; raise maxDepth if people keep repos deeper.
  static const int maxDepth = 4;

  /// The repos checked, and what is wrong with any of them.
  Future<({int checked, List<RepoFinding> findings})> check(
    AppConfig config,
  ) async {
    final git = await _locator.locate('git');
    final byLogin = {for (final a in config.accounts) a.ghUsername: a};
    final ownEmails = {
      for (final a in config.accounts)
        if (a.gitEmail.isNotEmpty) a.gitEmail.toLowerCase(): a,
    };

    final repos = <String>{};
    for (final rule in config.rules) {
      await _findRepos(
          Directory(expandTilde(rule.pathPrefix, _home)), 0, repos);
    }

    final findings = <RepoFinding>[];
    for (final repo in repos) {
      final expected = byLogin[await _ruleAccount(git, repo, config)];
      if (expected == null || expected.gitEmail.isEmpty) continue;
      final want = expected.gitEmail.toLowerCase();

      final local = (await _runner.run(
              git, ['-C', repo, 'config', '--local', 'user.email']))
          .stdout
          .trim()
          .toLowerCase();
      if (local.isNotEmpty && local != want) {
        findings.add(RepoFinding(
          path: repo,
          expected: expected,
          problem: 'its own settings commit as $local',
          localOverride: true,
        ));
        continue;
      }

      final log = await _runner.run(
          git, ['-C', repo, 'log', '-n', '30', '--format=%ae']);
      final wrong = log.stdout
          .split('\n')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty && e != want && ownEmails.containsKey(e))
          .toList();
      if (wrong.isNotEmpty) {
        final other = ownEmails[wrong.first]!;
        findings.add(RepoFinding(
          path: repo,
          expected: expected,
          problem: '${wrong.length} of the last 30 commits used '
              "${other.displayName}'s email",
        ));
      }
    }
    return (checked: repos.length, findings: findings);
  }

  /// Removes a repo's own identity so its rule applies again.
  Future<void> removeLocalIdentity(String repo) async {
    final git = await _locator.locate('git');
    for (final key in ['user.email', 'user.name']) {
      await _runner.run(git, ['-C', repo, 'config', '--local', '--unset', key]);
    }
  }

  /// Which account the rules give [repo]: an organization rule matching its
  /// origin beats the most specific folder, as in the written git config.
  Future<String?> _ruleAccount(String git, String repo, AppConfig config) async {
    if (!config.autoSwitchEnabled) return null;
    final origin = (await _runner.run(
            git, ['-C', repo, 'remote', 'get-url', 'origin']))
        .stdout
        .trim();
    final owner = RegExp(r'github\.com[/:]([^/]+)/').firstMatch(origin)?.group(1);
    if (owner != null) {
      for (final rule in config.orgRules) {
        if (rule.org.toLowerCase() == owner.toLowerCase()) {
          return rule.ghUsername;
        }
      }
    }

    String? best;
    var bestLength = -1;
    final target = repo.replaceAll(r'\', '/');
    for (final rule in config.rules) {
      final prefix =
          expandTilde(rule.pathPrefix, _home).replaceAll(r'\', '/');
      final trimmed = prefix.endsWith('/')
          ? prefix.substring(0, prefix.length - 1)
          : prefix;
      if ((target == trimmed || target.startsWith('$trimmed/')) &&
          trimmed.length > bestLength) {
        best = rule.ghUsername;
        bestLength = trimmed.length;
      }
    }
    return best;
  }

  Future<void> _findRepos(Directory dir, int depth, Set<String> out) async {
    if (depth > maxDepth || !await dir.exists()) return;
    if (await Directory('${dir.path}/.git').exists() ||
        await File('${dir.path}/.git').exists()) {
      out.add(dir.path);
      return; // A repo's own subfolders are its business.
    }
    try {
      await for (final entry in dir.list(followLinks: false)) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        if (entry is Directory && !name.startsWith('.') && !_skip.contains(name)) {
          await _findRepos(entry, depth + 1, out);
        }
      }
    } on FileSystemException {
      // Unreadable folder: skip it rather than abandon the whole check.
    }
  }
}
