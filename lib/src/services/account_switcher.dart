import '../models/account.dart';
import '../models/switch_result.dart';
import 'gh_client.dart';
import 'git_identity_writer.dart';
import 'ssh_config_writer.dart';

/// Runs the three switch steps and collects their outcomes.
///
/// Steps are deliberately independent: a failure in one must not hide or
/// prevent the others, so the user always learns exactly how far the switch
/// got rather than being told only that "something failed".
class AccountSwitcher {
  AccountSwitcher({
    required GhClient gh,
    required GitIdentityWriter git,
    required SshConfigWriter ssh,
  })  : _gh = gh,
        _git = git,
        _ssh = ssh;

  final GhClient _gh;
  final GitIdentityWriter _git;
  final SshConfigWriter _ssh;

  Future<SwitchResult> switchTo(Account account) async {
    final steps = [
      await _guard(GhClient.stepName, () => _gh.switchTo(account.ghUsername)),
      await _guard(GitIdentityWriter.stepName, () => _git.apply(account)),
      await _guard(SshConfigWriter.stepName, () => _ssh.apply(account)),
    ];

    return SwitchResult(account.ghUsername, steps);
  }

  Future<StepResult> _guard(
    String stepName,
    Future<StepResult> Function() step,
  ) async {
    try {
      return await step();
    } catch (error) {
      return StepResult.failed(stepName, error.toString());
    }
  }
}
