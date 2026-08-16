import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/gh_client.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File hostsFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_gh_test');
    hostsFile = File('${tempDir.path}/hosts.yml');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  GhClient buildClient(FakeProcessRunner runner) => GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const ['/opt/homebrew/bin'],
          exists: (path) => path == '/opt/homebrew/bin/gh',
        ),
        hostsFile: hostsFile,
      );

  group('discover from hosts.yml', () {
    test('reads every user and the active one', () async {
      hostsFile.writeAsStringSync('''
github.com:
    git_protocol: https
    users:
        octocat:
        hubot:
    user: octocat
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(accounts.activeUsername, 'octocat');
    });

    test('handles a single user', () async {
      hostsFile.writeAsStringSync('''
github.com:
    users:
        solo:
    user: solo
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['solo']);
      expect(accounts.activeUsername, 'solo');
    });

    test('tolerates a missing active user key', () async {
      hostsFile.writeAsStringSync('''
github.com:
    users:
        solo:
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['solo']);
      expect(accounts.activeUsername, isNull);
    });

    test('ignores hosts other than github.com', () async {
      hostsFile.writeAsStringSync('''
ghe.example.com:
    users:
        enterprise-user:
    user: enterprise-user
github.com:
    users:
        octocat:
    user: octocat
''');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, ['octocat']);
    });

    test('returns nothing when github.com is absent', () async {
      hostsFile.writeAsStringSync('ghe.example.com:\n    users:\n        x:\n');

      final accounts = await buildClient(FakeProcessRunner()).discover();

      expect(accounts.usernames, isEmpty);
      expect(accounts.activeUsername, isNull);
    });
  });

  group('discover falls back to gh auth status', () {
    const statusOutput = '''
github.com
  ✓ Logged in to github.com account octocat (keyring)
  - Active account: true
  - Git operations protocol: https

  ✓ Logged in to github.com account hubot (keyring)
  - Active account: false
  - Git operations protocol: https
''';

    test('parses usernames and the active account from status text', () {
      final accounts = GhClient.parseAuthStatus(statusOutput);

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(accounts.activeUsername, 'octocat');
    });

    test('is used when hosts.yml is missing', () async {
      final runner = FakeProcessRunner(
        responses: {
          '/opt/homebrew/bin/gh auth status':
              const CommandResult(0, statusOutput, ''),
        },
      );

      final accounts = await buildClient(runner).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
      expect(runner.calls, contains('/opt/homebrew/bin/gh auth status'));
    });

    test('is used when hosts.yml is malformed', () async {
      hostsFile.writeAsStringSync('\t: not: valid: yaml: [');
      final runner = FakeProcessRunner(
        responses: {
          '/opt/homebrew/bin/gh auth status':
              const CommandResult(0, statusOutput, ''),
        },
      );

      final accounts = await buildClient(runner).discover();

      expect(accounts.usernames, ['octocat', 'hubot']);
    });

    test('returns nothing when gh itself is missing', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      final accounts = await client.discover();

      expect(accounts.usernames, isEmpty);
    });
  });

  group('isInstalled', () {
    test('is true when gh resolves', () async {
      expect(await buildClient(FakeProcessRunner()).isInstalled(), isTrue);
    });

    test('is false when gh cannot be found anywhere', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      expect(await client.isInstalled(), isFalse);
    });
  });

  group('switchTo', () {
    test('runs gh auth switch with the host and user', () async {
      final runner = FakeProcessRunner();

      final step = await buildClient(runner).switchTo('octocat');

      expect(step.status, StepStatus.ok);
      expect(
        runner.calls,
        contains(
          '/opt/homebrew/bin/gh auth switch --hostname github.com --user octocat',
        ),
      );
    });

    test('fails with the stderr text when gh exits non-zero', () async {
      final runner = FakeProcessRunner(
        fallback: const CommandResult(1, '', 'no such account octocat'),
      );

      final step = await buildClient(runner).switchTo('octocat');

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('no such account'));
    });

    test('fails with a clear message when gh is not installed', () async {
      final runner = FakeProcessRunner(fallback: const CommandResult(1, '', ''));
      final client = GhClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const [],
          exists: (_) => false,
        ),
        hostsFile: hostsFile,
      );

      final step = await client.switchTo('octocat');

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('gh'));
    });
  });
}
