import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/account_switcher.dart';
import 'package:git_switcher/src/services/gh_client.dart';
import 'package:git_switcher/src/services/git_identity_writer.dart';
import 'package:git_switcher/src/services/ssh_config_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File hostsFile;
  late File sshConfig;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_switch_test');
    hostsFile = File('${tempDir.path}/hosts.yml');
    sshConfig = File('${tempDir.path}/ssh_config');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  AccountSwitcher buildSwitcher(FakeProcessRunner runner) {
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const ['/opt/homebrew/bin', '/usr/bin'],
      exists: (path) =>
          path == '/opt/homebrew/bin/gh' || path == '/usr/bin/git',
    );
    return AccountSwitcher(
      gh: GhClient(runner: runner, locator: locator, hostsFile: hostsFile),
      git: GitIdentityWriter(runner: runner, locator: locator),
      ssh: SshConfigWriter(file: sshConfig, runner: runner),
    );
  }

  const fullAccount = Account(
    ghUsername: 'octocat',
    label: 'Work',
    gitName: 'Octo Cat',
    gitEmail: 'octo@example.com',
    sshKeyPath: '/Users/me/.ssh/id_work',
  );

  test('runs all three steps and reports them in order', () async {
    final result =
        await buildSwitcher(FakeProcessRunner()).switchTo(fullAccount);

    expect(result.ghUsername, 'octocat');
    expect(result.steps.map((s) => s.name), ['gh', 'git identity', 'ssh']);
    expect(result.allOk, isTrue);
  });

  test('runs the remaining steps when gh fails', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/opt/homebrew/bin/gh auth switch --hostname github.com --user octocat':
            const CommandResult(1, '', 'not logged in'),
      },
    );

    final result = await buildSwitcher(runner).switchTo(fullAccount);

    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'gh');
    expect(sshConfig.existsSync(), isTrue);
    expect(
      runner.calls,
      contains('/usr/bin/git config --global user.name Octo Cat'),
    );
  });

  test('reports skipped steps without marking the switch failed', () async {
    final result = await buildSwitcher(FakeProcessRunner())
        .switchTo(const Account(ghUsername: 'octocat'));

    expect(result.allOk, isTrue);
    expect(
      result.steps
          .where((s) => s.status == StepStatus.skipped)
          .map((s) => s.name),
      ['git identity', 'ssh'],
    );
  });

  test('reports an unwritable ssh config as a failed step only', () async {
    // A directory where the SSH config file should be makes writing throw.
    Directory(sshConfig.path).createSync(recursive: true);

    final result =
        await buildSwitcher(FakeProcessRunner()).switchTo(fullAccount);

    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'ssh');
    expect(result.steps.first.status, StepStatus.ok);
  });
}
