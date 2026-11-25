import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/process_runner.dart';
import 'git_config_writer.dart';

/// Asks GitHub which account an SSH key actually signs in as.
///
/// A key that authenticates as the wrong account is the failure nothing else
/// catches: every switch step reports success and pushes still land on the
/// other account. `ssh -T git@github.com` answers "Hi `login`!", which is
/// compared with the account the key is configured for.
class SshTester {
  SshTester({required ProcessRunner runner, required String home})
      : _runner = runner,
        _home = home;

  final ProcessRunner _runner;
  final String _home;

  static const String stepName = 'ssh test';
  static final RegExp _greeting = RegExp(r'Hi ([A-Za-z0-9-]+)!');

  Future<StepResult> test(Account account) async {
    if (account.sshKeyPath.isEmpty) {
      return const StepResult.failed(stepName, 'no SSH key is set');
    }
    final key = expandTilde(account.sshKeyPath, _home);
    if (!await File(key).exists()) {
      return StepResult.failed(stepName, 'no key file at $key');
    }

    final result = await _runner.run('/usr/bin/ssh', [
      // Only this key: the user's config could otherwise offer another key
      // first and report whichever account that one belongs to.
      '-F', '/dev/null',
      '-i', key,
      '-o', 'IdentitiesOnly=yes',
      // Never prompt — there is no terminal to answer in.
      '-o', 'BatchMode=yes',
      '-o', 'StrictHostKeyChecking=accept-new',
      '-o', 'ConnectTimeout=10',
      '-T', 'git@github.com',
    ]);

    final match = _greeting.firstMatch('${result.stdout}\n${result.stderr}');
    if (match == null) {
      final denied = result.stderr.contains('Permission denied');
      return StepResult.failed(
        stepName,
        denied
            ? 'GitHub rejected this key. Add its .pub to the account, or run '
                'ssh-add if the key has a passphrase.'
            : result.errorText,
      );
    }

    final login = match.group(1)!;
    if (login.toLowerCase() != account.ghUsername.toLowerCase()) {
      return StepResult.failed(
        stepName,
        'this key signs in as $login, not ${account.ghUsername}',
      );
    }
    return const StepResult.ok(stepName);
  }
}
