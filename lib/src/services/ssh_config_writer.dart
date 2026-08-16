import 'dart:io';

import '../models/account.dart';
import '../models/switch_result.dart';
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
    DateTime Function() now = DateTime.now,
  })  : _file = file,
        _runner = runner,
        _now = now;

  final File _file;
  final ProcessRunner _runner;
  final DateTime Function() _now;

  static const String stepName = 'ssh';
  static const String beginMarker = '# >>> GitSwitcher (managed — do not edit)';
  static const String endMarker = '# <<< GitSwitcher';

  static const ManagedBlock block = ManagedBlock(
    beginMarker: beginMarker,
    endMarker: endMarker,
  );

  static String renderBlock(String keyPath) => block.render([
        'Host github.com',
        '    HostName github.com',
        '    User git',
        '    IdentityFile $keyPath',
        '    IdentitiesOnly yes',
      ]);

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
      if (fileExisted) {
        final stamp = _now().millisecondsSinceEpoch;
        await File('${_file.path}.gitswitcher-backup-$stamp')
            .writeAsString(existing);
      }

      await _file.parent.create(recursive: true);
      await _file.writeAsString(updated);

      if (!fileExisted) {
        // Dart cannot set file modes directly, and ssh refuses to read a
        // world-readable config.
        await _runner.run('/bin/chmod', ['600', _file.path]);
      }
    } on FileSystemException catch (error) {
      return StepResult.failed(stepName, error.message);
    }

    return const StepResult.ok(stepName);
  }
}
