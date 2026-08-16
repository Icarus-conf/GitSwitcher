import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/services/notifier.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('describes a fully successful switch', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.ok('git identity'),
      StepResult.ok('ssh'),
    ]);

    expect(Notifier.describe(result), 'gh, git identity and SSH updated.');
  });

  test('names the steps that were skipped', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.skipped('git identity', 'no git name and email configured'),
      StepResult.skipped('ssh', 'no SSH key configured'),
    ]);

    expect(Notifier.describe(result), contains('skipped: git identity, ssh'));
  });

  test('names the steps that failed and why', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.ok('git identity'),
      StepResult.failed('ssh', 'markers are malformed'),
    ]);

    expect(
        Notifier.describe(result), contains('ssh failed: markers are malformed'));
  });

  test('runs osascript with the title and body', () async {
    final runner = FakeProcessRunner();

    await Notifier(runner).show(title: 'GitSwitcher', body: 'Switched to Work');

    expect(runner.calls.single, contains('/usr/bin/osascript'));
    expect(
        runner.calls.single, contains('display notification "Switched to Work"'));
    expect(runner.calls.single, contains('with title "GitSwitcher"'));
  });

  test('escapes quotes and backslashes in notification text', () async {
    final runner = FakeProcessRunner();

    await Notifier(runner).show(title: 'GitSwitcher', body: r'say "hi" \ bye');

    expect(runner.calls.single, contains(r'say \"hi\" \\ bye'));
  });
}
