import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import '../platform/host.dart';

/// A newer GitSwitcher release, and where to get it.
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.downloadUrl});

  final String version;

  /// This system's zip when the release has one, else the release page.
  final String downloadUrl;
}

typedef FetchJson = Future<Map<String, dynamic>> Function(Uri url);

/// Asks GitHub whether a newer release of GitSwitcher exists.
///
/// The running version comes from `--dart-define=APP_VERSION=…`, which only
/// the release workflow sets. A build made any other way has no version and
/// never claims to be out of date.
class UpdateChecker {
  UpdateChecker({
    String currentVersion = const String.fromEnvironment('APP_VERSION'),
    FetchJson? fetch,
  })  : _current = currentVersion,
        _fetch = fetch ?? _httpGetJson;

  final String _current;
  final FetchJson _fetch;

  static final Uri latestRelease = Uri.parse(
      'https://api.github.com/repos/Icarus-conf/GitSwitcher/releases/latest');

  /// The newer release, or null when up to date, unknown, or offline.
  Future<AvailableUpdate?> check() async {
    if (_current.isEmpty) return null;
    try {
      final release = await _fetch(latestRelease);
      final tag = release['tag_name'] as String? ?? '';
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!isNewer(latest, _current)) return null;

      final suffix = Host.current.isWindows ? '-windows.zip' : '-macos.zip';
      final asset = (release['assets'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .where((a) => (a['name'] as String? ?? '').endsWith(suffix))
          .firstOrNull;
      return AvailableUpdate(
        version: latest,
        downloadUrl: (asset?['browser_download_url'] ??
            release['html_url']) as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Compares `MAJOR.MINOR.PATCH` numerically, so 0.10.0 beats 0.9.0.
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) =>
        v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(candidate), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Future<Map<String, dynamic>> _httpGetJson(Uri url) async {
    final client = HttpClient()..userAgent = 'GitSwitcher';
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add);
      return jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
