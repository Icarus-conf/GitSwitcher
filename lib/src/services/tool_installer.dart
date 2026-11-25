import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart' show sha256;

import '../platform/host.dart';
import '../platform/process_runner.dart';

typedef Fetch = Future<List<int>> Function(Uri url);

/// Gets the two command-line tools GitSwitcher drives onto a fresh machine.
///
/// - git on macOS comes from Apple's Command Line Tools. `/usr/bin/git` exists
///   on every Mac but is only a stub until those are installed, so its
///   presence proves nothing; `xcode-select -p` is the real test, and
///   `xcode-select --install` opens Apple's own installer.
/// - git on Windows is Git for Windows, installed through winget.
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

  bool get _windows => Host.current.isWindows;

  Future<bool> gitInstalled() async {
    if (_windows) {
      final programs = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      if (_exists('$programs\\Git\\cmd\\git.exe')) return true;
      return (await _runner.run('where.exe', ['git'])).ok;
    }
    if (_exists('/opt/homebrew/bin/git') || _exists('/usr/local/bin/git')) {
      return true;
    }
    return (await _runner.run('/usr/bin/xcode-select', ['-p'])).ok;
  }

  /// Starts git's installer and returns what to tell the user.
  ///
  /// On macOS this opens Apple's dialog and returns at once. On Windows it
  /// runs winget, which shows its own progress and a UAC prompt, and returns
  /// when it finishes; without winget, git's download page opens instead.
  Future<String> installGit() async {
    if (!_windows) {
      await _runner.run('/usr/bin/xcode-select', ['--install']);
      return "Follow Apple's installer, then press Check again when it "
          'finishes.';
    }
    final result = await _runner.run('winget', [
      'install', '--id', 'Git.Git', '--exact', '--source', 'winget',
      // The user pressed Install; these only stop winget waiting on a
      // console prompt nobody can see.
      '--accept-package-agreements', '--accept-source-agreements',
    ]);
    if (result.ok) return 'git installed. Press Check again.';
    await Host.current.openUrl(_runner, 'https://git-scm.com/download/win');
    return 'Could not install git automatically. Its download page is open.';
  }

  /// Downloads the latest gh and returns its version tag.
  ///
  /// Throws [ToolInstallException] with a message fit to show the user.
  Future<String> installGh() async {
    final arch =
        _abi == Abi.macosArm64 || _abi == Abi.windowsArm64 ? 'arm64' : 'amd64';
    final os = _windows ? 'windows' : 'macOS';

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
        .where((a) => (a['name'] as String).endsWith('_${os}_$arch.zip'))
        .firstOrNull;
    if (asset == null) {
      throw ToolInstallException('gh $tag has no $os $arch download');
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
      final List<int> bytes;
      try {
        bytes = await _fetch(Uri.parse(asset['browser_download_url'] as String));
      } catch (error) {
        throw ToolInstallException('download failed: $error');
      }
      if ('sha256:${sha256.convert(bytes)}' != digest) {
        throw ToolInstallException(
            'the download did not match its checksum; nothing was installed');
      }
      await zip.writeAsBytes(bytes);

      final out = Directory('${work.path}/out')..createSync();
      final unpacked = await _runner.run(
        _windows ? _windowsTar : '/usr/bin/ditto',
        _windows
            ? ['-xf', zip.path, '-C', out.path]
            : ['-x', '-k', zip.path, out.path],
      );
      if (!unpacked.ok) {
        throw ToolInstallException('could not unzip: ${unpacked.errorText}');
      }

      final name = Host.current.exe('gh');
      final binary = (await out
              .list(recursive: true)
              .where((e) =>
                  e is File &&
                  e.uri.pathSegments.last == name &&
                  e.parent.uri.pathSegments.reversed
                          .firstWhere((s) => s.isNotEmpty) ==
                      'bin')
              .toList())
          .firstOrNull;
      if (binary == null) {
        throw ToolInstallException('the gh download had an unexpected layout');
      }

      await _binDir.create(recursive: true);
      final target = Host.current.join(_binDir.path, name);
      await (binary as File).copy(target);
      await Host.current.chmod(_runner, '755', target);
      return tag;
    } finally {
      await work.delete(recursive: true);
    }
  }

  /// Re-downloads the gh this app installed when a newer release exists.
  /// Returns the new tag, or null when there was nothing to do. A gh the user
  /// installed themselves is theirs to update and is never touched.
  ///
  /// ponytail: checked once per launch; add a timer if people leave the app
  /// running for weeks.
  Future<String?> updateGh() async {
    final ours = Host.current.join(_binDir.path, Host.current.exe('gh'));
    if (!_exists(ours)) return null;

    final Map<String, dynamic> release;
    try {
      release = jsonDecode(utf8.decode(await _fetch(latestRelease)))
          as Map<String, dynamic>;
    } catch (_) {
      return null; // Offline is normal; try again next launch.
    }
    final latest = release['tag_name'] as String? ?? '';
    // `gh version 2.89.0 (2026-03-26)` → v2.89.0
    final current = (await _runner.run(ours, ['--version']))
        .stdout
        .split(' ')
        .elementAtOrNull(2);
    if (latest.isEmpty || current == null || 'v$current' == latest) return null;

    return installGh();
  }

  /// Windows' own bsdtar, by full path: Git for Windows puts GNU tar on PATH
  /// too, and GNU tar reads `C:\...` as a remote host name.
  static String get _windowsTar =>
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe';

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
