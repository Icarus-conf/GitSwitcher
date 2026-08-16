import 'dart:async';

import '../models/github_profile.dart';
import 'profile_client.dart';

/// Profile plus cached avatar path for one account.
class AccountProfile {
  const AccountProfile({required this.profile, required this.avatarPath});

  final GitHubProfile profile;

  /// Local file path to the cached avatar, or null when unavailable.
  final String? avatarPath;
}

/// In-memory profile lookup, populated in the background.
///
/// The menu must never wait on the network: it reads whatever is already
/// loaded, and [refresh] fills the gaps and notifies when something changed.
class ProfileStore {
  ProfileStore({
    required ProfileClient client,
    required AvatarCache avatars,
    int avatarSize = 64,
  })  : _client = client,
        _avatars = avatars,
        _avatarSize = avatarSize;

  final ProfileClient _client;
  final AvatarCache _avatars;
  final int _avatarSize;

  final Map<String, AccountProfile> _byLogin = {};
  final _changes = StreamController<void>.broadcast();

  /// Emits whenever newly loaded profiles change what the UI should show.
  Stream<void> get changes => _changes.stream;

  AccountProfile? operator [](String login) => _byLogin[login];

  /// Loads any profile not already known. Already-known logins are skipped, so
  /// this is cheap to call on every menu open.
  Future<void> refresh(Iterable<String> logins) async {
    final missing = logins.where((l) => !_byLogin.containsKey(l)).toList();
    if (missing.isEmpty) return;

    var changed = false;
    for (final login in missing) {
      final profile = await _client.fetch(login);
      if (profile == null) continue;

      _byLogin[login] = AccountProfile(
        profile: profile,
        avatarPath: await _avatars.pathFor(
          login,
          profile.sizedAvatarUrl(_avatarSize),
        ),
      );
      changed = true;
    }

    if (changed && !_changes.isClosed) _changes.add(null);
  }

  void dispose() => _changes.close();
}
