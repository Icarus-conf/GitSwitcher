import 'dart:io';

import '../models/account.dart';
import '../platform/binary_locator.dart';
import '../platform/host.dart';
import '../platform/process_runner.dart';

/// Clones a repository as a chosen account, right from the first fetch.
///
/// The clone gets `include.path` pointing at the account's include file (the
/// same one folder and organization rules use), so its name, email, SSH key,
/// HTTPS token and signing are that account's wherever the repo lives, and
/// they follow later edits to the account.
class RepoCloner {
  RepoCloner({
    required ProcessRunner runner,
    required BinaryLocator locator,
    required File Function(String login) accountFile,
  })  : _runner = runner,
        _locator = locator,
        _accountFile = accountFile;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
  final File Function(String login) _accountFile;

  static final RegExp _shorthand =
      RegExp(r'^([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(\.git)?$');

  /// What to clone for [input]: `owner/repo` becomes an SSH URL when the
  /// account has a key and HTTPS otherwise; anything else is used as given.
  static String urlFor(String input, Account account) {
    final text = input.trim();
    final match = _shorthand.firstMatch(text);
    if (match == null) return text;
    final path = '${match.group(1)}/${match.group(2)}';
    return account.sshKeyPath.isNotEmpty
        ? 'git@github.com:$path.git'
        : 'https://github.com/$path.git';
  }

  /// The folder name git would pick: the last path segment without `.git`.
  static String nameFor(String url) {
    var name = url.trim().split(RegExp(r'[/:\\]')).where((s) => s.isNotEmpty).last;
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    return name;
  }

  /// Clones [input] into [parentDir] as [account] and returns the new
  /// repository's path. Throws [CloneException] with git's own message.
  Future<String> clone({
    required String input,
    required Account account,
    required String parentDir,
  }) async {
    final url = urlFor(input, account);
    final target = Host.current.join(parentDir, nameFor(url));
    if (await Directory(target).exists()) {
      throw CloneException('$target already exists');
    }

    final String git;
    try {
      git = await _locator.locate('git');
    } on BinaryNotFoundException catch (error) {
      throw CloneException(error.toString());
    }

    final include =
        Host.current.configPath(_accountFile(account.ghUsername).path);
    final result = await _runner.run(git, [
      'clone',
      // Written into the new repo before the first fetch, so even the clone
      // itself authenticates as this account.
      '-c', 'include.path=$include',
      url,
      target,
    ], environment: const {'GIT_TERMINAL_PROMPT': '0'});
    if (!result.ok) throw CloneException(result.errorText);
    return target;
  }
}

class CloneException implements Exception {
  CloneException(this.message);

  final String message;

  @override
  String toString() => message;
}
