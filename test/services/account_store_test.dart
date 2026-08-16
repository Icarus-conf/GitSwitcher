import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/app_config.dart';
import 'package:git_switcher/src/models/directory_rule.dart';
import 'package:git_switcher/src/services/account_store.dart';

void main() {
  late Directory tempDir;
  late File file;
  late AccountStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_store_test');
    file = File('${tempDir.path}/config/accounts.json');
    store = AccountStore(file);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('returns an empty list when the file does not exist', () async {
    expect(await store.load(), isEmpty);
  });

  test('the empty list from a missing file can be added to', () async {
    // Callers append the account they are saving; an unmodifiable list would
    // throw on the very first save the app ever performs.
    final accounts = await store.load();

    expect(
      () => accounts.add(const Account(ghUsername: 'octocat')),
      returnsNormally,
    );
  });

  test('the empty list from a corrupt file can be added to', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('not json');

    final accounts = await store.load();

    expect(
      () => accounts.add(const Account(ghUsername: 'octocat')),
      returnsNormally,
    );
  });

  test('a saved account survives a reload through the store', () async {
    final accounts = await store.load();
    accounts.add(const Account(ghUsername: 'octocat', gitEmail: 'o@x.com'));
    await store.save(accounts);

    expect(await store.load(), hasLength(1));
  });

  test('round-trips accounts through save and load', () async {
    const accounts = [
      Account(
        ghUsername: 'octocat',
        label: 'Work',
        gitName: 'Octo Cat',
        gitEmail: 'octo@example.com',
        sshKeyPath: '/Users/me/.ssh/id_work',
      ),
      Account(ghUsername: 'hubot', label: 'Personal'),
    ];

    await store.save(accounts);

    expect(await store.load(), accounts);
  });

  test('creates parent directories on save', () async {
    await store.save(const [Account(ghUsername: 'octocat')]);
    expect(file.existsSync(), isTrue);
  });

  test('writes a versioned envelope', () async {
    await store.save(const [Account(ghUsername: 'octocat')]);

    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(data['version'], 2);
    expect(data['accounts'], hasLength(1));
  });

  group('schema migration', () {
    // Exactly the shape version 1 wrote, including a real account.
    const version1 = '''
{
  "version": 1,
  "accounts": [
    {
      "ghUsername": "octocat",
      "label": "Work",
      "gitName": "octocat",
      "gitEmail": "work@example.com",
      "sshKeyPath": "/Users/me/.ssh/id_ed25519"
    }
  ]
}
''';

    test('reads a version 1 file without losing accounts', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(version1);

      final config = await store.loadConfig();

      expect(config.accounts.single.label, 'Work');
      expect(config.accounts.single.sshKeyPath, '/Users/me/.ssh/id_ed25519');
    });

    test('defaults the fields version 1 did not have', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(version1);

      final config = await store.loadConfig();

      expect(config.rules, isEmpty);
      expect(config.autoSwitchEnabled, isFalse);
    });

    test('upgrades to version 2 on the next save, keeping the account',
        () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(version1);

      final config = await store.loadConfig();
      await store.saveConfig(config.copyWith(autoSwitchEnabled: true));

      final reloaded = await store.loadConfig();
      expect(reloaded.accounts.single.gitEmail, 'work@example.com');
      expect(reloaded.autoSwitchEnabled, isTrue);
      expect(
        (jsonDecode(file.readAsStringSync()) as Map)['version'],
        2,
      );
    });

    test('saving accounts alone preserves rules and settings', () async {
      await store.saveConfig(const AppConfig(
        accounts: [Account(ghUsername: 'a')],
        rules: [DirectoryRule(pathPrefix: '~/work', ghUsername: 'a')],
        autoSwitchEnabled: true,
      ));

      await store.save([const Account(ghUsername: 'a', label: 'Renamed')]);

      final config = await store.loadConfig();
      expect(config.accounts.single.label, 'Renamed');
      expect(config.rules, hasLength(1));
      expect(config.autoSwitchEnabled, isTrue);
    });

    test('round-trips rules and the auto-switch flag', () async {
      await store.saveConfig(const AppConfig(
        accounts: [Account(ghUsername: 'a')],
        rules: [
          DirectoryRule(pathPrefix: '~/work', ghUsername: 'a'),
          DirectoryRule(pathPrefix: '~/code', ghUsername: 'b'),
        ],
        autoSwitchEnabled: true,
      ));

      final config = await store.loadConfig();

      expect(config.rules, hasLength(2));
      expect(config.rules.first.pathPrefix, '~/work');
      expect(config.autoSwitchEnabled, isTrue);
    });
  });

  test('quarantines a corrupt file and starts fresh', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('this is not json {{{');

    expect(await store.load(), isEmpty);
    expect(file.existsSync(), isFalse);

    final quarantined = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('accounts.json.corrupt-'));
    expect(quarantined, hasLength(1));
  });

  test('quarantines valid JSON with the wrong shape', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"version": 1, "accounts": "not a list"}');

    expect(await store.load(), isEmpty);
    expect(file.existsSync(), isFalse);
  });
}
