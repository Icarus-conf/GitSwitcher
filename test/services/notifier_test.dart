import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/services/notifier.dart';

import 'package:flutter/services.dart';

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

  test('posts the title and body to the native side', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final sent = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Notifier.channel, (call) async {
      sent.add(call);
      return true;
    });

    await const Notifier().show(title: 'GitSwitcher', body: 'Switched "Work"');

    expect(sent.single.method, 'show');
    expect(sent.single.arguments,
        {'title': 'GitSwitcher', 'body': 'Switched "Work"'});
  });

  test('a failure on the native side never escapes', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Notifier.channel,
            (_) async => throw PlatformException(code: 'denied'));

    await const Notifier().show(title: 't', body: 'b');
  });

  test('on Windows, posts through the tray icon balloon', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Host.current = Host.windows;
    addTearDown(() => Host.current = Host.macos);
    final sent = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Notifier.trayChannel, (call) async {
      sent.add(call);
      return true;
    });

    await const Notifier().show(title: 'T', body: 'B');

    expect(sent.single.method, 'showBalloon');
    expect(sent.single.arguments, {'title': 'T', 'body': 'B'});
  });
}
