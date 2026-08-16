/// Maps a directory to the account that should be active inside it.
class DirectoryRule {
  const DirectoryRule({required this.pathPrefix, required this.ghUsername});

  /// A directory path. Everything at or below it matches. May start with `~`.
  final String pathPrefix;

  final String ghUsername;

  factory DirectoryRule.fromJson(Map<String, dynamic> json) => DirectoryRule(
        pathPrefix: json['pathPrefix'] as String,
        ghUsername: json['ghUsername'] as String,
      );

  Map<String, dynamic> toJson() => {
        'pathPrefix': pathPrefix,
        'ghUsername': ghUsername,
      };

  @override
  bool operator ==(Object other) =>
      other is DirectoryRule &&
      other.pathPrefix == pathPrefix &&
      other.ghUsername == ghUsername;

  @override
  int get hashCode => Object.hash(pathPrefix, ghUsername);

  @override
  String toString() => 'DirectoryRule($pathPrefix -> $ghUsername)';
}

/// Chooses which rule applies to a directory.
class RuleMatcher {
  const RuleMatcher({required this.home});

  final String home;

  String expand(String path) {
    if (path == '~') return home;
    if (path.startsWith('~/')) return '$home${path.substring(1)}';
    return path;
  }

  /// The most specific matching rule, or null when none apply.
  ///
  /// Longest prefix wins, so a rule for `~/work/client` beats one for `~/work`
  /// and the more specific intent is the one that takes effect.
  DirectoryRule? match(String directory, List<DirectoryRule> rules) {
    final target = _normalise(directory);

    DirectoryRule? best;
    var bestLength = -1;

    for (final rule in rules) {
      final prefix = _normalise(expand(rule.pathPrefix));
      if (!_isAtOrUnder(target, prefix)) continue;
      if (prefix.length > bestLength) {
        best = rule;
        bestLength = prefix.length;
      }
    }

    return best;
  }

  /// Strips trailing slashes so `/a/b/` and `/a/b` behave identically.
  static String _normalise(String path) {
    var result = path;
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// True when [target] is [prefix] or lives inside it.
  ///
  /// The trailing-separator check stops `/a/bcd` from matching a `/a/b` rule.
  static bool _isAtOrUnder(String target, String prefix) =>
      target == prefix || target.startsWith(prefix.endsWith('/') ? prefix : '$prefix/');
}
