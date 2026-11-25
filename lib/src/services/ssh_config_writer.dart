import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
import '../platform/host.dart';
import '../platform/process_runner.dart';
import 'managed_block.dart';

/// Rewrites the github.com SSH identity inside a marked region of the user's
/// `~/.ssh/config`.
///
/// The user owns this file and did not create it for us, so the contract is
/// strict: only bytes between the two markers are ever touched, a backup is
/// written before any modification, and anything unexpected between the
/// markers aborts the write rather than guessing.
class SshConfigWriter {
  SshConfigWriter({
    required File file,
    required ProcessRunner runner,
    BackupWriter backups = const BackupWriter(),
  })  : _file = file,
        _runner = runner,
        _backups = backups;

  final File _file;
  final ProcessRunner _runner;
  final BackupWriter _backups;

  static const String stepName = 'ssh';
  static const String beginMarker = '# >>> GitSwitcher (managed — do not edit)';
  static const String endMarker = '# <<< GitSwitcher';

  /// Kept at the top of the file. ssh tries every matching IdentityFile in
  /// the order it reads them, so a block at the bottom would lose to any
  /// earlier `Host *` or `Host github.com` key — and GitHub would happily
  /// accept that key as a different account.
  static const ManagedBlock block = ManagedBlock(
    beginMarker: beginMarker,
    endMarker: endMarker,
    atStart: true,
  );

  /// Only the key is set, so the user's own HostName, Port or proxy settings
  /// for github.com still apply. The trailing `Host *` closes our block:
  /// without it, the user's next top-level line (an `Include`, say) would
  /// silently become part of the github.com block.
  static String renderBlock(String keyPath) => block.render([
        'Host github.com',
        '    IdentityFile ${_sshValue(Host.current.configPath(keyPath))}',
        '    IdentitiesOnly yes',
        'Host *',
      ]);

  /// ssh config splits on spaces unless the value is quoted — a real concern
  /// on Windows, where home folders are often `C:/Users/First Last`.
  static String _sshValue(String value) =>
      value.contains(' ') ? '"$value"' : value;

  /// Returns [existing] with the managed block set to [newBlock].
  ///
  /// Throws [FormatException] if the markers are present but unusable.
  static String replaceBlock(String existing, String newBlock) =>
      block.replaceIn(existing, newBlock);

  Future<StepResult> apply(Account account) async {
    if (account.sshKeyPath.isEmpty) {
      return const StepResult.skipped(stepName, 'no SSH key configured');
    }

    final fileExisted = await _file.exists();
    final existing = fileExisted ? await _file.readAsString() : '';

    final String updated;
    try {
      updated = replaceBlock(existing, renderBlock(account.sshKeyPath));
    } on FormatException catch (error) {
      return StepResult.failed(stepName, error.message);
    }

    // Already correct — do not churn the file or pile up backups.
    if (updated == existing) return const StepResult.ok(stepName);

    try {
      if (fileExisted) await _backups.write(_file, existing);

      await _file.parent.create(recursive: true);
      await _file.writeAsString(updated);

      if (!fileExisted) {
        // Dart cannot set file modes directly, and ssh refuses to read a
        // world-readable config.
        await Host.current.chmod(_runner, '600', _file.path);
      }
    } on FileSystemException catch (error) {
      return StepResult.failed(stepName, error.message);
    }

    return const StepResult.ok(stepName);
  }
}
