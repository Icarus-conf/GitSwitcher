/// A GitHub account the user can switch to.
///
/// [ghUsername] is the primary key and comes from the gh CLI. Every other
/// field is supplied by the user through Settings.
class Account {
  const Account({
    required this.ghUsername,
    this.label = '',
    this.gitName = '',
    this.gitEmail = '',
    this.sshKeyPath = '',
  });

  final String ghUsername;
  final String label;
  final String gitName;
  final String gitEmail;
  final String sshKeyPath;

  /// What the menu shows for this account.
  String get displayName => label.isEmpty ? ghUsername : label;

  /// An account is incomplete until it can change at least one thing beyond
  /// the gh CLI's own active account.
  bool get isComplete => gitEmail.isNotEmpty || sshKeyPath.isNotEmpty;

  Account copyWith({
    String? label,
    String? gitName,
    String? gitEmail,
    String? sshKeyPath,
  }) {
    return Account(
      ghUsername: ghUsername,
      label: label ?? this.label,
      gitName: gitName ?? this.gitName,
      gitEmail: gitEmail ?? this.gitEmail,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
    );
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      ghUsername: json['ghUsername'] as String,
      label: json['label'] as String? ?? '',
      gitName: json['gitName'] as String? ?? '',
      gitEmail: json['gitEmail'] as String? ?? '',
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'ghUsername': ghUsername,
        'label': label,
        'gitName': gitName,
        'gitEmail': gitEmail,
        'sshKeyPath': sshKeyPath,
      };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.ghUsername == ghUsername &&
      other.label == label &&
      other.gitName == gitName &&
      other.gitEmail == gitEmail &&
      other.sshKeyPath == sshKeyPath;

  @override
  int get hashCode =>
      Object.hash(ghUsername, label, gitName, gitEmail, sshKeyPath);

  @override
  String toString() => 'Account($ghUsername, label: $label)';
}
