import 'dart:io';

import '../models/account.dart';
import '../models/app_config.dart';
import '../models/switch_result.dart';
import 'managed_block.dart';

/// Expands a leading `~`, which neither git nor a process argument does.
String expandTilde(String path, String home) {
  if (path == '~') return home;
  if (path.startsWith('~/')) return '$home${path.substring(1)}';
  return path;
}

/// Keeps a managed block at the end of `~/.gitconfig` that includes files this
/// app writes into its own folder:
///
/// - `active.gitconfig`: commit signing for the account picked in the menu.
/// - `accounts/<login>.gitconfig`: identity, SSH key and signing for each
///   account a folder rule points at, pulled in with git's own
///   `includeIf "gitdir:…"`.
///
/// Folder rules therefore work in every shell, editor and GUI client at once,
/// and two terminals in different folders never fight over a global setting.
/// The block sits at the end because git lets the last value win, and it is
/// moved back there on every sync in case `git config --global` appended a
/// `[user]` section after it.
class GitConfigWriter {
  GitConfigWriter({
    required File gitconfig,
    required Directory directory,
    required String home,
    BackupWriter backups = const BackupWriter(),
  })  : _gitconfig = gitconfig,
        _directory = directory,
        _home = home,
        _backups = backups;

  final File _gitconfig;
  final Directory _directory;
  final String _home;
  final BackupWriter _backups;

  static const String stepName = 'git config';

  static const ManagedBlock block = ManagedBlock(
    beginMarker: '# >>> GitSwitcher (managed — do not edit)',
    endMarker: '# <<< GitSwitcher',
  );

  File get _activeFile => File('${_directory.path}/active.gitconfig');
  Directory get _accountsDir => Directory('${_directory.path}/accounts');
  File _accountFile(String login) =>
      File('${_accountsDir.path}/$login.gitconfig');

  /// Brings the block and the included files in line with [config], with
  /// [activeUsername] as the account picked in the menu.
  ///
  /// When nothing needs including the block is removed, so a user who never
  /// signs commits or adds a folder never finds GitSwitcher in `.gitconfig`.
  Future<StepResult> sync(AppConfig config, String? activeUsername) async {
    try {
      final byLogin = {for (final a in config.accounts) a.ghUsername: a};
      final anySigns = config.accounts.any(_signs);

      final rules = config.autoSwitchEnabled
          ? ([...config.rules]
            // Most specific last, because git lets the last match win.
            ..sort((a, b) => expandHome(a.pathPrefix)
                .length
                .compareTo(expandHome(b.pathPrefix).length)))
          : const [];

      final active = byLogin[activeUsername];
      final activeLines = active != null && _signs(active)
          ? _signingLines(active)
          : const <String>[];

      final lines = <String>[];
      if (activeLines.isNotEmpty) {
        await _writeIfChanged(_activeFile, activeLines);
        lines.addAll(['[include]', '\tpath = ${_quote(_activeFile.path)}']);
      }

      final used = <String>{};
      for (final rule in rules) {
        final login = rule.ghUsername;
        final account = byLogin[login] ?? Account(ghUsername: login);
        if (used.add(login)) {
          await _writeIfChanged(
            _accountFile(login),
            folderLines(account, anySigns: anySigns),
          );
        }
        final dir = await _realPath(_trimSlash(expandHome(rule.pathPrefix)));
        lines.addAll([
          '[includeIf ${_quote('gitdir:$dir/')}]',
          '\tpath = ${_quote(_accountFile(login).path)}',
        ]);
      }
      await _removeStaleAccountFiles(used);

      final existed = await _gitconfig.exists();
      final existing = existed ? await _gitconfig.readAsString() : '';
      final updated = lines.isEmpty
          ? block.removeFrom(existing)
          : block.replaceIn(existing, block.render(lines));
      if (updated == existing) return const StepResult.ok(stepName);

      if (existed) await _backups.write(_gitconfig, existing);
      await _gitconfig.writeAsString(updated);
      return const StepResult.ok(stepName);
    } on FormatException catch (error) {
      return StepResult.failed(stepName, error.message);
    } on FileSystemException catch (error) {
      return StepResult.failed(stepName, error.message);
    }
  }

  /// The config applied inside a folder that belongs to [account].
  ///
  /// When any account signs, a non-signing one turns signing off, so its
  /// folders never sign with another account's key.
  List<String> folderLines(Account account, {required bool anySigns}) {
    final key = expandHome(account.sshKeyPath);
    return [
      if (account.gitName.isNotEmpty && account.gitEmail.isNotEmpty) ...[
        '[user]',
        '\tname = ${_quote(account.gitName)}',
        '\temail = ${_quote(account.gitEmail)}',
      ],
      // ponytail: applies to every remote in the folder, not only github.com,
      // so a GitLab repo under a mapped folder is offered this key alone. Add a
      // per-remote url.insteadOf host alias if that ever bites.
      if (key.isNotEmpty) ...[
        '[core]',
        '\tsshCommand = ${_quote('ssh -i ${_shellQuote(key)} -o IdentitiesOnly=yes')}',
      ],
      if (_signs(account))
        ..._signingLines(account)
      else if (anySigns) ...['[commit]', '\tgpgsign = false'],
    ];
  }

  List<String> _signingLines(Account account) => [
        '[user]',
        '\tsigningkey = ${_quote(expandHome(account.sshKeyPath))}',
        '[gpg]',
        '\tformat = ssh',
        '[commit]',
        '\tgpgsign = true',
      ];

  static bool _signs(Account a) => a.signCommits && a.sshKeyPath.isNotEmpty;

  String expandHome(String path) => expandTilde(path, _home);

  /// git matches `gitdir:` against the repo's resolved path, so a folder
  /// reached through a symlink would never match as written.
  static Future<String> _realPath(String path) async {
    try {
      return await Directory(path).resolveSymbolicLinks();
    } on FileSystemException {
      return path; // Not created yet; nothing to resolve.
    }
  }

  static String _trimSlash(String path) {
    var result = path;
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// A git config string: only backslash and double quote need escaping.
  static String _quote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  Future<void> _writeIfChanged(File file, List<String> lines) async {
    final contents = '# Written by GitSwitcher — changes are overwritten.\n'
        '${lines.join('\n')}\n';
    if (await file.exists() && await file.readAsString() == contents) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> _removeStaleAccountFiles(Set<String> keep) async {
    if (!await _accountsDir.exists()) return;
    await for (final entry in _accountsDir.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File &&
          name.endsWith('.gitconfig') &&
          !keep.contains(name.substring(0, name.length - '.gitconfig'.length))) {
        await entry.delete();
      }
    }
  }
}
