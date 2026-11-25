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

/// Maps a GitHub organization (or user) to the account its repos should use,
/// wherever on disk they are cloned.
class OrgRule {
  const OrgRule({required this.org, required this.ghUsername});

  /// Accepts `acme`, `github.com/acme` or a pasted URL, and keeps `acme`.
  factory OrgRule.parse(String input, String ghUsername) {
    var org = input.trim();
    org = org.replaceFirst(
        RegExp(r'^((https?|ssh)://)?(git@)?(www\.)?github\.com[/:]'), '');
    org = org.split('/').first.trim();
    return OrgRule(org: org, ghUsername: ghUsername);
  }

  final String org;
  final String ghUsername;

  bool get isValid => RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$').hasMatch(org);

  factory OrgRule.fromJson(Map<String, dynamic> json) => OrgRule(
        org: json['org'] as String,
        ghUsername: json['ghUsername'] as String,
      );

  Map<String, dynamic> toJson() => {'org': org, 'ghUsername': ghUsername};

  @override
  bool operator ==(Object other) =>
      other is OrgRule && other.org == org && other.ghUsername == ghUsername;

  @override
  int get hashCode => Object.hash(org, ghUsername);
}
