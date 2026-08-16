import 'account.dart';
import 'directory_rule.dart';

/// Everything the app persists: accounts, directory rules, and settings.
class AppConfig {
  const AppConfig({
    this.accounts = const [],
    this.rules = const [],
    this.autoSwitchEnabled = false,
  });

  final List<Account> accounts;
  final List<DirectoryRule> rules;
  final bool autoSwitchEnabled;

  /// Bumped to 2 when directory rules were added. Version 1 files hold only
  /// accounts and are read without loss.
  static const int schemaVersion = 2;

  AppConfig copyWith({
    List<Account>? accounts,
    List<DirectoryRule>? rules,
    bool? autoSwitchEnabled,
  }) {
    return AppConfig(
      accounts: accounts ?? this.accounts,
      rules: rules ?? this.rules,
      autoSwitchEnabled: autoSwitchEnabled ?? this.autoSwitchEnabled,
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final accounts = (json['accounts'] as List? ?? const [])
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();

    // Version 1 has no rules or settings; the defaults below are the migration.
    final rules = (json['rules'] as List? ?? const [])
        .map((e) => DirectoryRule.fromJson(e as Map<String, dynamic>))
        .toList();

    return AppConfig(
      accounts: accounts,
      rules: rules,
      autoSwitchEnabled: json['autoSwitchEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': schemaVersion,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'autoSwitchEnabled': autoSwitchEnabled,
      };
}
