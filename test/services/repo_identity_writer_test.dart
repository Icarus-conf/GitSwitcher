import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/repo_identity_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  RepoIdentityWriter buildWriter(
    FakeProcessRunner runner, {
    bool isRepo = true,
  }) {
    return RepoIdentityWriter(
      runner: runner,
      locator: BinaryLocator(
        runner: runner,
        searchDirs: const ['/usr/bin'],
        exists: (p) => p == '/usr/bin/git',
      ),
      isGitRepo: (_) => isRepo,
    );
  }

  const account = Account(
    ghUsername: 'octocat',
    gitName: 'Octo Cat',
    gitEmail: 'octo@example.com',
  );

  test('sets local name and email in the given repo', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner).apply(account, '/repos/work');

    expect(step.status, StepStatus.ok);
    expect(runner.calls, [
      '/usr/bin/git -C /repos/work config --local user.name Octo Cat',
      '/usr/bin/git -C /repos/work config --local user.email octo@example.com',
    ]);
  });

  test('refuses a path that is not a git repository', () async {
    final runner = FakeProcessRunner();

    final step =
        await buildWriter(runner, isRepo: false).apply(account, '/tmp/nope');

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('not a git repository'));
    expect(runner.calls, isEmpty);
  });

  test('refuses an account with no identity configured', () async {
    final runner = FakeProcessRunner();

    final step = await buildWriter(runner)
        .apply(const Account(ghUsername: 'octocat'), '/repos/work');

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('no git name and email'));
    expect(runner.calls, isEmpty);
  });

  test('reports the stderr text when git fails', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(1, '', 'not a git dir'),
    );

    final step = await buildWriter(runner).apply(account, '/repos/work');

    expect(step.status, StepStatus.failed);
    expect(step.message, contains('not a git dir'));
  });

  test('does not set email when setting name failed', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/usr/bin/git -C /repos/work config --local user.name Octo Cat':
            const CommandResult(1, '', 'denied'),
      },
    );

    await buildWriter(runner).apply(account, '/repos/work');

    expect(runner.calls, hasLength(1));
  });
}
