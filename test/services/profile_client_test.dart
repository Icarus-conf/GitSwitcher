import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/github_profile.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/profile_client.dart';

import '../support/fake_process_runner.dart';

void main() {
  const apiResponse =
      '{"login":"hubot","name":"Muhammad Fathy",'
      '"avatar_url":"https://avatars.githubusercontent.com/u/583231?v=4"}';

  ProfileClient buildClient(FakeProcessRunner runner, {bool ghExists = true}) {
    return ProfileClient(
      runner: runner,
      locator: BinaryLocator(
        runner: runner,
        searchDirs: const ['/opt/homebrew/bin'],
        exists: (path) => ghExists && path == '/opt/homebrew/bin/gh',
      ),
    );
  }

  test('fetches a profile for any account, not just the active one', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/opt/homebrew/bin/gh api users/hubot':
            const CommandResult(0, apiResponse, ''),
      },
    );

    final profile = await buildClient(runner).fetch('hubot');

    expect(profile, isNotNull);
    expect(profile!.login, 'hubot');
    expect(profile.name, 'Muhammad Fathy');
    expect(profile.avatarUrl, contains('avatars.githubusercontent.com'));
  });

  test('returns null when gh fails rather than throwing', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(1, '', 'not found'),
    );

    expect(await buildClient(runner).fetch('nobody'), isNull);
  });

  test('returns null when gh is not installed', () async {
    final client = buildClient(FakeProcessRunner(), ghExists: false);

    expect(await client.fetch('octocat'), isNull);
  });

  test('returns null on unparseable output', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(0, 'not json at all', ''),
    );

    expect(await buildClient(runner).fetch('octocat'), isNull);
  });

  test('tolerates a null name, which GitHub allows', () async {
    final runner = FakeProcessRunner(
      fallback: const CommandResult(
        0,
        '{"login":"octocat","name":null,"avatar_url":"https://x/y.png"}',
        '',
      ),
    );

    final profile = await buildClient(runner).fetch('octocat');

    expect(profile!.name, isNull);
    expect(profile.displayName, 'octocat');
  });

  group('GitHubProfile', () {
    test('round-trips through JSON for caching', () {
      const profile = GitHubProfile(
        login: 'octocat',
        name: 'Octo Cat',
        avatarUrl: 'https://x/y.png',
      );

      expect(GitHubProfile.fromJson(profile.toJson()), profile);
    });

    test('sized avatar url appends the size parameter', () {
      const profile = GitHubProfile(
        login: 'octocat',
        name: null,
        avatarUrl: 'https://avatars.githubusercontent.com/u/1?v=4',
      );

      expect(profile.sizedAvatarUrl(64), endsWith('&s=64'));
    });

    test('sized avatar url starts a query when none exists', () {
      const profile = GitHubProfile(
        login: 'octocat',
        name: null,
        avatarUrl: 'https://example.com/a.png',
      );

      expect(profile.sizedAvatarUrl(64), 'https://example.com/a.png?s=64');
    });
  });

  group('AvatarCache', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gitswitcher_avatar_test');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns an already-cached file without downloading', () async {
      final cached = File('${tempDir.path}/octocat.png');
      cached.writeAsBytesSync([1, 2, 3]);

      var downloads = 0;
      final cache = AvatarCache(
        directory: tempDir,
        download: (url) async {
          downloads++;
          return [9, 9];
        },
      );

      expect(await cache.pathFor('octocat', 'https://x/y.png'), cached.path);
      expect(downloads, 0);
    });

    test('downloads and stores an avatar that is not cached', () async {
      final cache = AvatarCache(
        directory: tempDir,
        download: (url) async => [1, 2, 3],
      );

      final path = await cache.pathFor('octocat', 'https://x/y.png');

      expect(path, isNotNull);
      expect(File(path!).readAsBytesSync(), [1, 2, 3]);
    });

    test('returns null when the download fails', () async {
      final cache = AvatarCache(
        directory: tempDir,
        download: (url) async => throw const SocketException('offline'),
      );

      expect(await cache.pathFor('octocat', 'https://x/y.png'), isNull);
    });

    test('returns null for an empty download rather than a broken file',
        () async {
      final cache = AvatarCache(
        directory: tempDir,
        download: (url) async => <int>[],
      );

      expect(await cache.pathFor('octocat', 'https://x/y.png'), isNull);
      expect(File('${tempDir.path}/octocat.png').existsSync(), isFalse);
    });
  });
}
