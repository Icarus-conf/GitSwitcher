import '../models/account.dart';
import 'gh_client.dart';

/// A stored account joined with what gh currently reports about it.
class ResolvedAccount {
  const ResolvedAccount({
    required this.account,
    required this.isActive,
    required this.isLoggedIn,
  });

  final Account account;

  /// True when gh's active account is this one.
  final bool isActive;

  /// True when gh still has credentials for this account.
  final bool isLoggedIn;

  /// Whether the menu lets the user pick this account.
  ///
  /// Being logged in is the only requirement: `gh auth switch` works with no
  /// configuration at all, and that switch is the most useful thing this app
  /// does. Gating it behind filling in a git email would make the app look
  /// broken on first launch, exactly when it should be most useful. Steps the
  /// account has not configured report themselves as skipped instead.
  bool get isSelectable => isLoggedIn;

  /// Why this account cannot be selected, or null if it can be.
  String? get disabledReason {
    if (!isLoggedIn) return 'not logged in to gh — run: gh auth login';
    return null;
  }

  /// What selecting this account will not do yet, or null when fully set up.
  String? get setupHint {
    if (!isLoggedIn || account.isComplete) return null;
    return 'gh only — add a git email or SSH key in Settings';
  }
}

/// Joins the app's stored configuration with gh's live account list.
///
/// A stored account is never dropped just because gh forgot it — the user
/// typed its email and key path, and losing that silently would be worse than
/// showing a disabled row.
class AccountResolver {
  const AccountResolver._();

  static List<ResolvedAccount> merge({
    required List<Account> stored,
    required GhAccounts discovered,
  }) {
    final resolved = <ResolvedAccount>[];
    final seen = <String>{};

    for (final account in stored) {
      seen.add(account.ghUsername);
      resolved.add(ResolvedAccount(
        account: account,
        isActive: account.ghUsername == discovered.activeUsername,
        isLoggedIn: discovered.usernames.contains(account.ghUsername),
      ));
    }

    for (final username in discovered.usernames) {
      if (seen.contains(username)) continue;
      resolved.add(ResolvedAccount(
        account: Account(ghUsername: username),
        isActive: username == discovered.activeUsername,
        isLoggedIn: true,
      ));
    }

    return resolved;
  }
}
