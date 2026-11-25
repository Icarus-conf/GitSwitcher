import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/binary_locator.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/platform/process_runner.dart';

import '../support/fake_process_runner.dart';

void main() {
  test('returns the first search directory that contains the binary', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(),
      searchDirs: const ['/opt/homebrew/bin', '/usr/local/bin'],
      exists: (path) => path == '/usr/local/bin/gh',
    );

    expect(await locator.locate('gh'), '/usr/local/bin/gh');
  });

  test('prefers an earlier search directory over a later one', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(),
      searchDirs: const ['/opt/homebrew/bin', '/usr/local/bin'],
      exists: (_) => true,
    );

    expect(await locator.locate('gh'), '/opt/homebrew/bin/gh');
  });

  test('falls back to a login shell when no search directory matches', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/bin/zsh -lc which gh': const CommandResult(0, '/custom/bin/gh', ''),
      },
    );
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const ['/opt/homebrew/bin'],
      exists: (path) => path == '/custom/bin/gh',
    );

    expect(await locator.locate('gh'), '/custom/bin/gh');
    expect(runner.calls, ['/bin/zsh -lc which gh']);
  });

  test('throws when the binary is nowhere to be found', () async {
    final locator = BinaryLocator(
      runner: FakeProcessRunner(fallback: const CommandResult(1, '', '')),
      searchDirs: const ['/opt/homebrew/bin'],
      exists: (_) => false,
    );

    expect(
      () => locator.locate('gh'),
      throwsA(isA<BinaryNotFoundException>()),
    );
  });

  test('caches a resolved path instead of probing twice', () async {
    final runner = FakeProcessRunner(
      responses: {
        '/bin/zsh -lc which gh': const CommandResult(0, '/custom/bin/gh', ''),
      },
    );
    final locator = BinaryLocator(
      runner: runner,
      searchDirs: const [],
      exists: (path) => path == '/custom/bin/gh',
    );

    await locator.locate('gh');
    await locator.locate('gh');

    expect(runner.calls.length, 1);
  });

  test('the not-found message names the missing binary', () {
    expect(BinaryNotFoundException('gh').toString(), contains('gh'));
  });

  group('on Windows', () {
    setUp(() => Host.current = Host.windows);
    tearDown(() => Host.current = Host.macos);

    test('looks for name.exe in each folder', () async {
      final locator = BinaryLocator(
        runner: FakeProcessRunner(),
        searchDirs: const [r'C:\Program Files\GitHub CLI'],
        exists: (path) => path == r'C:\Program Files\GitHub CLI\gh.exe',
      );

      expect(await locator.locate('gh'), r'C:\Program Files\GitHub CLI\gh.exe');
    });

    test('falls back to the first line where.exe prints', () async {
      final runner = FakeProcessRunner(responses: {
        'where.exe ssh': const CommandResult(
            0, 'C:\\Tools\\ssh.exe\r\nC:\\Other\\ssh.exe', ''),
      });
      final locator = BinaryLocator(
        runner: runner,
        searchDirs: const [],
        exists: (path) => path == r'C:\Tools\ssh.exe',
      );

      expect(await locator.locate('ssh'), r'C:\Tools\ssh.exe');
    });
  });

  test('config paths use forward slashes on Windows only', () {
    expect(Host.windows.configPath(r'C:\Users\me\.ssh\k'), 'C:/Users/me/.ssh/k');
    expect(Host.macos.configPath('/Users/me/.ssh/k'), '/Users/me/.ssh/k');
  });
}
