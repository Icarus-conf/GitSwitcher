import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// Sets one repository's local git identity.
///
/// This is the safest way to use GitSwitcher day to day: a repo's local
/// identity overrides the global one and survives every later switch, so the
/// right email is attached to commits even if the active account is wrong.
class RepoIdentityWriter {
  RepoIdentityWriter({
    required ProcessRunner runner,
    required BinaryLocator locator,
    bool Function(String path)? isGitRepo,
  })  : _runner = runner,
        _locator = locator,
        _isGitRepo = isGitRepo ?? _defaultIsGitRepo;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
  final bool Function(String path) _isGitRepo;

  static const String stepName = 'repo identity';

  static bool _defaultIsGitRepo(String path) =>
      Directory('$path/.git').existsSync() || File('$path/.git').existsSync();

  Future<StepResult> apply(Account account, String repoPath) async {
    if (account.gitName.isEmpty || account.gitEmail.isEmpty) {
      return const StepResult.failed(
        stepName,
        'this account has no git name and email yet',
      );
    }

    if (!_isGitRepo(repoPath)) {
      return StepResult.failed(stepName, 'not a git repository: $repoPath');
    }

    final String git;
    try {
      git = await _locator.locate('git');
    } on BinaryNotFoundException catch (error) {
      return StepResult.failed(stepName, error.toString());
    }

    for (final entry in {
      'user.name': account.gitName,
      'user.email': account.gitEmail,
    }.entries) {
      final result = await _runner.run(
        git,
        ['-C', repoPath, 'config', '--local', entry.key, entry.value],
      );
      if (!result.ok) {
        return StepResult.failed(
          stepName,
          'setting ${entry.key} failed: ${result.errorText}',
        );
      }
    }

    return const StepResult.ok(stepName);
  }
}
