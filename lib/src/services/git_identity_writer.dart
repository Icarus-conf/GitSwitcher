import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// Sets the global git commit identity.
///
/// Both name and email must be configured, otherwise the step is skipped:
/// writing half an identity would leave commits attributed to a mix of two
/// accounts, which is worse than leaving the previous identity in place.
class GitIdentityWriter {
  GitIdentityWriter({
    required ProcessRunner runner,
    required BinaryLocator locator,
  })  : _runner = runner,
        _locator = locator;

  final ProcessRunner _runner;
  final BinaryLocator _locator;

  static const String stepName = 'git identity';

  Future<StepResult> apply(Account account) async {
    if (account.gitName.isEmpty || account.gitEmail.isEmpty) {
      return const StepResult.skipped(
        stepName,
        'no git name and email configured',
      );
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
        ['config', '--global', entry.key, entry.value],
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
