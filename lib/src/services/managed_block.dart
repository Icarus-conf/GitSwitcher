import 'dart:io';

/// Edits a marked region inside a file the user owns.
///
/// Both `~/.ssh/config` and `~/.zshrc` are files the user wrote and we are only
/// a guest in. The contract is the same for each: only bytes between the two
/// markers are ever touched, a backup precedes any modification, and damaged
/// markers abort the write instead of guessing.
class ManagedBlock {
  const ManagedBlock({
    required this.beginMarker,
    required this.endMarker,
    this.atStart = false,
  });

  final String beginMarker;
  final String endMarker;

  /// Where the block lives. Position matters in both files we manage: ssh uses
  /// the first value it reads (and tries IdentityFiles in order), while git
  /// lets the last value win. So the block is moved to its end of the file on
  /// every write, not just placed there once.
  final bool atStart;

  /// Wraps [body] in this block's markers.
  String render(List<String> body) =>
      [beginMarker, ...body, endMarker].join('\n');

  /// Returns [existing] with the managed region replaced by [block], placed at
  /// the start or end of the file according to [atStart].
  ///
  /// Throws [FormatException] if the markers are present but unusable.
  String replaceIn(String existing, String block) {
    final beginIndex = existing.indexOf(beginMarker);
    final endIndex = existing.indexOf(endMarker);

    if ((beginIndex == -1) != (endIndex == -1) || endIndex < beginIndex) {
      throw const FormatException(
        'The GitSwitcher markers in this file are malformed. '
        'Nothing was written — please repair the file by hand.',
      );
    }

    final rest = removeFrom(existing);
    if (rest.isEmpty) return '$block\n';
    if (atStart) return '$block\n\n$rest';
    final separator = rest.endsWith('\n') ? '\n' : '\n\n';
    return '$rest$separator$block\n';
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

/// Writes a timestamped copy of a file before it is modified, keeping only
/// the newest [keep] copies so backups do not pile up forever.
class BackupWriter {
  const BackupWriter({this.now = DateTime.now, this.keep = 5});

  final DateTime Function() now;
  final int keep;

  Future<File> write(File file, String contents) async {
    final stamp = now().millisecondsSinceEpoch;
    final backup = File('${file.path}.gitswitcher-backup-$stamp');
    await backup.writeAsString(contents);
    await _prune(file);
    return backup;
  }

  Future<void> _prune(File file) async {
    // Compared by file name, not full path: on Windows a listing spells the
    // folder with `\` even when [file] was built with `/`, so a full-path
    // prefix would never match and nothing would ever be pruned.
    final prefix = '${file.uri.pathSegments.last}.gitswitcher-backup-';
    String nameOf(String path) => File(path).uri.pathSegments.last;
    final backups = await file.parent
        .list()
        .where((e) => e is File && nameOf(e.path).startsWith(prefix))
        .map((e) => e.path)
        .toList();
    int stampOf(String path) =>
        int.tryParse(nameOf(path).substring(prefix.length)) ?? 0;
    backups.sort((a, b) => stampOf(b).compareTo(stampOf(a)));
    for (final old in backups.skip(keep)) {
      try {
        await File(old).delete();
      } on FileSystemException {
        // A backup we cannot delete is harmless; try again next time.
      }
    }
  }
}
