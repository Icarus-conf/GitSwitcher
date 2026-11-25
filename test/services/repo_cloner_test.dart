import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/repo_cloner.dart';

void main() {
  const withKey = Account(ghUsername: 'octo', sshKeyPath: '~/.ssh/k');
  const noKey = Account(ghUsername: 'octo');

  group('urlFor', () {
    test('owner/repo uses SSH when the account has a key', () {
      expect(RepoCloner.urlFor('acme/api', withKey), 'git@github.com:acme/api.git');
    });

    test('owner/repo uses HTTPS without a key', () {
      expect(RepoCloner.urlFor(' acme/api.git ', noKey),
          'https://github.com/acme/api.git');
    });

    test('a full URL is used as given', () {
      const url = 'https://github.com/acme/api';
      expect(RepoCloner.urlFor(url, withKey), url);
    });
  });

  test('nameFor picks the folder git would', () {
    expect(RepoCloner.nameFor('git@github.com:acme/api.git'), 'api');
    expect(RepoCloner.nameFor('https://github.com/acme/web/'), 'web');
  });

  test('the clone commits as the account from the start (real git)', () async {
    Host.current = Platform.isWindows ? Host.windows : Host.macos;
    final temp = Directory.systemTemp.createTempSync('gitswitcher_clone');
    addTearDown(() => temp.deleteSync(recursive: true));
    final env = {'HOME': temp.path, 'GIT_CONFIG_NOSYSTEM': '1'};

    final origin = '${temp.path}/origin.git';
    Process.runSync('git', ['init', '-q', '--bare', origin], environment: env);
    final include = File('${temp.path}/octo.gitconfig')
      ..writeAsStringSync('[user]\n\temail = octo@example.com\n');

    final parent = Directory('${temp.path}/work')..createSync();
    const runner = RealProcessRunner();
    final path = await RepoCloner(
      runner: runner,
      locator: BinaryLocator(runner: runner),
      accountFile: (_) => include,
    ).clone(input: origin, account: noKey, parentDir: parent.path);

    final email = Process.runSync('git', ['-C', path, 'config', 'user.email'],
        environment: env);
    expect((email.stdout as String).trim(), 'octo@example.com');
  });
}
