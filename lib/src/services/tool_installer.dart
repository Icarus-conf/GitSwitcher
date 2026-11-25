import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import '../platform/process_runner.dart';

typedef Fetch = Future<List<int>> Function(Uri url);

/// Gets the two command-line tools GitSwitcher drives onto a fresh Mac.
///
/// - git comes from Apple's Command Line Tools. `/usr/bin/git` exists on every
///   Mac but is only a stub until those are installed, so its presence proves
///   nothing; `xcode-select -p` is the real test, and `xcode-select --install`
///   opens Apple's own installer.
/// - gh is downloaded from its official GitHub release into the app's own
///   folder, checked against the SHA-256 GitHub publishes for the file. No
///   admin password and no Homebrew needed. A gh the user installed
///   themselves still wins, because that folder is searched last.
class ToolInstaller {
  ToolInstaller({
    required ProcessRunner runner,
    required Directory binDir,
    Fetch? fetch,
    bool Function(String path)? exists,
    Abi? abi,
  })  : _runner = runner,
        _binDir = binDir,
        _fetch = fetch ?? _httpGet,
        _exists = exists ?? ((p) => File(p).existsSync()),
        _abi = abi ?? Abi.current();

  final ProcessRunner _runner;
  final Directory _binDir;
  final Fetch _fetch;
  final bool Function(String path) _exists;
  final Abi _abi;

  static final Uri latestRelease =
      Uri.parse('https://api.github.com/repos/cli/cli/releases/latest');

  Future<bool> gitInstalled() async {
    if (_exists('/opt/homebrew/bin/git') || _exists('/usr/local/bin/git')) {
      return true;
    }
    return (await _runner.run('/usr/bin/xcode-select', ['-p'])).ok;
  }

  /// Opens Apple's installer dialog and returns straight away; the install
  /// itself runs in that dialog and takes a few minutes.
  Future<void> installGit() =>
      _runner.run('/usr/bin/xcode-select', ['--install']);

  /// Downloads the latest gh and returns its version tag.
  ///
  /// Throws [ToolInstallException] with a message fit to show the user.
  Future<String> installGh() async {
    final arch = _abi == Abi.macosArm64 ? 'arm64' : 'amd64';

    final Map<String, dynamic> release;
    try {
      release = jsonDecode(utf8.decode(await _fetch(latestRelease)))
          as Map<String, dynamic>;
    } catch (error) {
      throw ToolInstallException('could not reach GitHub: $error');
    }

    final tag = release['tag_name'] as String? ?? '?';
    final asset = (release['assets'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((a) => (a['name'] as String).endsWith('_macOS_$arch.zip'))
        .firstOrNull;
    if (asset == null) {
      throw ToolInstallException('gh $tag has no macOS $arch download');
    }
    // GitHub computes this digest itself on upload; refusing without it is
    // what stops a tampered or truncated download from being run.
    final digest = asset['digest'] as String? ?? '';
    if (!digest.startsWith('sha256:')) {
      throw ToolInstallException('gh $tag has no published checksum');
    }

    final work = await Directory.systemTemp.createTemp('gitswitcher-gh');
    try {
      final zip = File('${work.path}/gh.zip');
      try {
        await zip.writeAsBytes(
          await _fetch(Uri.parse(asset['browser_download_url'] as String)),
        );
      } catch (error) {
        throw ToolInstallException('download failed: $error');
      }

      final sum = await _runner.run('/usr/bin/shasum', ['-a', '256', zip.path]);
      final actual = sum.stdout.split(' ').first;
      if (!sum.ok || 'sha256:$actual' != digest) {
        throw ToolInstallException(
            'the download did not match its checksum; nothing was installed');
      }

      final unpacked = await _runner.run(
          '/usr/bin/ditto', ['-x', '-k', zip.path, '${work.path}/out']);
      if (!unpacked.ok) {
        throw ToolInstallException('could not unzip: ${unpacked.errorText}');
      }

      final binary = (await Directory('${work.path}/out')
              .list(recursive: true)
              .where((e) => e is File && e.path.endsWith('/bin/gh'))
              .toList())
          .firstOrNull;
      if (binary == null) {
        throw ToolInstallException('the gh download had an unexpected layout');
      }

      await _binDir.create(recursive: true);
      final target = '${_binDir.path}/gh';
      await (binary as File).copy(target);
      await _runner.run('/bin/chmod', ['755', target]);
      return tag;
    } finally {
      await work.delete(recursive: true);
    }
  }

  static Future<List<int>> _httpGet(Uri url) async {
    final client = HttpClient()..userAgent = 'GitSwitcher';
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final bytes = BytesBuilder(copy: false);
      await response.forEach(bytes.add);
      return bytes.takeBytes();
    } finally {
      client.close();
    }
  }
}

class ToolInstallException implements Exception {
  ToolInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
