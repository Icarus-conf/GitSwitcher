import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_starter.dart';
import 'package:git_switcher/src/services/gh_client.dart';
import 'package:git_switcher/src/services/gh_login_session.dart';

import '../support/fake_process_runner.dart';

/// Replays scripted output lines, then exits with a chosen code.
class FakeProcessStarter implements ProcessStarter {
  FakeProcessStarter({this.output = const [], this.exitCode = 0, this.onStart});

  final List<String> output;
  final int exitCode;

  /// Lets a test reproduce gh's side effect of changing the active account
  /// the moment the login begins.
  final void Function()? onStart;

  List<String>? startedWith;
  var killed = false;

  @override
  Future<StartedProcess> start(String executable, List<String> arguments) async {
    startedWith = [executable, ...arguments];
    onStart?.call();
    return StartedProcess(
      lines: Stream.fromIterable(output),
      exitCode: Future.value(exitCode),
      kill: () => killed = true,
    );
  }
}

void main() {
  BinaryLocator locatorFor({bool ghExists = true}) {
    final runner = FakeProcessRunner();
    return BinaryLocator(
      runner: runner,
      searchDirs: const ['/opt/homebrew/bin'],
      exists: (p) => ghExists && p == '/opt/homebrew/bin/gh',
    );
  }

  test('parses gh 2.x real output, captured from the installed binary',
      () async {
    // Copied verbatim from `gh auth login --web` run without a terminal.
    final starter = FakeProcessStarter(output: [
      '',
      '! First copy your one-time code: C613-16DB',
      'Open this URL to continue in your web browser: '
          'https://github.com/login/device',
    ]);
    final session = GhLoginSession(starter: starter, locator: locatorFor());

    final codes = <String>[];
    final urls = <String>[];
    session.codes.listen(codes.add);
    session.urls.listen(urls.add);
    await session.run();

    expect(codes, ['C613-16DB']);
    expect(urls, ['https://github.com/login/device']);
  });

  test('surfaces the one-time code gh prints', () async {
    final starter = FakeProcessStarter(output: [
      '! First copy your one-time code: 8D5F-2A1C',
      'Press Enter to open github.com in your browser...',
    ]);
    final session =
        GhLoginSession(starter: starter, locator: locatorFor());

    final codes = <String>[];
    session.codes.listen(codes.add);
    await session.run();

    expect(codes, ['8D5F-2A1C']);
  });

  test('passes the flags that avoid blocking prompts', () async {
    final starter = FakeProcessStarter();
    await GhLoginSession(starter: starter, locator: locatorFor()).run();

    expect(starter.startedWith, [
      '/opt/homebrew/bin/gh',
      'auth',
      'login',
      '--hostname',
      'github.com',
      '--git-protocol',
      'https',
      '--scopes',
      'workflow',
      '--skip-ssh-key',
      '--web',
    ]);
  });

  test('requests the workflow scope, which gh does not grant by default',
      () async {
    // Re-authenticating replaces an account's token rather than extending it,
    // so a login that forgets this silently removes the ability to push
    // changes under .github/workflows/.
    final starter = FakeProcessStarter();
    await GhLoginSession(starter: starter, locator: locatorFor()).run();

    final args = starter.startedWith!;
    expect(args, contains('--scopes'));
    expect(args[args.indexOf('--scopes') + 1], contains('workflow'));
  });

  test('reports success on a zero exit code', () async {
    final session = GhLoginSession(
      starter: FakeProcessStarter(exitCode: 0),
      locator: locatorFor(),
    );

    expect(await session.run(), isTrue);
  });

  test('reports failure on a non-zero exit code', () async {
    final session = GhLoginSession(
      starter: FakeProcessStarter(exitCode: 1),
      locator: locatorFor(),
    );

    expect(await session.run(), isFalse);
  });

  test('fails without starting anything when gh is missing', () async {
    final starter = FakeProcessStarter();
    final session = GhLoginSession(
      starter: starter,
      locator: locatorFor(ghExists: false),
    );

    expect(await session.run(), isFalse);
    expect(starter.startedWith, isNull);
  });

  test('ignores lines that carry no code', () async {
    final starter = FakeProcessStarter(output: [
      'Logging into github.com',
      'no code on this line',
    ]);
    final session = GhLoginSession(starter: starter, locator: locatorFor());

    final codes = <String>[];
    session.codes.listen(codes.add);
    await session.run();

    expect(codes, isEmpty);
  });

  test('the code pattern matches gh formatting but not ordinary words', () {
    expect(GhLoginSession.codePattern.hasMatch('code: ABCD-1234'), isTrue);
    expect(GhLoginSession.codePattern.hasMatch('some-words'), isFalse);
    expect(GhLoginSession.codePattern.hasMatch('lower-case'), isFalse);
  });

  group('active account is protected from an abandoned login', () {
    late Directory tempDir;
    late File hostsFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gitswitcher_login_active');
      hostsFile = File('${tempDir.path}/hosts.yml');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    void writeActive(String user) {
      hostsFile.writeAsStringSync('''
github.com:
    users:
        octocat:
        hubot:
    user: $user
''');
    }

    ({GhLoginSession session, FakeProcessRunner runner}) build({
      required int exitCode,
      required String switchesTo,
    }) {
      final runner = FakeProcessRunner();
      final locator = BinaryLocator(
        runner: runner,
        searchDirs: const ['/opt/homebrew/bin'],
        exists: (p) => p == '/opt/homebrew/bin/gh',
      );
      return (
        runner: runner,
        session: GhLoginSession(
          // gh flips the active account as soon as the login starts, whether
          // or not the user ever finishes it.
          starter: FakeProcessStarter(
            exitCode: exitCode,
            onStart: () => writeActive(switchesTo),
          ),
          locator: locator,
          gh: GhClient(
            runner: runner,
            locator: locator,
            hostsFile: hostsFile,
          ),
        ),
      );
    }

    test('restores the previous account when the login fails', () async {
      writeActive('hubot');
      final t = build(exitCode: 1, switchesTo: 'octocat');

      expect(await t.session.run(), isFalse);

      expect(
        t.runner.calls,
        contains(
          '/opt/homebrew/bin/gh auth switch --hostname github.com '
          '--user hubot',
        ),
      );
    });

    test('leaves the new account active when the login succeeds', () async {
      writeActive('hubot');
      final t = build(exitCode: 0, switchesTo: 'someone-new');

      expect(await t.session.run(), isTrue);

      expect(
        t.runner.calls.where((c) => c.contains('auth switch')),
        isEmpty,
        reason: 'a completed login should keep the account it signed in as',
      );
    });

    test('does nothing when the account never changed', () async {
      writeActive('hubot');
      final t = build(exitCode: 1, switchesTo: 'hubot');

      await t.session.run();

      expect(
        t.runner.calls.where((c) => c.contains('auth switch')),
        isEmpty,
      );
    });
  });
}
