import 'account.dart';
import 'directory_rule.dart';

/// Everything the app persists: accounts, directory rules, and settings.
class AppConfig {
  const AppConfig({
    this.accounts = const [],
    this.rules = const [],
    this.orgRules = const [],
    this.autoSwitchEnabled = false,
  });

  final List<Account> accounts;
  final List<DirectoryRule> rules;

  /// Repos whose remote is under a GitHub organization. Applied after folder
  /// rules, so "anything from acme is Work" holds even inside ~/personal.
  final List<OrgRule> orgRules;
  final bool autoSwitchEnabled;

  /// Bumped to 2 when directory rules were added. Version 1 files hold only
  /// accounts and are read without loss.
  static const int schemaVersion = 2;

  AppConfig copyWith({
    List<Account>? accounts,
    List<DirectoryRule>? rules,
    List<OrgRule>? orgRules,
    bool? autoSwitchEnabled,
  }) {
    return AppConfig(
      accounts: accounts ?? this.accounts,
      rules: rules ?? this.rules,
      orgRules: orgRules ?? this.orgRules,
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

    final orgRules = (json['orgRules'] as List? ?? const [])
        .map((e) => OrgRule.fromJson(e as Map<String, dynamic>))
        .toList();

    return AppConfig(
      accounts: accounts,
      rules: rules,
      orgRules: orgRules,
      autoSwitchEnabled: json['autoSwitchEnabled'] as bool? ?? false,
    );
  }

  /// A copy for another computer: paths under [home] are written with `~`,
  /// which the app expands to whichever home folder it runs under, Mac or
  /// Windows. Keys themselves are files and are not included.
  AppConfig portable(String home) {
    String tilde(String path) {
      final normal = path.replaceAll(r'\', '/');
      final h = home.replaceAll(r'\', '/');
      if (h.isEmpty) return path;
      if (normal == h) return '~';
      return normal.startsWith('$h/') ? '~${normal.substring(h.length)}' : path;
    }

    return copyWith(
      accounts: [
        for (final a in accounts) a.copyWith(sshKeyPath: tilde(a.sshKeyPath)),
      ],
      rules: [
        for (final r in rules)
          DirectoryRule(pathPrefix: tilde(r.pathPrefix), ghUsername: r.ghUsername),
      ],
    );
  }

  /// This config with [imported] laid over it: imported accounts and rules
  /// win where they overlap, everything else here is kept. An import never
  /// silently deletes anything.
  AppConfig mergedWith(AppConfig imported) {
    List<T> merge<T>(List<T> mine, List<T> theirs, Object Function(T) key) {
      final byKey = {for (final x in mine) key(x): x};
      for (final x in theirs) {
        byKey[key(x)] = x;
      }
      return byKey.values.toList();
    }

    return AppConfig(
      accounts: merge(accounts, imported.accounts, (a) => a.ghUsername),
      rules: merge(rules, imported.rules, (r) => r.pathPrefix),
      orgRules: merge(orgRules, imported.orgRules, (r) => r.org.toLowerCase()),
      autoSwitchEnabled: autoSwitchEnabled || imported.autoSwitchEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': schemaVersion,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'orgRules': orgRules.map((r) => r.toJson()).toList(),
        'autoSwitchEnabled': autoSwitchEnabled,
      };
}
