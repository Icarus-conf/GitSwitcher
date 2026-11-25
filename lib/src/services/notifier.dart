import 'package:flutter/services.dart';

import '../models/switch_result.dart';

/// Posts macOS notifications as GitSwitcher, with its name and icon.
///
/// The native side is in MainFlutterWindow.swift. If the user turned
/// notifications off, nothing is shown — their choice, not an error.
class Notifier {
  const Notifier();

  static const MethodChannel channel =
      MethodChannel('gitswitcher/notifications');

  Future<void> show({required String title, required String body}) async {
    try {
      await channel.invokeMethod<bool>('show', {'title': title, 'body': body});
    } on PlatformException {
      // A notification that cannot be shown must never break a switch.
    }
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
}
