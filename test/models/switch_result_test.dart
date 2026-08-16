import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';

void main() {
  test('StepResult.ok carries no message', () {
    final step = StepResult.ok('gh');
    expect(step.name, 'gh');
    expect(step.status, StepStatus.ok);
    expect(step.message, isNull);
  });

  test('StepResult.skipped carries its reason', () {
    final step = StepResult.skipped('ssh', 'no SSH key configured');
    expect(step.status, StepStatus.skipped);
    expect(step.message, 'no SSH key configured');
  });

  test('StepResult.failed carries its reason', () {
    final step = StepResult.failed('gh', 'gh not found');
    expect(step.status, StepStatus.failed);
    expect(step.message, 'gh not found');
  });

  test('SwitchResult is allOk when nothing failed', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.skipped('ssh', 'no SSH key configured'),
    ]);
    expect(result.allOk, isTrue);
    expect(result.anyFailed, isFalse);
  });

  test('SwitchResult reports failure when any step failed', () {
    final result = SwitchResult('octocat', [
      StepResult.ok('gh'),
      StepResult.failed('ssh', 'markers malformed'),
    ]);
    expect(result.allOk, isFalse);
    expect(result.anyFailed, isTrue);
    expect(result.failedSteps.single.name, 'ssh');
  });
}
