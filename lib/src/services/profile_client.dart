import 'dart:convert';
import 'dart:io';

import '../models/github_profile.dart';
import '../platform/binary_locator.dart';
import '../platform/process_runner.dart';

/// Fetches public GitHub profiles through the gh CLI.
///
/// Going through `gh api` rather than raw HTTP means this app never handles a
/// token: gh reads it from the keychain and signs the request itself. The
/// endpoint is public, so one account's token can look up another's profile —
/// no switching required just to draw a menu.
class ProfileClient {
  ProfileClient({required ProcessRunner runner, required BinaryLocator locator})
      : _runner = runner,
        _locator = locator;

  final ProcessRunner _runner;
  final BinaryLocator _locator;

  /// Returns null on any failure. A missing avatar must never break the menu.
  Future<GitHubProfile?> fetch(String login) async {
    try {
      final gh = await _locator.locate('gh');
      final result = await _runner.run(gh, ['api', 'users/$login']);
      if (!result.ok) return null;

      return GitHubProfile.fromJson(
        jsonDecode(result.stdout) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef AvatarDownloader = Future<List<int>> Function(String url);

/// Stores avatar images on disk so the menu never waits on the network twice.
class AvatarCache {
  AvatarCache({required Directory directory, AvatarDownloader? download})
      : _directory = directory,
        _download = download ?? _defaultDownload;

  final Directory _directory;
  final AvatarDownloader _download;

  static Future<List<int>> _defaultDownload(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) return <int>[];
      return await response.expand((chunk) => chunk).toList();
    } finally {
      client.close();
    }
  }

  /// Path to the cached avatar, downloading it first if needed.
  ///
  /// Returns null when the image cannot be obtained, so callers render an
  /// account with no picture rather than failing.
  Future<String?> pathFor(String login, String url) async {
    final file = File('${_directory.path}/$login.png');
    if (await file.exists()) return file.path;

    try {
      final bytes = await _download(url);
      if (bytes.isEmpty) return null;

      await _directory.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Forgets a cached image so the next lookup re-downloads it.
  Future<void> evict(String login) async {
    final file = File('${_directory.path}/$login.png');
    if (await file.exists()) await file.delete();
  }
}
