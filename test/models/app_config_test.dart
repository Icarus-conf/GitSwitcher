import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/models/app_config.dart';
import 'package:git_switcher/src/models/directory_rule.dart';

void main() {
  test('portable writes home-relative paths with ~, Mac or Windows', () {
    const mac = AppConfig(
      accounts: [Account(ghUsername: 'a', sshKeyPath: '/Users/me/.ssh/k')],
      rules: [DirectoryRule(pathPrefix: '/Users/me/work', ghUsername: 'a')],
    );
    final out = mac.portable('/Users/me');
    expect(out.accounts.single.sshKeyPath, '~/.ssh/k');
    expect(out.rules.single.pathPrefix, '~/work');

    const win = AppConfig(
      rules: [DirectoryRule(pathPrefix: r'C:\Users\me\work', ghUsername: 'a')],
    );
    expect(win.portable(r'C:\Users\me').rules.single.pathPrefix, '~/work');
  });

  test('portable leaves paths outside home alone', () {
    const config = AppConfig(
      rules: [DirectoryRule(pathPrefix: '/Volumes/code', ghUsername: 'a')],
    );
    expect(config.portable('/Users/me').rules.single.pathPrefix, '/Volumes/code');
  });

  test('an import adds and updates, and never deletes', () {
    const mine = AppConfig(
      accounts: [
        Account(ghUsername: 'a', label: 'old'),
        Account(ghUsername: 'keep'),
      ],
      orgRules: [OrgRule(org: 'acme', ghUsername: 'a')],
    );
    const theirs = AppConfig(
      accounts: [Account(ghUsername: 'a', label: 'new'), Account(ghUsername: 'b')],
      orgRules: [OrgRule(org: 'ACME', ghUsername: 'b')],
      autoSwitchEnabled: true,
    );

    final merged = mine.mergedWith(theirs);

    expect({for (final a in merged.accounts) a.ghUsername: a.label},
        {'a': 'new', 'keep': '', 'b': ''});
    expect(merged.orgRules.single.ghUsername, 'b');
    expect(merged.autoSwitchEnabled, isTrue);
  });

  test('round-trips through JSON with org rules', () {
    const config = AppConfig(
      orgRules: [OrgRule(org: 'acme', ghUsername: 'a')],
      autoSwitchEnabled: true,
    );
    final back = AppConfig.fromJson(config.toJson());
    expect(back.orgRules, config.orgRules);
  });
}
