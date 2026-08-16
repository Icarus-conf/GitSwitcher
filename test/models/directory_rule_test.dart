import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/directory_rule.dart';

void main() {
  const matcher = RuleMatcher(home: '/Users/me');

  const work = DirectoryRule(pathPrefix: '~/work', ghUsername: 'work-user');
  const personal =
      DirectoryRule(pathPrefix: '~/code', ghUsername: 'personal-user');

  test('matches a directory inside a rule', () {
    expect(
      matcher.match('/Users/me/work/api', const [work, personal]),
      work,
    );
  });

  test('matches the rule directory itself', () {
    expect(matcher.match('/Users/me/work', const [work]), work);
  });

  test('returns null when nothing matches', () {
    expect(matcher.match('/tmp/elsewhere', const [work, personal]), isNull);
  });

  test('the most specific rule wins', () {
    const client =
        DirectoryRule(pathPrefix: '~/work/client', ghUsername: 'client-user');

    expect(
      matcher.match('/Users/me/work/client/api', const [work, client]),
      client,
    );
  });

  test('rule order does not decide the winner', () {
    const client =
        DirectoryRule(pathPrefix: '~/work/client', ghUsername: 'client-user');

    expect(
      matcher.match('/Users/me/work/client/api', const [client, work]),
      client,
    );
  });

  test('a sibling with a shared name prefix does not match', () {
    // ~/work must not capture ~/workshop.
    expect(matcher.match('/Users/me/workshop/thing', const [work]), isNull);
  });

  test('trailing slashes are irrelevant', () {
    const trailing =
        DirectoryRule(pathPrefix: '~/work/', ghUsername: 'work-user');

    expect(matcher.match('/Users/me/work/api/', const [trailing]), trailing);
  });

  test('absolute prefixes work without a tilde', () {
    const absolute =
        DirectoryRule(pathPrefix: '/opt/src', ghUsername: 'work-user');

    expect(matcher.match('/opt/src/thing', const [absolute]), absolute);
  });

  test('expands a bare tilde to home', () {
    expect(matcher.expand('~'), '/Users/me');
    expect(matcher.expand('~/work'), '/Users/me/work');
    expect(matcher.expand('/absolute'), '/absolute');
  });

  test('round-trips through JSON', () {
    expect(DirectoryRule.fromJson(work.toJson()), work);
  });
}
