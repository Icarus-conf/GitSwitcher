import 'dart:async';

import '../platform/binary_locator.dart';
import '../platform/process_starter.dart';
import 'gh_client.dart';

/// Drives `gh auth login --web` and surfaces its one-time code.
///
/// gh prints a device code, opens a browser, then blocks until the user
/// finishes. The code has to be shown while the process is still running,
/// which is why this streams output instead of waiting for exit.
class GhLoginSession {
  GhLoginSession({
    required ProcessStarter starter,
    required BinaryLocator locator,
    GhClient? gh,
  })  : _starter = starter,
        _locator = locator,
        _gh = gh;

  final ProcessStarter _starter;
  final BinaryLocator _locator;

  /// Used to put the active account back if the login is abandoned.
  final GhClient? _gh;

  /// gh renders the code as `XXXX-XXXX`.
  static final RegExp codePattern = RegExp(r'\b([A-Z0-9]{4}-[A-Z0-9]{4})\b');

  /// Launched without a terminal, gh does not open a browser itself — it
  /// prints this URL and waits. The app has to offer the link.
  static final RegExp urlPattern =
      RegExp(r'(https://\S*github\.com/login/device\S*)');

  StartedProcess? _process;

  final _codes = StreamController<String>.broadcast();
  final _urls = StreamController<String>.broadcast();

  /// Emits the one-time code as soon as gh prints it.
  Stream<String> get codes => _codes.stream;

  /// Emits the device-activation URL the user must open.
  Stream<String> get urls => _urls.stream;

  /// Scopes requested on top of gh's defaults.
  ///
  /// gh's default set omits `workflow`, and re-authenticating an account
  /// *replaces* its token rather than extending it. Without asking for this
  /// explicitly, logging in again quietly strips the caller's ability to push
  /// changes under `.github/workflows/`.
  static const List<String> extraScopes = ['workflow'];

  /// Starts the login flow and completes when gh exits.
  ///
  /// Returns true when the login succeeded.
  Future<bool> run({String hostname = 'github.com'}) async {
    final String gh;
    try {
      gh = await _locator.locate('gh');
    } on BinaryNotFoundException {
      await _closeStreams();
      return false;
    }

    // gh makes the account being signed in as active the moment the flow
    // starts, and leaves it that way even if the user walks off. Remembering
    // this now is the only chance to undo that.
    final previousActive = (await _gh?.discover())?.activeUsername;

    final process = await _starter.start(gh, [
      'auth',
      'login',
      '--hostname',
      hostname,
      '--git-protocol',
      'https',
      '--scopes',
      extraScopes.join(','),
      // Both flags exist to avoid prompts that would block forever without a
      // terminal to answer them.
      '--skip-ssh-key',
      '--web',
    ]);
    _process = process;

    final drained = Completer<void>();
    final subscription = process.lines.listen(
      (line) {
        final code = codePattern.firstMatch(line);
        if (code != null && !_codes.isClosed) _codes.add(code.group(1)!);

        final url = urlPattern.firstMatch(line);
        if (url != null && !_urls.isClosed) _urls.add(url.group(1)!);
      },
      onDone: () => drained.complete(),
      onError: (_) => drained.complete(),
      cancelOnError: true,
    );

    final exitCode = await process.exitCode;

    // Exiting does not mean its output has been read. Without this wait, a code
    // printed on a later line can be dropped between exit and teardown.
    await drained.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );

    await subscription.cancel();
    await _closeStreams();
    _process = null;

    final succeeded = exitCode == 0;
    if (!succeeded) await _restoreActive(previousActive);

    return succeeded;
  }

  /// Puts the active account back after an abandoned or failed login.
  ///
  /// A completed login is left alone: signing in as an account is a deliberate
  /// request to use it. This only undoes a switch nobody asked for.
  Future<void> _restoreActive(String? previousActive) async {
    final client = _gh;
    if (client == null || previousActive == null) return;

    final current = (await client.discover()).activeUsername;
    if (current == previousActive) return;

    await client.switchTo(previousActive);
  }

  Future<void> _closeStreams() async {
    if (!_codes.isClosed) await _codes.close();
    if (!_urls.isClosed) await _urls.close();
  }

  /// Abandons a login the user no longer wants to finish.
  void cancel() {
    _process?.kill();
    _process = null;
  }
}
