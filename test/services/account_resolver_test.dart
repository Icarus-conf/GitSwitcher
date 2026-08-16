import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/services/account_resolver.dart';
import 'package:git_switcher/src/services/gh_client.dart';

void main() {
  const work = Account(
    ghUsername: 'octocat',
    label: 'Work',
    gitName: 'Muhammad',
    gitEmail: 'work@example.com',
  );

  test('marks the gh active account as active', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat'], 'octocat'),
    );

    expect(resolved.single.isActive, isTrue);
    expect(resolved.single.isSelectable, isTrue);
    expect(resolved.single.disabledReason, isNull);
  });

  test('adds discovered accounts that have no stored entry', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered:
          const GhAccounts(['octocat', 'hubot'], 'octocat'),
    );

    expect(resolved.map((r) => r.account.ghUsername),
        ['octocat', 'hubot']);
  });

  test('an unconfigured account is still selectable — gh can switch it', () {
    final resolved = AccountResolver.merge(
      stored: const [],
      discovered: const GhAccounts(['hubot'], null),
    );

    expect(resolved.single.isLoggedIn, isTrue);
    expect(resolved.single.isSelectable, isTrue);
    expect(resolved.single.disabledReason, isNull);
  });

  test('an unconfigured account hints at what it will not do', () {
    final resolved = AccountResolver.merge(
      stored: const [],
      discovered: const GhAccounts(['hubot'], null),
    );

    expect(resolved.single.setupHint, contains('gh only'));
  });

  test('a configured account needs no hint', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat'], 'octocat'),
    );

    expect(resolved.single.setupHint, isNull);
  });

  test('keeps a stored account that gh no longer knows about', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['hubot'], 'hubot'),
    );

    final stale = resolved.firstWhere(
      (r) => r.account.ghUsername == 'octocat',
    );
    expect(stale.isLoggedIn, isFalse);
    expect(stale.isSelectable, isFalse);
    expect(stale.disabledReason, contains('not logged in'));
  });

  test('being logged out is the only thing that disables an account', () {
    final resolved = AccountResolver.merge(
      stored: const [Account(ghUsername: 'gone')],
      discovered: const GhAccounts([], null),
    );

    expect(resolved.single.isSelectable, isFalse);
  });

  test('never lists the same username twice', () {
    final resolved = AccountResolver.merge(
      stored: const [work],
      discovered: const GhAccounts(['octocat'], 'octocat'),
    );

    expect(resolved, hasLength(1));
  });

  test('stored accounts keep their order and come before new discoveries', () {
    final resolved = AccountResolver.merge(
      stored: const [
        Account(ghUsername: 'b', gitEmail: 'b@x.com'),
        Account(ghUsername: 'a', gitEmail: 'a@x.com'),
      ],
      discovered: const GhAccounts(['a', 'b', 'c'], 'a'),
    );

    expect(resolved.map((r) => r.account.ghUsername), ['b', 'a', 'c']);
  });

  test('reports no accounts when gh knows none and nothing is stored', () {
    final resolved = AccountResolver.merge(
      stored: const [],
      discovered: const GhAccounts.empty(),
    );

    expect(resolved, isEmpty);
  });
}
