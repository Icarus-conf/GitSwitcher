/// A GitHub user's public profile, as returned by `gh api users/<login>`.
class GitHubProfile {
  const GitHubProfile({
    required this.login,
    required this.name,
    required this.avatarUrl,
  });

  final String login;

  /// GitHub allows an empty display name, so this is nullable.
  final String? name;

  final String avatarUrl;

  String get displayName => (name == null || name!.isEmpty) ? login : name!;

  /// GitHub serves avatars at any size via `s`; asking for the size we render
  /// avoids downloading a 460px image to draw it at 16px.
  String sizedAvatarUrl(int size) =>
      avatarUrl.contains('?') ? '$avatarUrl&s=$size' : '$avatarUrl?s=$size';

  factory GitHubProfile.fromJson(Map<String, dynamic> json) => GitHubProfile(
        login: json['login'] as String,
        name: json['name'] as String?,
        avatarUrl: json['avatar_url'] as String,
      );

  Map<String, dynamic> toJson() => {
        'login': login,
        'name': name,
        'avatar_url': avatarUrl,
      };

  @override
  bool operator ==(Object other) =>
      other is GitHubProfile &&
      other.login == login &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(login, name, avatarUrl);
}
