import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/models/account.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/process_runner.dart';
import 'package:git_switcher/src/services/ssh_key_creator.dart';

import '../support/fake_process_runner.dart';

/// Runs ssh-keygen and chmod for real; gh is faked from [gh].
class _Runner implements ProcessRunner {
  _Runner(this.gh);

  final FakeProcessRunner gh;

  @override
  Future<CommandResult> run(String executable, List<String> arguments,
      {Map<String, String>? environment}) {
    if (executable.endsWith('/gh')) {
      return gh.run(executable, arguments, environment: environment);
    }
    return const RealProcessRunner().run(executable, arguments);
  }
}

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('gitswitcher_keys'));
  tearDown(() => home.deleteSync(recursive: true));

  const gh = '/opt/homebrew/bin/gh';
  const tokenCmd = '$gh auth token --hostname github.com --user octo';

  SshKeyCreator creator(FakeProcessRunner fake) => SshKeyCreator(
        runner: _Runner(fake),
        home: home.path,
        hostname: 'mac',
        locator: BinaryLocator(
          runner: fake,
          searchDirs: const ['/opt/homebrew/bin'],
          exists: (p) => p == gh,
        ),
      );

  test('makes a key and adds it for pushing and signing as that account',
      () async {
    final fake = FakeProcessRunner(responses: {
      tokenCmd: const CommandResult(0, 'secret-token', ''),
    });

    final key = await creator(fake).create(const Account(ghUsername: 'octo'));

    expect(key.uploaded, isTrue);
    expect(key.path, '~/.ssh/gitswitcher_octo');
    expect(key.publicKey, startsWith('ssh-ed25519 '));
    expect(File('${home.path}/.ssh/gitswitcher_octo').existsSync(), isTrue);

    final adds = fake.calls.where((c) => c.contains('ssh-key add')).toList();
    expect(adds, hasLength(2));
    expect(adds[0], endsWith('--type authentication'));
    expect(adds[1], endsWith('--type signing'));
    // As this account, whichever one is active in gh.
    expect(fake.environments.last, {'GH_TOKEN': 'secret-token'});
  });

  test('never overwrites an existing key', () async {
    final fake = FakeProcessRunner(responses: {
      tokenCmd: const CommandResult(0, 't', ''),
    });
    final first = await creator(fake).create(const Account(ghUsername: 'octo'));
    final second =
        await creator(fake).create(const Account(ghUsername: 'octo'));

    expect(second.publicKey, first.publicKey);
  });

  test('reports a token without key scopes so the UI can fall back', () async {
    final fake = FakeProcessRunner(
      responses: {tokenCmd: const CommandResult(0, 't', '')},
      fallback: const CommandResult(1, '',
          'HTTP 404: This API operation needs the "admin:public_key" scope.'),
    );

    final key = await creator(fake).create(const Account(ghUsername: 'octo'));

    expect(key.uploaded, isFalse);
    expect(key.problem, contains('cannot add keys'));
    expect(key.publicKey, isNotEmpty);
  });
}
