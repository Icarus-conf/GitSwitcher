import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/services/ssh_config_writer.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;
  late File configFile;
  late FakeProcessRunner runner;
  late SshConfigWriter writer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_ssh_test');
    configFile = File('${tempDir.path}/config');
    runner = FakeProcessRunner();
    writer = SshConfigWriter(
      file: configFile,
      runner: runner,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const account = Account(
    ghUsername: 'octocat',
    sshKeyPath: '/Users/me/.ssh/id_work',
  );

  group('replaceBlock', () {
    const block = 'BEGIN\nbody\nEND';

    test('appends to content that has no markers', () {
      final result =
          SshConfigWriter.replaceBlock('Host *\n    TCPKeepAlive yes\n', block);

      expect(result, 'Host *\n    TCPKeepAlive yes\n\nBEGIN\nbody\nEND\n');
    });

    test('appends to empty content without leading blank lines', () {
      expect(SshConfigWriter.replaceBlock('', block), 'BEGIN\nbody\nEND\n');
    });

    test('replaces an existing block in place', () {
      const existing = 'before\n\n'
          '${SshConfigWriter.beginMarker}\nold body\n${SshConfigWriter.endMarker}'
          '\n\nafter\n';
      final newBlock =
          '${SshConfigWriter.beginMarker}\nnew body\n${SshConfigWriter.endMarker}';

      final result = SshConfigWriter.replaceBlock(existing, newBlock);

      expect(result, 'before\n\n$newBlock\n\nafter\n');
    });

    test('throws when the closing marker is missing', () {
      expect(
        () => SshConfigWriter.replaceBlock(
          '${SshConfigWriter.beginMarker}\nbody\n',
          block,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when the closing marker precedes the opening marker', () {
      expect(
        () => SshConfigWriter.replaceBlock(
          '${SshConfigWriter.endMarker}\n${SshConfigWriter.beginMarker}\n',
          block,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('apply', () {
    test('skips when no ssh key is configured', () async {
      final step = await writer.apply(const Account(ghUsername: 'octocat'));

      expect(step.status, StepStatus.skipped);
      expect(configFile.existsSync(), isFalse);
    });

    test('creates the file when it does not exist', () async {
      final step = await writer.apply(account);

      expect(step.status, StepStatus.ok);
      expect(configFile.readAsStringSync(),
          contains('IdentityFile /Users/me/.ssh/id_work'));
      expect(configFile.readAsStringSync(), contains('Host github.com'));
    });

    test('chmods a newly created file to 600', () async {
      await writer.apply(account);

      expect(runner.calls, ['/bin/chmod 600 ${configFile.path}']);
    });

    test('preserves content outside the markers byte-for-byte', () async {
      const original = 'Host *\n'
          '    ServerAliveInterval 60\n'
          '    TCPKeepAlive yes\n';
      configFile.writeAsStringSync(original);

      await writer.apply(account);

      expect(configFile.readAsStringSync(), startsWith(original));
    });

    test('replaces the key on a second switch without duplicating the block',
        () async {
      await writer.apply(account);
      await writer.apply(
        const Account(
            ghUsername: 'hubot', sshKeyPath: '/Users/me/.ssh/id_personal'),
      );

      final contents = configFile.readAsStringSync();
      expect(SshConfigWriter.beginMarker.allMatches(contents), hasLength(1));
      expect(contents, contains('/Users/me/.ssh/id_personal'));
      expect(contents, isNot(contains('/Users/me/.ssh/id_work')));
    });

    test('writes a backup before modifying an existing file', () async {
      configFile.writeAsStringSync('Host *\n    TCPKeepAlive yes\n');

      await writer.apply(account);

      final backup =
          File('${configFile.path}.gitswitcher-backup-1700000000000');
      expect(backup.existsSync(), isTrue);
      expect(backup.readAsStringSync(), 'Host *\n    TCPKeepAlive yes\n');
    });

    test('is idempotent: an unchanged rewrite makes no backup', () async {
      await writer.apply(account);
      final afterFirst = configFile.readAsStringSync();

      final step = await writer.apply(account);

      expect(step.status, StepStatus.ok);
      expect(configFile.readAsStringSync(), afterFirst);
      expect(
        File('${configFile.path}.gitswitcher-backup-1700000000000')
            .existsSync(),
        isFalse,
      );
    });

    test('fails without writing when the markers are malformed', () async {
      const damaged = '${SshConfigWriter.beginMarker}\nHost github.com\n';
      configFile.writeAsStringSync(damaged);

      final step = await writer.apply(account);

      expect(step.status, StepStatus.failed);
      expect(step.message, contains('malformed'));
      expect(configFile.readAsStringSync(), damaged);
    });
  });
}
