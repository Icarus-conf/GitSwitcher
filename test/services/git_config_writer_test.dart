import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/app_config.dart';
import 'package:git_switcher/src/models/directory_rule.dart';
import 'package:git_switcher/src/models/switch_result.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/services/git_config_writer.dart';

/// These tests run the real git binary against a throwaway HOME, so they prove
/// git actually honours what we write — not just that we wrote it.
void main() {
  // Real git on whichever system runs the suite, so Windows CI checks the
  // gitdir/i and forward-slash handling for real.
  Host.current = Platform.isWindows ? Host.windows : Host.macos;
  String cfg(String path) => Host.current.configPath(path);
  late Directory home;
  late File gitconfig;
  late GitConfigWriter writer;

  setUp(() {
    home = Directory.systemTemp.createTempSync('gitswitcher_gitconfig');
    gitconfig = File('${home.path}/.gitconfig');
    writer = GitConfigWriter(
      gitconfig: gitconfig,
      // A space in the path, like Application Support, must survive quoting.
      directory: Directory('${home.path}/Support Dir/git'),
      home: home.path,
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  const work = Account(
    ghUsername: 'work-octo',
    gitName: 'Work Octo',
    gitEmail: 'octo@work.example',
    sshKeyPath: '~/.ssh/id_work',
  );
  const client = Account(
    ghUsername: 'client-octo',
    gitName: 'Client Octo',
    gitEmail: 'octo@client.example',
  );

  String repo(String relative) {
    final dir = Directory('${home.path}/$relative')..createSync(recursive: true);
    final init = Process.runSync('git', ['init', '-q', dir.path],
        environment: {'HOME': home.path});
    expect(init.exitCode, 0, reason: '${init.stderr}');
    return dir.path;
  }

  String? gitGet(String dir, String key) {
    final result = Process.runSync(
      'git',
      ['-C', dir, 'config', '--get', key],
      environment: {'HOME': home.path, 'GIT_CONFIG_NOSYSTEM': '1'},
    );
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  }

  AppConfig config({
    List<Account> accounts = const [work, client],
    List<DirectoryRule> rules = const [],
    bool enabled = true,
  }) =>
      AppConfig(accounts: accounts, rules: rules, autoSwitchEnabled: enabled);

  test('writes nothing when there is nothing to include', () async {
    gitconfig.writeAsStringSync('[user]\n\tname = Me\n');

    final step = await writer.sync(config(), 'work-octo');

    expect(step.status, StepStatus.ok);
    expect(gitconfig.readAsStringSync(), '[user]\n\tname = Me\n');
  });

  test('a folder rule sets identity and key for repos under it only',
      () async {
    gitconfig.writeAsStringSync('[user]\n\temail = me@home.example\n');
    final inside = repo('code/work/api');
    final outside = repo('code/personal');

    await writer.sync(
      config(rules: [
        const DirectoryRule(pathPrefix: '~/code/work', ghUsername: 'work-octo'),
      ]),
      null,
    );

    expect(gitGet(inside, 'user.email'), 'octo@work.example');
    expect(gitGet(inside, 'core.sshCommand'),
        "ssh -i '${cfg(home.path)}/.ssh/id_work' -o IdentitiesOnly=yes");
    expect(gitGet(outside, 'user.email'), 'me@home.example');
    expect(gitGet(outside, 'core.sshCommand'), isNull);
  });

  test('the most specific folder wins whatever the rule order', () async {
    final nested = repo('code/work/client/app');

    await writer.sync(
      config(rules: [
        const DirectoryRule(
            pathPrefix: '~/code/work/client', ghUsername: 'client-octo'),
        const DirectoryRule(pathPrefix: '~/code/work', ghUsername: 'work-octo'),
      ]),
      null,
    );

    expect(gitGet(nested, 'user.email'), 'octo@client.example');
  });

  test('turning folder rules off removes the block and restores the file',
      () async {
    const original = '[core]\n\teditor = vim\n';
    gitconfig.writeAsStringSync(original);
    final rules = [
      const DirectoryRule(pathPrefix: '~/code/work', ghUsername: 'work-octo'),
    ];

    await writer.sync(config(rules: rules), null);
    expect(gitconfig.readAsStringSync(), contains('includeIf'));

    await writer.sync(config(rules: rules, enabled: false), null);
    expect(gitconfig.readAsStringSync(), original);
  });

  test('moves the block back after a [user] section appended below it',
      () async {
    final inside = repo('code/work/api');
    final rules = [
      const DirectoryRule(pathPrefix: '~/code/work', ghUsername: 'work-octo'),
    ];
    await writer.sync(config(rules: rules), null);
    // What `git config --global user.email` does when no [user] exists yet.
    gitconfig.writeAsStringSync('[user]\n\temail = late@x.example\n',
        mode: FileMode.append);

    await writer.sync(config(rules: rules), null);

    expect(gitGet(inside, 'user.email'), 'octo@work.example');
  });

  test('signs with the active account key, and nowhere else', () async {
    const signer = Account(
      ghUsername: 'work-octo',
      sshKeyPath: '~/.ssh/id_work',
      signCommits: true,
    );
    final elsewhere = repo('code/personal');
    final clientRepo = repo('code/client');

    await writer.sync(
      config(accounts: const [signer, client], rules: [
        const DirectoryRule(pathPrefix: '~/code/client', ghUsername: 'client-octo'),
      ]),
      'work-octo',
    );

    expect(gitGet(elsewhere, 'commit.gpgsign'), 'true');
    expect(gitGet(elsewhere, 'gpg.format'), 'ssh');
    expect(gitGet(elsewhere, 'user.signingkey'), '${cfg(home.path)}/.ssh/id_work');
    // A folder for a non-signing account must not sign with someone else's key.
    expect(gitGet(clientRepo, 'commit.gpgsign'), 'false');
  });

  test('HTTPS in a folder gets that account\'s token from gh, not the menu\'s',
      () async {
    // A stand-in gh that answers `auth token --user X` with "token-for-X".
    final gh = File('${home.path}/bin dir/gh')..createSync(recursive: true);
    gh.writeAsStringSync('#!/bin/sh\n'
        'while [ "\$1" != --user ]; do shift; done; echo "token-for-\$2"\n');
    // Git for Windows runs helpers through its own sh, which honours the
    // shebang without an execute bit; only macOS needs one.
    if (!Platform.isWindows) Process.runSync('/bin/chmod', ['755', gh.path]);
    // gh's own helper, as `gh auth setup-git` leaves it: always the menu account.
    gitconfig.writeAsStringSync('[credential "https://github.com"]\n'
        '\thelper = !echo username=menu-account; echo password=wrong #\n');
    final inside = repo('code/work/api');

    await GitConfigWriter(
      gitconfig: gitconfig,
      directory: Directory('${home.path}/Support Dir/git'),
      home: home.path,
      ghPath: () async => gh.path,
    ).sync(
      config(rules: [
        const DirectoryRule(pathPrefix: '~/code/work', ghUsername: 'work-octo'),
      ]),
      null,
    );

    final fill = await Process.start(
      'git',
      ['-C', inside, 'credential', 'fill'],
      environment: {
        'HOME': home.path,
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_TERMINAL_PROMPT': '0',
      },
    );
    fill.stdin.write('protocol=https\nhost=github.com\n\n');
    await fill.stdin.close();
    final out = await fill.stdout.transform(const SystemEncoding().decoder).join();

    expect(out, contains('username=work-octo'));
    expect(out, contains('password=token-for-work-octo'));
  });

  test('removes include files for accounts no longer mapped', () async {
    final rules = [
      const DirectoryRule(pathPrefix: '~/a', ghUsername: 'work-octo'),
      const DirectoryRule(pathPrefix: '~/b', ghUsername: 'client-octo'),
    ];
    await writer.sync(config(rules: rules), null);
    await writer.sync(config(rules: rules.take(1).toList()), null);

    final names = Directory('${home.path}/Support Dir/git/accounts')
        .listSync()
        .map((e) => e.uri.pathSegments.last);
    expect(names, ['work-octo.gitconfig']);
  });

  test('fails without writing when the markers are malformed', () async {
    const damaged = '${'# >>> GitSwitcher (managed — do not edit)'}\n[x]\n';
    gitconfig.writeAsStringSync(damaged);

    final step = await writer.sync(
      config(rules: [
        const DirectoryRule(pathPrefix: '~/a', ghUsername: 'work-octo'),
      ]),
      null,
    );

    expect(step.status, StepStatus.failed);
    expect(gitconfig.readAsStringSync(), damaged);
  });
}
