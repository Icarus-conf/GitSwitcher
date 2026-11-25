import 'dart:io';

import '../models/account.dart';
import '../platform/binary_locator.dart';
import '../platform/host.dart';
import '../platform/process_runner.dart';
import 'git_config_writer.dart';

/// What [SshKeyCreator.create] did.
class CreatedKey {
  const CreatedKey({
    required this.path,
    required this.publicKey,
    required this.uploaded,
    this.problem,
  });

  /// Where the private key is, written with `~` so it reads naturally.
  final String path;
  final String publicKey;

  /// True when GitHub now has the key for both pushing and signing.
  final bool uploaded;

  /// Why it was not uploaded, when it was not.
  final String? problem;
}

/// Makes an SSH key for one account and adds it to that account on GitHub.
///
/// The key has no passphrase: GitSwitcher and GUI git clients have no way to
/// type one, so a protected key would fail silently at every push. It is
/// readable only by the user, like any key ssh-keygen makes.
///
/// Uploading uses that account's own token (`GH_TOKEN`), so it works for
/// accounts other than the active one. The token needs the key scopes, which
/// only logins made by this version request; older tokens fall back to the
/// user pasting the key on GitHub's page.
class SshKeyCreator {
  SshKeyCreator({
    required ProcessRunner runner,
    required BinaryLocator locator,
    required String home,
    String? hostname,
  })  : _runner = runner,
        _locator = locator,
        _home = home,
        _hostname = hostname ?? Platform.localHostname;

  final ProcessRunner _runner;
  final BinaryLocator _locator;
  final String _home;
  final String _hostname;

  static final Uri addKeyPage = Uri.parse('https://github.com/settings/ssh/new');

  Future<CreatedKey> create(Account account) async {
    final login = account.ghUsername;
    final path = '~/.ssh/gitswitcher_$login';
    final file = expandTilde(path, _home);

    // Never overwrite: an existing key may already be in use somewhere. It is
    // reused instead, so pressing the button twice is harmless.
    if (!await File(file).exists()) {
      final sshDir = Directory('$_home/.ssh');
      if (!await sshDir.exists()) {
        await sshDir.create();
        await Host.current.chmod(_runner, '700', sshDir.path);
      }
      final made = await _runner.run(await _locator.locate('ssh-keygen'), [
        '-t', 'ed25519', '-N', '', '-q',
        '-C', '$login@GitSwitcher',
        '-f', file,
      ]);
      if (!made.ok) {
        throw FileSystemException('ssh-keygen failed: ${made.errorText}', file);
      }
    }
    final publicKey = (await File('$file.pub').readAsString()).trim();

    final problem = await _upload(login, '$file.pub');
    return CreatedKey(
      path: path,
      publicKey: publicKey,
      uploaded: problem == null,
      problem: problem,
    );
  }

  /// Adds the account's existing key to GitHub, for a key GitHub no longer
  /// accepts. Same result shape as [create].
  Future<CreatedKey> upload(Account account) async {
    final file = expandTilde(account.sshKeyPath, _home);
    final publicKey = (await File('$file.pub').readAsString()).trim();
    final problem = await _upload(account.ghUsername, '$file.pub');
    return CreatedKey(
      path: account.sshKeyPath,
      publicKey: publicKey,
      uploaded: problem == null,
      problem: problem,
    );
  }

  /// Returns null on success, or why the key could not be added.
  Future<String?> _upload(String login, String publicKeyFile) async {
    final String gh;
    try {
      gh = await _locator.locate('gh');
    } on BinaryNotFoundException {
      return 'the GitHub CLI is not installed';
    }

    final token = await _runner.run(
        gh, ['auth', 'token', '--hostname', 'github.com', '--user', login]);
    if (!token.ok || token.stdout.isEmpty) return '$login is not signed in to gh';

    for (final type in ['authentication', 'signing']) {
      final added = await _runner.run(
        gh,
        ['ssh-key', 'add', publicKeyFile,
         '--title', 'GitSwitcher ($_hostname)', '--type', type],
        environment: {'GH_TOKEN': token.stdout},
      );
      // Adding a key GitHub already has is not a failure.
      if (!added.ok && !added.errorText.contains('already')) {
        return added.errorText.contains('scope')
            ? 'this sign-in cannot add keys'
            : added.errorText;
      }
    }
    return null;
  }

  Future<void> openAddKeyPage() =>
      Host.current.openUrl(_runner, addKeyPage.toString());
}
