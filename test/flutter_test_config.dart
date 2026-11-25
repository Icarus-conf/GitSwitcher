import 'dart:async';

import 'package:git_switcher/src/platform/host.dart';

/// Runs before every test file.
///
/// Most tests feed fake command output and expect macOS paths, so they pin
/// macOS behaviour and mean the same thing when CI runs them on Windows.
/// Tests that drive real tools set `Host.current` back to the real system.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Host.current = Host.macos;
  await testMain();
}
