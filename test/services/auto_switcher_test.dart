import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/directory_rule.dart';
import 'package:git_switcher/src/services/auto_switcher.dart';

void main() {
  group('CwdWatcher', () {
    late Directory tempDir;
    late File stateFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gitswitcher_cwd_test');
      stateFile = File('${tempDir.path}/cwd');
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('emits a directory written by the hook', () async {
      final watcher = CwdWatcher(stateFile: stateFile);
      addTearDown(watcher.dispose);

      final seen = <String>[];
      watcher.directories.listen(seen.add);

      stateFile.writeAsStringSync('/Users/me/work\n');
      await watcher.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['/Users/me/work']);
    });

    test('does not emit the same directory twice', () async {
      final watcher = CwdWatcher(stateFile: stateFile);
      addTearDown(watcher.dispose);

      final seen = <String>[];
      watcher.directories.listen(seen.add);

      stateFile.writeAsStringSync('/Users/me/work\n');
      await watcher.poll();
      await watcher.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
    });

    test('emits again when the directory really changes', () async {
      final watcher = CwdWatcher(stateFile: stateFile);
      addTearDown(watcher.dispose);

      final seen = <String>[];
      watcher.directories.listen(seen.add);

      stateFile.writeAsStringSync('/a\n');
      await watcher.poll();
      stateFile.writeAsStringSync('/b\n');
      await watcher.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['/a', '/b']);
    });

    test('a missing state file is not an error', () async {
      final watcher = CwdWatcher(stateFile: stateFile);
      addTearDown(watcher.dispose);

      await expectLater(watcher.poll(), completes);
    });

    test('an empty state file emits nothing', () async {
      final watcher = CwdWatcher(stateFile: stateFile);
      addTearDown(watcher.dispose);

      final seen = <String>[];
      watcher.directories.listen(seen.add);

      stateFile.writeAsStringSync('\n');
      await watcher.poll();
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
    });
  });

  group('AutoSwitchPolicy', () {
    const policy = AutoSwitchPolicy(matcher: RuleMatcher(home: '/Users/me'));

    const work = Account(ghUsername: 'work-user', gitEmail: 'w@x.com');
    const personal = Account(ghUsername: 'personal-user', gitEmail: 'p@x.com');
    const accounts = [work, personal];
    const rules = [
      DirectoryRule(pathPrefix: '~/work', ghUsername: 'work-user'),
      DirectoryRule(pathPrefix: '~/code', ghUsername: 'personal-user'),
    ];

    Account? decide({
      String directory = '/Users/me/work/api',
      bool enabled = true,
      List<DirectoryRule> withRules = rules,
      List<Account> withAccounts = accounts,
      String? active = 'personal-user',
    }) {
      return policy.accountFor(
        directory: directory,
        enabled: enabled,
        rules: withRules,
        accounts: withAccounts,
        activeUsername: active,
      );
    }

    test('picks the account for a matching directory', () {
      expect(decide(), work);
    });

    test('does nothing when auto-switching is disabled', () {
      expect(decide(enabled: false), isNull);
    });

    test('does nothing when no rule matches', () {
      expect(decide(directory: '/tmp/elsewhere'), isNull);
    });

    test('does nothing when the account is already active', () {
      expect(decide(active: 'work-user'), isNull);
    });

    test('does nothing when the rule names an unknown account', () {
      expect(decide(withAccounts: const [personal]), isNull);
    });

    test('honours the most specific rule', () {
      const client =
          DirectoryRule(pathPrefix: '~/work/client', ghUsername: 'personal-user');

      expect(
        decide(
          directory: '/Users/me/work/client/api',
          withRules: const [...rules, client],
          active: 'work-user',
        ),
        personal,
      );
    });
  });
}
