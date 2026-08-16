import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models/directory_rule.dart';
import 'platform/binary_locator.dart';
import 'platform/process_runner.dart';
import 'platform/process_starter.dart';
import 'services/account_store.dart';
import 'services/gh_login_session.dart';
import 'services/auto_switcher.dart';
import 'services/shell_hook_installer.dart';
import 'services/account_switcher.dart';
import 'services/gh_client.dart';
import 'services/git_identity_writer.dart';
import 'services/notifier.dart';
import 'services/profile_client.dart';
import 'services/profile_store.dart';
import 'services/repo_identity_writer.dart';
import 'services/ssh_config_writer.dart';

/// Wires the real implementations together at startup.
class AppServices {
  AppServices._({
    required this.store,
    required this.gh,
    required this.switcher,
    required this.notifier,
    required this.profiles,
    required this.repoIdentity,
    required this.hooks,
    required this.watcher,
    required this.policy,
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
  final ShellHookInstaller hooks;
  final CwdWatcher watcher;
  final AutoSwitchPolicy policy;

  static Future<AppServices> create() async {
    const runner = RealProcessRunner();
    final locator = BinaryLocator(runner: runner);
    final home = Platform.environment['HOME']!;

    final supportDir = await getApplicationSupportDirectory();
    final store = AccountStore(File('${supportDir.path}/accounts.json'));
    final stateFile = File('${supportDir.path}/cwd');

    final gh = GhClient(
      runner: runner,
      locator: locator,
      hostsFile: File('$home/.config/gh/hosts.yml'),
    );

    return AppServices._(
      store: store,
      gh: gh,
      notifier: const Notifier(runner),
      repoIdentity: RepoIdentityWriter(runner: runner, locator: locator),
      hooks: ShellHookInstaller(
        zshrc: File('$home/.zshrc'),
        stateFile: stateFile,
      ),
      watcher: CwdWatcher(stateFile: stateFile),
      policy: AutoSwitchPolicy(matcher: RuleMatcher(home: home)),
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
      ),
    );
  }
}
