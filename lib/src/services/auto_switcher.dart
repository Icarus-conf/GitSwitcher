import 'dart:async';
import 'dart:io';

import '../models/account.dart';
import '../models/directory_rule.dart';
import '../models/switch_result.dart';

/// Watches the state file the shell hook writes and reports directory changes.
///
/// Polling rather than [File.watch]: the hook rewrites this file on every `cd`,
/// and FSEvents coalesces rapid rewrites unpredictably. A one-second poll of a
/// tiny file is cheap and never misses the final state.
class CwdWatcher {
  CwdWatcher({
    required File stateFile,
    Duration interval = const Duration(seconds: 1),
  })  : _stateFile = stateFile,
        _interval = interval;

  final File _stateFile;
  final Duration _interval;

  Timer? _timer;
  String? _lastSeen;
  final _controller = StreamController<String>.broadcast();

  /// Emits each new directory, never the same one twice in a row.
  Stream<String> get directories => _controller.stream;

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads the state file once. Exposed so tests need no real timer.
  Future<void> poll() async {
    try {
      if (!await _stateFile.exists()) return;
      final directory = (await _stateFile.readAsString()).trim();
      if (directory.isEmpty || directory == _lastSeen) return;

      _lastSeen = directory;
      if (!_controller.isClosed) _controller.add(directory);
    } catch (_) {
      // A half-written file is normal: the next poll picks it up.
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}

/// Decides whether a directory change should trigger an account switch.
///
/// Kept free of I/O so the whole policy is unit-testable: it answers "which
/// account should be active here, if any", and the caller performs the switch.
class AutoSwitchPolicy {
  const AutoSwitchPolicy({required this.matcher});

  final RuleMatcher matcher;

  /// The account to switch to, or null to do nothing.
  ///
  /// Returns null when auto-switching is off, no rule matches, the matched
  /// account is already active, or the rule names an account that no longer
  /// exists — switching to something unknown would be worse than doing
  /// nothing.
  Account? accountFor({
    required String directory,
    required bool enabled,
    required List<DirectoryRule> rules,
    required List<Account> accounts,
    required String? activeUsername,
  }) {
    if (!enabled) return null;

    final rule = matcher.match(directory, rules);
    if (rule == null) return null;
    if (rule.ghUsername == activeUsername) return null;

    for (final account in accounts) {
      if (account.ghUsername == rule.ghUsername) return account;
    }
    return null;
  }
}

/// The outcome of an automatic switch, for notification purposes.
class AutoSwitchEvent {
  const AutoSwitchEvent({required this.directory, required this.result});

  final String directory;
  final SwitchResult result;
}
