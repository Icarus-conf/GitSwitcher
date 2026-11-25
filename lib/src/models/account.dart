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
    this.signCommits = false,
  });

  final String ghUsername;
  final String label;
  final String gitName;
  final String gitEmail;
  final String sshKeyPath;

  /// Sign commits with [sshKeyPath]. GitHub only shows them as Verified once
  /// that key is also added to the account as a signing key.
  final bool signCommits;

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
    bool? signCommits,
  }) {
    return Account(
      ghUsername: ghUsername,
      label: label ?? this.label,
      gitName: gitName ?? this.gitName,
      gitEmail: gitEmail ?? this.gitEmail,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      signCommits: signCommits ?? this.signCommits,
    );
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      ghUsername: json['ghUsername'] as String,
      label: json['label'] as String? ?? '',
      gitName: json['gitName'] as String? ?? '',
      gitEmail: json['gitEmail'] as String? ?? '',
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
      signCommits: json['signCommits'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'ghUsername': ghUsername,
        'label': label,
        'gitName': gitName,
        'gitEmail': gitEmail,
        'sshKeyPath': sshKeyPath,
        'signCommits': signCommits,
      };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.ghUsername == ghUsername &&
      other.label == label &&
      other.gitName == gitName &&
      other.gitEmail == gitEmail &&
      other.sshKeyPath == sshKeyPath &&
      other.signCommits == signCommits;

  @override
  int get hashCode =>
      Object.hash(ghUsername, label, gitName, gitEmail, sshKeyPath, signCommits);

  @override
  String toString() => 'Account($ghUsername, label: $label)';
}
