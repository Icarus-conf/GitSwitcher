import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';
import 'git_config_writer.dart';

/// Asks GitHub which account an SSH key actually signs in as.
///
/// A key that authenticates as the wrong account is the failure nothing else
/// catches: every switch step reports success and pushes still land on the
/// other account. `ssh -T git@github.com` answers "Hi `login`!", which is
/// compared with the account the key is configured for.
class SshTester {
  SshTester({
    required ProcessRunner runner,
    required BinaryLocator locator,
    required String home,
  }) : _runner = runner,
       _locator = locator,
       _home = home;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
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

    final String ssh;
    try {
      ssh = await _locator.locate('ssh');
    } on BinaryNotFoundException catch (error) {
      return StepResult.failed(stepName, error.toString());
    }

    // An empty config: the user's own could offer another key first and
    // report whichever account that one belongs to. A real empty file rather
    // than /dev/null, which Windows does not have.
    final dir = await Directory.systemTemp.createTemp('gitswitcher-ssh');
    final emptyConfig = File('${dir.path}/config')..createSync();
    final CommandResult result;
    try {
      result = await _runner.run(ssh, [
        '-F', emptyConfig.path,
        '-i', key,
        '-o', 'IdentitiesOnly=yes',
        // Never prompt — there is no terminal to answer in.
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'ConnectTimeout=10',
        '-T', 'git@github.com',
      ]);
    } finally {
      await dir.delete(recursive: true);
    }

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
