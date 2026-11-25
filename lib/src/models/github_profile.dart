/// A GitHub user's public profile, as returned by `gh api users/<login>`.
class GitHubProfile {
  const GitHubProfile({
    required this.login,
    required this.name,
    required this.avatarUrl,
    this.id,
  });

  final String login;

  /// GitHub's numeric account id; never changes, even when the login does.
  final int? id;

  /// The address GitHub gives every account for commits: it always links the
  /// commit to this account and keeps the real email private.
  String? get noreplyEmail =>
      id == null ? null : '$id+$login@users.noreply.github.com';

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
        id: json['id'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'login': login,
        'name': name,
        'avatar_url': avatarUrl,
        'id': id,
      };

  @override
  bool operator ==(Object other) =>
      other is GitHubProfile &&
      other.login == login &&
      other.name == name &&
      other.avatarUrl == avatarUrl &&
      other.id == id;

  @override
  int get hashCode => Object.hash(login, name, avatarUrl, id);
}
