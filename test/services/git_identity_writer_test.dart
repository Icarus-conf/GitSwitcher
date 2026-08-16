import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/git_identity_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  GitIdentityWriter buildWriter(
    FakeProcessRunner runner, {
    bool gitInstalled = true,
  }) {
    return GitIdentityWriter(
      runner: runner,
      locator: BinaryLocator(
        runner: runner,
        searchDirs: const ['/usr/bin'],
        exists: (path) => gitInstalled && path == '/usr/bin/git',
      ),
    );
  }

  const complete = Account(
    ghUsername: 'octocat',
    gitName: 'Octo Cat',
    gitEmail: 'octo@example.com',
  );

  test('sets both global name and email', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner).apply(complete);

    expect(step.status, StepStatus.ok);
    expect(runner.calls, [
      '/usr/bin/git config --global user.name Octo Cat',
      '/usr/bin/git config --global user.email octo@example.com',
    ]);
  });

  test('skips when the git name is empty', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner)
        .apply(const Account(ghUsername: 'octocat', gitEmail: 'a@b.com'));

    expect(step.status, StepStatus.skipped);
    expect(runner.calls, isEmpty);
  });

  test('skips when the git email is empty', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner)
        .apply(const Account(ghUsername: 'octocat', gitName: 'Octo Cat'));

    expect(step.status, StepStatus.skipped);
    expect(runner.calls, isEmpty);
  });

  test('fails with the stderr text when git exits non-zero', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(1, '', 'could not lock config file'),
    );

    final step = await buildWriter(runner).apply(complete);

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('could not lock'));
  });

  test('does not set the email if setting the name failed', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/usr/bin/git config --global user.name Octo Cat':
            const CommandResult(1, '', 'permission denied'),
      },
    );

    await buildWriter(runner).apply(complete);

    expect(
      runner.calls,
      isNot(contains(
        '/usr/bin/git config --global user.email octo@example.com',
      )),
    );
  });

  test('fails with a clear message when git is not installed', () async {
    final step = await buildWriter(FakeProcessRunner(), gitInstalled: false)
        .apply(complete);

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('git'));
  });
}
