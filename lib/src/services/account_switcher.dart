import '../models/account.dart';
import '../models/switch_result.dart';
import 'account_store.dart';
import 'gh_client.dart';
import 'git_config_writer.dart';
import 'git_identity_writer.dart';
import 'ssh_config_writer.dart';

/// Runs the switch steps and collects their outcomes.
///
/// Steps are deliberately independent: a failure in one must not hide or
/// prevent the others, so the user always learns exactly how far the switch
/// got rather than being told only that "something failed".
class AccountSwitcher {
  AccountSwitcher({
    required GhClient gh,
    required GitIdentityWriter git,
    required SshConfigWriter ssh,
    required GitConfigWriter gitConfig,
    required AccountStore store,
  })  : _gh = gh,
        _git = git,
        _ssh = ssh,
        _gitConfig = gitConfig,
        _store = store;

  final GhClient _gh;
  final GitIdentityWriter _git;
  final SshConfigWriter _ssh;
  final GitConfigWriter _gitConfig;
  final AccountStore _store;

  Future<SwitchResult> switchTo(Account account) async {
    final steps = [
      await _guard(GhClient.stepName, () => _gh.switchTo(account.ghUsername)),
      await _guard(GitIdentityWriter.stepName, () => _git.apply(account)),
      await _guard(SshConfigWriter.stepName, () => _ssh.apply(account)),
      // Last, so its block lands after any [user] section the git step added.
      await _guard(
        GitConfigWriter.stepName,
        () async =>
            _gitConfig.sync(await _store.loadConfig(), account.ghUsername),
      ),
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
