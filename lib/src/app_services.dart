import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models/switch_result.dart';
import 'platform/binary_locator.dart';
import 'platform/process_runner.dart';
import 'platform/process_starter.dart';
import 'services/account_store.dart';
import 'services/gh_login_session.dart';
import 'services/account_switcher.dart';
import 'services/gh_client.dart';
import 'services/git_config_writer.dart';
import 'services/git_identity_writer.dart';
import 'services/managed_block.dart';
import 'services/notifier.dart';
import 'services/profile_client.dart';
import 'services/profile_store.dart';
import 'services/repo_identity_writer.dart';
import 'services/ssh_config_writer.dart';
import 'services/ssh_key_creator.dart';
import 'services/ssh_tester.dart';
import 'services/tool_installer.dart';

/// Wires the real implementations together at startup.
class AppServices {
  AppServices._({
    required this.store,
    required this.gh,
    required this.switcher,
    required this.notifier,
    required this.profiles,
    required this.repoIdentity,
    required this.gitConfig,
    required this.sshTester,
    required this.tools,
    required this.keys,
    required this.removedLegacyHook,
    required BinaryLocator locator,
  }) : _locator = locator;

  final BinaryLocator _locator;

  /// A fresh login flow. Each attempt gets its own session because a session
  /// ends when its process exits.
  ///
  /// [gh] is passed so an abandoned login cannot leave the wrong account
  /// active.
  GhLoginSession createLoginSession() => GhLoginSession(
        starter: const RealProcessStarter(),
        locator: _locator,
        gh: gh,
      );

  final AccountStore store;
  final GhClient gh;
  final AccountSwitcher switcher;
  final Notifier notifier;
  final ProfileStore profiles;
  final RepoIdentityWriter repoIdentity;
  final GitConfigWriter gitConfig;
  final SshTester sshTester;
  final ToolInstaller tools;
  final SshKeyCreator keys;

  /// True on the first launch after upgrading from the zsh-hook version, so
  /// the user can be told why their folder setup changed.
  final bool removedLegacyHook;

  /// Rewrites the git config block for the current settings. Called whenever
  /// accounts or folder rules change, not only on a switch.
  Future<StepResult> syncGitConfig() async => gitConfig.sync(
        await store.loadConfig(),
        (await gh.discover()).activeUsername,
      );

  static Future<AppServices> create() async {
    const runner = RealProcessRunner();
    final home = Platform.environment['HOME']!;

    final supportDir = await getApplicationSupportDirectory();
    // Where ToolInstaller puts gh. Searched last, so a gh the user installed
    // themselves always wins.
    final binDir = Directory('${supportDir.path}/bin');
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: [...kBinarySearchDirs, binDir.path],
    );
    final store = AccountStore(File('${supportDir.path}/accounts.json'));
    final removedLegacyHook = await _removeLegacyShellHook(
      zshrc: File('$home/.zshrc'),
      stateFile: File('${supportDir.path}/cwd'),
    );
    final gitConfig = GitConfigWriter(
      gitconfig: File('$home/.gitconfig'),
      directory: Directory('${supportDir.path}/git'),
      home: home,
      ghPath: () async {
        try {
          return await locator.locate('gh');
        } on BinaryNotFoundException {
          return null;
        }
      },
    );

    final gh = GhClient(
      runner: runner,
      locator: locator,
      hostsFile: File('$home/.config/gh/hosts.yml'),
    );

    return AppServices._(
      store: store,
      gh: gh,
      notifier: const Notifier(),
      repoIdentity: RepoIdentityWriter(runner: runner, locator: locator),
      gitConfig: gitConfig,
      sshTester: SshTester(runner: runner, home: home),
      tools: ToolInstaller(runner: runner, binDir: binDir),
      keys: SshKeyCreator(runner: runner, locator: locator, home: home),
      removedLegacyHook: removedLegacyHook,
      locator: locator,
      profiles: ProfileStore(
        client: ProfileClient(runner: runner, locator: locator),
        avatars: AvatarCache(
          directory: Directory('${supportDir.path}/avatars'),
        ),
      ),
      switcher: AccountSwitcher(
        gh: gh,
        git: GitIdentityWriter(runner: runner, locator: locator),
        ssh: SshConfigWriter(
          file: File('$home/.ssh/config'),
          runner: runner,
        ),
        gitConfig: gitConfig,
        store: store,
      ),
    );
  }

  /// Folder rules used to work through a zsh hook. git's own includeIf
  /// replaced it, so take the old hook back out of `~/.zshrc` for anyone
  /// upgrading. Best effort: a failure here must not stop the app starting.
  /// Returns true when a hook was found and removed.
  static Future<bool> _removeLegacyShellHook({
    required File zshrc,
    required File stateFile,
  }) async {
    const block = ManagedBlock(
      beginMarker: '# >>> GitSwitcher (managed — do not edit)',
      endMarker: '# <<< GitSwitcher',
    );
    try {
      if (await stateFile.exists()) await stateFile.delete();
      if (!await zshrc.exists()) return false;
      final existing = await zshrc.readAsString();
      final updated = block.removeFrom(existing);
      if (updated == existing) return false;
      await const BackupWriter().write(zshrc, existing);
      await zshrc.writeAsString(updated);
      return true;
    } on FileSystemException {
      // Leave it; the hook only writes a file nobody reads any more.
      return false;
    }
  }
}
