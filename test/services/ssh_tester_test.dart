import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/ssh_tester.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('gitswitcher_sshtest');
    File('${home.path}/.ssh/id_work').createSync(recursive: true);
  });

  tearDown(() => home.deleteSync(recursive: true));

  const account =
      Account(ghUsername: 'Octocat', sshKeyPath: '~/.ssh/id_work');

  Future<StepResult> run(CommandResult reply) => SshTester(
        runner: FakeProcessRunner(fallback: reply),
        home: home.path,
      ).test(account);

  test('passes when GitHub greets the same login, ignoring case', () async {
    final step = await run(const CommandResult(1, '',
        "Hi octocat! You've successfully authenticated, but GitHub does not "
        'provide shell access.'));

    expect(step.status, StepStatus.ok);
  });

  test('fails when the key belongs to another account', () async {
    final step = await run(const CommandResult(1, '', 'Hi hubot! You have...'));

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('signs in as hubot'));
  });

  test('explains a rejected key', () async {
    final step = await run(
        const CommandResult(255, '', 'git@github.com: Permission denied (publickey).'));

    expect(step.message, contains('rejected'));
  });

  test('passes the expanded key path to ssh', () async {
    final runner = FakeProcessRunner();
    await SshTester(runner: runner, home: home.path).test(account);

    expect(runner.calls.single, contains('-i ${home.path}/.ssh/id_work'));
  });

  test('fails without running ssh when the key file is missing', () async {
    final runner = FakeProcessRunner();
    final step = await SshTester(runner: runner, home: home.path)
        .test(const Account(ghUsername: 'x', sshKeyPath: '~/.ssh/nope'));

    expect(step.status, StepStatus.failed);
    expect(runner.calls, isEmpty);
  });
}
