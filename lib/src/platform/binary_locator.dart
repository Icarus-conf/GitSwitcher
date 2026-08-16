import 'dart:io';

import 'process_runner.dart';

typedef PathExists = bool Function(String path);

/// Where CLI tools normally live on macOS, in probe order.
const List<String> kBinarySearchDirs = [
  '/opt/homebrew/bin',
  '/usr/local/bin',
  '/usr/bin',
];

class BinaryNotFoundException implements Exception {
  BinaryNotFoundException(this.name);

  final String name;

  @override
  String toString() =>
      '$name was not found. Install it, or make sure it is on your PATH.';
}

/// Resolves absolute paths to CLI tools.
///
/// A GUI app launched from Finder does not inherit the login shell's PATH, so
/// `Process.run('gh', ...)` fails inside a bundled `.app` even when `gh` works
/// perfectly in a terminal. Probing known directories first — and only then
/// paying for a login shell — keeps the common case fast.
class BinaryLocator {
  BinaryLocator({
    required ProcessRunner runner,
    List<String> searchDirs = kBinarySearchDirs,
    PathExists exists = _defaultExists,
  })  : _runner = runner,
        _searchDirs = searchDirs,
        _exists = exists;

  final ProcessRunner _runner;
  final List<String> _searchDirs;
  final PathExists _exists;
  final Map<String, String> _cache = {};

  static bool _defaultExists(String path) => File(path).existsSync();

  /// Throws [BinaryNotFoundException] if [name] cannot be resolved.
  Future<String> locate(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;

    for (final dir in _searchDirs) {
      final candidate = '$dir/$name';
      if (_exists(candidate)) {
        _cache[name] = candidate;
        return candidate;
      }
    }

    final result = await _runner.run('/bin/zsh', ['-lc', 'which $name']);
    final resolved = result.stdout.trim();
    if (result.ok && resolved.isNotEmpty && _exists(resolved)) {
      _cache[name] = resolved;
      return resolved;
    }

    throw BinaryNotFoundException(name);
  }
}
