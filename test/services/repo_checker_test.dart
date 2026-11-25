import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/app_config.dart';
import 'package:git_switcher/src/models/directory_rule.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/repo_checker.dart';

/// Real repos, real git: the check is only as good as its reading of them.
void main() {
  late Directory home;
  late RepoChecker checker;
  final env = <String, String>{};

  const work = Account(
    ghUsername: 'work',
    label: 'Work',
    gitName: 'W',
    gitEmail: 'me@work.example',
  );
  const personal = Account(
    ghUsername: 'me',
    label: 'Personal',
    gitName: 'P',
    gitEmail: 'me@home.example',
  );

  setUp(() {
    Host.current = Platform.isWindows ? Host.windows : Host.macos;
    home = Directory.systemTemp.createTempSync('gitswitcher_repocheck');
    env
      ..clear()
      ..addAll({'HOME': home.path, 'GIT_CONFIG_NOSYSTEM': '1'});
    const runner = RealProcessRunner();
    checker = RepoChecker(
      runner: runner,
      locator: BinaryLocator(runner: runner),
      home: home.path,
    );
  });

  tearDown(() => home.deleteSync(recursive: true));

  String repo(String relative) {
    final path = '${home.path}/$relative';
    Directory(path).createSync(recursive: true);
    Process.runSync('git', ['init', '-q', path], environment: env);
    return path;
  }

  void git(String repo, List<String> args) {
    final r = Process.runSync('git', ['-C', repo, ...args], environment: env);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  }

  void commitAs(String repo, String email) => git(repo, [
        '-c', 'user.name=x', '-c', 'user.email=$email',
        'commit', '-q', '--allow-empty', '-m', 'c',
      ]);

  const config = AppConfig(
    accounts: [work, personal],
    rules: [DirectoryRule(pathPrefix: '~/work', ghUsername: 'work')],
    autoSwitchEnabled: true,
  );

  test('a clean repo has no findings', () async {
    final r = repo('work/api');
    commitAs(r, 'me@work.example');
    commitAs(r, 'teammate@work.example'); // Someone else's: fine.

    final result = await checker.check(config);

    expect(result.checked, 1);
    expect(result.findings, isEmpty);
  });

  test('flags a repo whose own settings override the rule, and fixes it',
      () async {
    final r = repo('work/nested/legacy');
    git(r, ['config', 'user.email', 'me@home.example']);

    final result = await checker.check(config);

    expect(result.findings.single.localOverride, isTrue);
    await checker.removeLocalIdentity(r);
    expect((await checker.check(config)).findings, isEmpty);
  });

  test('flags commits made with another of your own accounts', () async {
    final r = repo('work/web');
    commitAs(r, 'me@home.example');
    commitAs(r, 'me@work.example');

    final finding = (await checker.check(config)).findings.single;

    expect(finding.localOverride, isFalse);
    expect(finding.problem, contains("1 of the last 30 commits used Personal's"));
  });

  test('an organization rule decides over the folder', () async {
    final r = repo('work/fork');
    git(r, ['remote', 'add', 'origin', 'git@github.com:me-oss/fork.git']);
    commitAs(r, 'me@work.example');

    final result = await checker.check(config.copyWith(
      orgRules: [const OrgRule(org: 'me-oss', ghUsername: 'me')],
    ));

    expect(result.findings.single.expected.ghUsername, 'me');
  });
}
