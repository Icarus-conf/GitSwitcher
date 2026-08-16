import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_starter.dart';
import 'package:git_switcher/src/services/gh_login_session.dart';
import 'package:git_switcher/src/ui/add_account_dialog.dart';

import '../support/fake_process_runner.dart';

/// A process that keeps running until it is killed, like a real login waiting
/// for the user to finish in the browser.
class HangingProcessStarter implements ProcessStarter {
  final _exit = Completer<int>();
  final _lines = StreamController<String>();

  @override
  Future<StartedProcess> start(String executable, List<String> arguments) async {
    return StartedProcess(
      lines: _lines.stream,
      exitCode: _exit.future,
      kill: () {
        if (!_lines.isClosed) _lines.close();
        // A real process does not die instantly. Completing after a short
        // delay lands run() inside the dialog's dismiss animation, which is
        // when the dialog is still mounted and a second pop is possible.
        Future<void>.delayed(const Duration(milliseconds: 50), () {
          if (!_exit.isCompleted) _exit.complete(1);
        });
      },
    );
  }

  void emit(String line) => _lines.add(line);
}

void main() {
  testWidgets('cancelling closes only the dialog, not the screen under it',
      (tester) async {
    final starter = HangingProcessStarter();
    final runner = FakeProcessRunner();
    final session = GhLoginSession(
      starter: starter,
      locator: BinaryLocator(
        runner: runner,
        searchDirs: const ['/opt/homebrew/bin'],
        exists: (p) => p == '/opt/homebrew/bin/gh',
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const Text('SETTINGS BEHIND'),
              ElevatedButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      AddAccountDialog(createSession: () => session),
                ),
                child: const Text('open'),
              ),
            ],
          ),
        ),
      ),
    ));

    // pumpAndSettle is unusable here: the dialog shows a progress indicator,
    // which never stops animating.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    starter.emit('! First copy your one-time code: C613-16DB');
    await tester.pump();
    await tester.pump();
    expect(find.text('C613-16DB'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    // Advance in small steps so run() completes mid-dismissal, reproducing the
    // window in which a second pop would remove the screen underneath.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('C613-16DB'), findsNothing, reason: 'dialog should close');
    expect(
      find.text('SETTINGS BEHIND'),
      findsOneWidget,
      reason: 'the screen underneath must survive the cancel',
    );
  });
}
