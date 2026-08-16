import 'dart:io';

/// Edits a marked region inside a file the user owns.
///
/// Both `~/.ssh/config` and `~/.zshrc` are files the user wrote and we are only
/// a guest in. The contract is the same for each: only bytes between the two
/// markers are ever touched, a backup precedes any modification, and damaged
/// markers abort the write instead of guessing.
class ManagedBlock {
  const ManagedBlock({required this.beginMarker, required this.endMarker});

  final String beginMarker;
  final String endMarker;

  /// Wraps [body] in this block's markers.
  String render(List<String> body) =>
      [beginMarker, ...body, endMarker].join('\n');

  /// Returns [existing] with the managed region replaced by [block].
  ///
  /// Throws [FormatException] if the markers are present but unusable.
  String replaceIn(String existing, String block) {
    final beginIndex = existing.indexOf(beginMarker);
    final endIndex = existing.indexOf(endMarker);

    if (beginIndex == -1 && endIndex == -1) {
      if (existing.isEmpty) return '$block\n';
      final separator = existing.endsWith('\n') ? '\n' : '\n\n';
      return '$existing$separator$block\n';
    }

    if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
      throw const FormatException(
        'The GitSwitcher markers in this file are malformed. '
        'Nothing was written — please repair the file by hand.',
      );
    }

    return existing.substring(0, beginIndex) +
        block +
        existing.substring(endIndex + endMarker.length);
  }

  /// Returns [existing] with the managed region and its markers removed.
  ///
  /// Content outside the markers is preserved. Returns [existing] unchanged
  /// when no block is present.
  String removeFrom(String existing) {
    final beginIndex = existing.indexOf(beginMarker);
    final endIndex = existing.indexOf(endMarker);
    if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
      return existing;
    }

    // Undo exactly what replaceIn added: the blank-line separator before the
    // block and the newline after it. Without this, install/uninstall cycles
    // slowly accumulate blank lines in the user's file.
    var before = existing.substring(0, beginIndex);
    if (before.endsWith('\n\n')) before = before.substring(0, before.length - 1);

    var after = existing.substring(endIndex + endMarker.length);
    if (after.startsWith('\n')) after = after.substring(1);
    return before.trimRight().isEmpty ? after.trimLeft() : '$before$after';
  }

  bool isPresentIn(String existing) => existing.contains(beginMarker);
}

/// Writes a timestamped copy of a file before it is modified.
class BackupWriter {
  const BackupWriter({this.now = DateTime.now});

  final DateTime Function() now;

  Future<File> write(File file, String contents) async {
    final stamp = now().millisecondsSinceEpoch;
    final backup = File('${file.path}.gitswitcher-backup-$stamp');
    await backup.writeAsString(contents);
    return backup;
  }
}
