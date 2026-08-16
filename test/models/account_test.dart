import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';

void main() {
  group('Account.displayName', () {
    test('uses the label when it is set', () {
      const account = Account(ghUsername: 'octocat', label: 'Work');
      expect(account.displayName, 'Work');
    });

    test('falls back to the gh username when the label is empty', () {
      const account = Account(ghUsername: 'octocat');
      expect(account.displayName, 'octocat');
    });
  });

  group('Account.isComplete', () {
    test('is false when both git email and ssh key are empty', () {
      const account = Account(ghUsername: 'octocat');
      expect(account.isComplete, isFalse);
    });

    test('is true when only the git email is set', () {
      const account = Account(ghUsername: 'octocat', gitEmail: 'a@b.com');
      expect(account.isComplete, isTrue);
    });

    test('is true when only the ssh key is set', () {
      const account = Account(ghUsername: 'octocat', sshKeyPath: '/k');
      expect(account.isComplete, isTrue);
    });
  });

  group('Account JSON', () {
    test('round-trips every field', () {
      const account = Account(
        ghUsername: 'octocat',
        label: 'Work',
        gitName: 'Octo Cat',
        gitEmail: 'octo@example.com',
        sshKeyPath: '/Users/me/.ssh/id_work',
      );
      expect(Account.fromJson(account.toJson()), account);
    });

    test('defaults missing optional fields to empty strings', () {
      final account = Account.fromJson({'ghUsername': 'octocat'});
      expect(account.ghUsername, 'octocat');
      expect(account.label, '');
      expect(account.gitName, '');
      expect(account.gitEmail, '');
      expect(account.sshKeyPath, '');
    });
  });

  test('copyWith replaces only the named fields', () {
    const account = Account(ghUsername: 'octocat', label: 'Work');
    final updated = account.copyWith(gitEmail: 'octo@example.com');
    expect(updated.ghUsername, 'octocat');
    expect(updated.label, 'Work');
    expect(updated.gitEmail, 'octo@example.com');
  });
}
