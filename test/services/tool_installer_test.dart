import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/tool_installer.dart';

import '../support/fake_process_runner.dart';

/// The gh tests use the real shasum and ditto, so the checksum and unzip
/// paths are exercised exactly as they run in the app.
void main() {
  late Directory temp;
  late List<int> zipBytes;
  late String digest;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('gitswitcher_installer');
    final staged = Directory('${temp.path}/stage/gh_9.9.9_macOS_arm64/bin')
      ..createSync(recursive: true);
    File('${staged.path}/gh').writeAsStringSync('#!/bin/sh\necho gh 9.9.9\n');
    final zip = '${temp.path}/gh.zip';
    Process.runSync('/usr/bin/ditto',
        ['-c', '-k', '${temp.path}/stage', zip]);
    zipBytes = File(zip).readAsBytesSync();
    digest = 'sha256:${(Process.runSync('/usr/bin/shasum', ['-a', '256', zip])
            .stdout as String).split(' ').first}';
  });

  tearDown(() => temp.deleteSync(recursive: true));

  ToolInstaller installer({String? publishedDigest, List<int>? served}) {
    final release = jsonEncode({
      'tag_name': 'v9.9.9',
      'assets': [
        {
          'name': 'gh_9.9.9_macOS_amd64.zip',
          'browser_download_url': 'https://x/amd64.zip',
          'digest': 'sha256:00',
        },
        {
          'name': 'gh_9.9.9_macOS_arm64.zip',
          'browser_download_url': 'https://x/arm64.zip',
          'digest': publishedDigest ?? digest,
        },
      ],
    });
    return ToolInstaller(
      runner: const RealProcessRunner(),
      binDir: Directory('${temp.path}/bin'),
      abi: Abi.macosArm64,
      fetch: (url) async {
        if (url == ToolInstaller.latestRelease) return utf8.encode(release);
        expect(url.toString(), 'https://x/arm64.zip');
        return served ?? zipBytes;
      },
    );
  }

  test('installs the verified gh binary for this architecture', () async {
    final tag = await installer().installGh();

    final gh = File('${temp.path}/bin/gh');
    expect(tag, 'v9.9.9');
    expect(gh.readAsStringSync(), contains('gh 9.9.9'));
    expect(Process.runSync(gh.path, const []).stdout, contains('gh 9.9.9'));
  });

  test('refuses a download that does not match its checksum', () async {
    await expectLater(
      installer(served: [...zipBytes, 0]).installGh(),
      throwsA(isA<ToolInstallException>()
          .having((e) => e.message, 'message', contains('checksum'))),
    );
    expect(File('${temp.path}/bin/gh').existsSync(), isFalse);
  });

  test('refuses an asset with no published checksum', () async {
    await expectLater(
      installer(publishedDigest: '').installGh(),
      throwsA(isA<ToolInstallException>()),
    );
  });

  test('updates an outdated gh it installed, and leaves a current one', () async {
    await installer().installGh(); // installs a gh reporting 9.9.9...
    File('${temp.path}/bin/gh')
        .writeAsStringSync('#!/bin/sh\necho gh version 1.0.0 \\(x\\)\n');

    expect(await installer().updateGh(), 'v9.9.9');

    File('${temp.path}/bin/gh')
        .writeAsStringSync('#!/bin/sh\necho gh version 9.9.9 \\(x\\)\n');
    expect(await installer().updateGh(), isNull);
  });

  test('never touches a gh it did not install', () async {
    expect(await installer().updateGh(), isNull);
    expect(File('${temp.path}/bin/gh').existsSync(), isFalse);
  });

  group('gitInstalled', () {
    test('the /usr/bin stub alone does not count', () async {
      final tools = ToolInstaller(
        runner: FakeProcessRunner(
            fallback: const CommandResult(2, '', 'no developer tools')),
        binDir: temp,
        exists: (path) => path == '/usr/bin/git',
      );
      expect(await tools.gitInstalled(), isFalse);
    });

    test('Command Line Tools count', () async {
      final tools = ToolInstaller(
        runner: FakeProcessRunner(),
        binDir: temp,
        exists: (_) => false,
      );
      expect(await tools.gitInstalled(), isTrue);
    });

    test('a Homebrew git counts without asking xcode-select', () async {
      final runner = FakeProcessRunner(
          fallback: const CommandResult(2, '', 'no developer tools'));
      final tools = ToolInstaller(
        runner: runner,
        binDir: temp,
        exists: (path) => path == '/opt/homebrew/bin/git',
      );
      expect(await tools.gitInstalled(), isTrue);
      expect(runner.calls, isEmpty);
    });
  });
}
