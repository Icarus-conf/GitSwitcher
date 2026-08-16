import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/profile_client.dart';
import 'package:git_switcher/src/services/profile_store.dart';

import '../support/fake_process_runner.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_pstore_test');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  String apiFor(String login) =>
      '{"login":"$login","name":"Name Of $login","avatar_url":"https://x/$login.png"}';

  ProfileStore buildStore(FakeProcessRunner runner) {
    return ProfileStore(
      client: ProfileClient(
        runner: runner,
        locator: BinaryLocator(
          runner: runner,
          searchDirs: const ['/opt/homebrew/bin'],
          exists: (p) => p == '/opt/homebrew/bin/gh',
        ),
      ),
      avatars: AvatarCache(
        directory: tempDir,
        download: (url) async => [1, 2, 3],
      ),
    );
  }

  test('loads profiles and avatar paths', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/opt/homebrew/bin/gh api users/octocat':
            CommandResult(0, apiFor('octocat'), ''),
      },
    );
    final store = buildStore(runner);
    addTearDown(store.dispose);

    await store.refresh(['octocat']);

    expect(store['octocat']!.profile.displayName, 'Name Of octocat');
    expect(store['octocat']!.avatarPath, isNotNull);
  });

  test('does not refetch a profile it already has', () async {
    final runner = FakeProcessRunner(
      fallback: CommandResult(0, apiFor('octocat'), ''),
    );
    final store = buildStore(runner);
    addTearDown(store.dispose);

    await store.refresh(['octocat']);
    final callsAfterFirst = runner.calls.length;
    await store.refresh(['octocat']);

    expect(runner.calls.length, callsAfterFirst);
  });

  test('a failed profile leaves the account absent rather than throwing',
      () async {
    final runner = FakeProcessRunner(fallback: const CommandResult(1, '', 'no'));
    final store = buildStore(runner);
    addTearDown(store.dispose);

    await store.refresh(['ghost']);

    expect(store['ghost'], isNull);
  });

  test('notifies listeners when something new loads', () async {
    final runner = FakeProcessRunner(
      fallback: CommandResult(0, apiFor('octocat'), ''),
    );
    final store = buildStore(runner);
    addTearDown(store.dispose);

    final notified = expectLater(store.changes, emits(anything));
    await store.refresh(['octocat']);
    await notified;
  });

  test('stays quiet when nothing new loaded', () async {
    final runner = FakeProcessRunner(fallback: const CommandResult(1, '', 'no'));
    final store = buildStore(runner);

    var events = 0;
    final sub = store.changes.listen((_) => events++);
    await store.refresh(['ghost']);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    store.dispose();

    expect(events, 0);
  });
}
