import 'dart:io';

import 'process_runner.dart';

/// Everything that differs between macOS and Windows, kept in one place so the
/// rest of the app never asks which system it is on.
///
/// [current] is a plain variable rather than a getter so tests can pin it:
/// most tests describe macOS behaviour and set `Host.current = Host.macos`,
/// which keeps them meaningful when the suite runs on Windows CI too.
class Host {
  const Host._(this.isWindows);

  static const Host macos = Host._(false);
  static const Host windows = Host._(true);

  static Host current = Platform.isWindows ? windows : macos;

  final bool isWindows;

  bool get isMacOS => !isWindows;

  static String _env(String name) => Platform.environment[name] ?? '';

  /// The user's home folder. Windows has no HOME by default; git, ssh and gh
  /// all fall back to USERPROFILE there, so this does too.
  String get home => isWindows
      ? (_env('HOME').isNotEmpty ? _env('HOME') : _env('USERPROFILE'))
      : _env('HOME');

  /// Where gh keeps hosts.yml. On Windows that is %AppData%\GitHub CLI, not
  /// ~/.config/gh.
  String ghConfigDir(String home) {
    final override = _env('GH_CONFIG_DIR');
    if (override.isNotEmpty) return override;
    return isWindows ? '${_env('APPDATA')}\\GitHub CLI' : '$home/.config/gh';
  }

  /// Where CLI tools normally live, in probe order.
  ///
  /// On Windows the Git for Windows `usr\bin` folder comes before the system
  /// OpenSSH, so ssh and ssh-keygen are the same ones git itself uses.
  List<String> get binarySearchDirs {
    if (!isWindows) return const ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin'];
    final programs = _env('ProgramFiles').isEmpty
        ? r'C:\Program Files'
        : _env('ProgramFiles');
    final system = _env('SystemRoot').isEmpty ? r'C:\Windows' : _env('SystemRoot');
    return [
      '$programs\\GitHub CLI',
      '$programs\\Git\\cmd',
      '$programs\\Git\\usr\\bin',
      '$system\\System32\\OpenSSH',
    ];
  }

  String exe(String name) => isWindows ? '$name.exe' : name;

  String join(String dir, String name) =>
      isWindows ? '$dir\\$name' : '$dir/$name';

  /// The command that finds [name] on the user's PATH. A Windows GUI app
  /// inherits the user's PATH; a macOS one does not, hence the login shell.
  (String, List<String>) which(String name) => isWindows
      ? ('where.exe', [name])
      : ('/bin/zsh', ['-lc', 'which $name']);

  Future<void> openUrl(ProcessRunner runner, String url) => isWindows
      ? runner.run('rundll32', ['url.dll,FileProtocolHandler', url])
      : runner.run('/usr/bin/open', [url]);

  /// Restricts a file to its owner. Windows has no modes; files under the
  /// user's profile already inherit owner-only access, which is what
  /// Windows OpenSSH checks for.
  Future<void> chmod(ProcessRunner runner, String mode, String path) async {
    if (!isWindows) await runner.run('/bin/chmod', [mode, path]);
  }

  /// A path as git and ssh config files want it: forward slashes. Both
  /// accept `C:/Users/...` on Windows, and backslashes would need escaping.
  String configPath(String path) =>
      isWindows ? path.replaceAll(r'\', '/') : path;
}
