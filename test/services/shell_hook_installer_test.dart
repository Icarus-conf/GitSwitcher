import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/services/shell_hook_installer.dart';

void main() {
  late Directory tempDir;
  late File zshrc;
  late File stateFile;
  late ShellHookInstaller installer;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('gitswitcher_hook_test');
    zshrc = File('${tempDir.path}/.zshrc');
    stateFile = File('${tempDir.path}/state/cwd');
    installer = ShellHookInstaller(zshrc: zshrc, stateFile: stateFile);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const userContent = 'export EDITOR=vim\nalias ll="ls -la"\n';

  test('reports not installed for a missing file', () async {
    expect(await installer.isInstalled(), isFalse);
  });

  test('installs the hook and reports it', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.install();

    expect(await installer.isInstalled(), isTrue);
    expect(zshrc.readAsStringSync(), contains('add-zsh-hook chpwd'));
    expect(zshrc.readAsStringSync(), contains(stateFile.path));
  });

  test('preserves the user content above the block', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.install();

    expect(zshrc.readAsStringSync(), startsWith(userContent));
  });

  test('creates the file when there is no .zshrc', () async {
    await installer.install();

    expect(zshrc.existsSync(), isTrue);
    expect(await installer.isInstalled(), isTrue);
  });

  test('backs up before modifying an existing file', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.install();

    final backups = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.gitswitcher-backup-'));
    expect(backups, hasLength(1));
    expect(backups.first.readAsStringSync(), userContent);
  });

  test('installing twice does not duplicate the block', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.install();
    await installer.install();

    final contents = zshrc.readAsStringSync();
    expect(
      ShellHookInstaller.block.beginMarker.allMatches(contents),
      hasLength(1),
    );
  });

  test('uninstall restores the original file exactly', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.install();
    await installer.uninstall();

    expect(zshrc.readAsStringSync(), userContent);
    expect(await installer.isInstalled(), isFalse);
  });

  test('repeated install and uninstall does not drift', () async {
    zshrc.writeAsStringSync(userContent);

    for (var i = 0; i < 3; i++) {
      await installer.install();
      await installer.uninstall();
    }

    expect(zshrc.readAsStringSync(), userContent);
  });

  test('uninstall is harmless when nothing is installed', () async {
    zshrc.writeAsStringSync(userContent);

    await installer.uninstall();

    expect(zshrc.readAsStringSync(), userContent);
  });

  test('refuses to write when the markers are damaged', () async {
    zshrc.writeAsStringSync(
      '$userContent${ShellHookInstaller.block.beginMarker}\nbroken\n',
    );

    expect(installer.install, throwsA(isA<FormatException>()));
  });

  test('the hook redirects stderr so a broken state path cannot spam the shell',
      () {
    expect(installer.hookBody, contains('2>/dev/null'));
  });
}
