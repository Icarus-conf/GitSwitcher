import '../models/switch_result.dart';
import '../platform/process_runner.dart';

/// Posts macOS notifications through osascript.
///
/// Shelling out avoids a native plugin and keeps this unit testable with the
/// same fake process runner as the rest of the app.
class Notifier {
  const Notifier(this._runner);

  final ProcessRunner _runner;

  static const String appName = 'GitSwitcher';

  Future<void> show({required String title, required String body}) async {
    final script =
        'display notification "${_escape(body)}" with title "${_escape(title)}"';
    await _runner.run('/usr/bin/osascript', ['-e', script]);
  }

  Future<void> showSwitchResult(SwitchResult result, String displayName) {
    final prefix = result.allOk
        ? 'Switched to $displayName'
        : 'Switch to $displayName incomplete';
    return show(title: prefix, body: describe(result));
  }

  /// A one-line summary of what actually happened.
  static String describe(SwitchResult result) {
    final failed = result.failedSteps
        .map((s) => '${s.name} failed: ${s.message}')
        .join('; ');
    if (failed.isNotEmpty) return failed;

    final skipped = result.steps
        .where((s) => s.status == StepStatus.skipped)
        .map((s) => s.name)
        .join(', ');
    if (skipped.isNotEmpty) return 'Done — skipped: $skipped.';

    return 'gh, git identity and SSH updated.';
  }

  static String _escape(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
