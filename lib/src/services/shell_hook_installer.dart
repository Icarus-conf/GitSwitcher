import 'dart:io';

import 'managed_block.dart';

/// Installs and removes the zsh hook that reports directory changes.
///
/// The hook is deliberately tiny and side-effect free: it writes `$PWD` to a
/// state file and nothing else. It runs on every `cd` the user makes, so it
/// must never be slow, never print, and never fail in a way that disturbs the
/// shell. A subshell redirect satisfies all three.
class ShellHookInstaller {
  ShellHookInstaller({
    required File zshrc,
    required File stateFile,
    BackupWriter backups = const BackupWriter(),
  })  : _zshrc = zshrc,
        _stateFile = stateFile,
        _backups = backups;

  final File _zshrc;
  final File _stateFile;
  final BackupWriter _backups;

  static const ManagedBlock block = ManagedBlock(
    beginMarker: '# >>> GitSwitcher (managed — do not edit)',
    endMarker: '# <<< GitSwitcher',
  );

  String get hookBody => '''
# Reports the current directory to GitSwitcher so it can switch accounts.
gitswitcher_report_cwd() {
  print -r -- "\$PWD" > '${_stateFile.path}' 2>/dev/null
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd gitswitcher_report_cwd
gitswitcher_report_cwd''';

  Future<bool> isInstalled() async {
    if (!await _zshrc.exists()) return false;
    return block.isPresentIn(await _zshrc.readAsString());
  }

  /// Adds the hook, replacing any previous version of it.
  ///
  /// Throws [FormatException] if the existing markers are damaged.
  Future<void> install() async {
    final existed = await _zshrc.exists();
    final existing = existed ? await _zshrc.readAsString() : '';

    final updated = block.replaceIn(existing, block.render(hookBody.split('\n')));
    if (updated == existing) return;

    if (existed) await _backups.write(_zshrc, existing);
    await _stateFile.parent.create(recursive: true);
    await _zshrc.writeAsString(updated);
  }

  /// Removes the hook, leaving everything else in the file untouched.
  Future<void> uninstall() async {
    if (!await _zshrc.exists()) return;

    final existing = await _zshrc.readAsString();
    final updated = block.removeFrom(existing);
    if (updated == existing) return;

    await _backups.write(_zshrc, existing);
    await _zshrc.writeAsString(updated);
  }
}
