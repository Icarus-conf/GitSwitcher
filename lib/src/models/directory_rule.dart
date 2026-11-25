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
