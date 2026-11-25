import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/platform/host.dart';
import 'package:git_switcher/src/services/update_checker.dart';

void main() {
  Map<String, dynamic> release(String tag) => {
        'tag_name': tag,
        'html_url': 'https://github.com/x/releases/$tag',
        'assets': [
          {'name': 'GitSwitcher-$tag-macos.zip', 'browser_download_url': 'mac'},
          {'name': 'GitSwitcher-$tag-windows.zip', 'browser_download_url': 'win'},
        ],
      };

  UpdateChecker checker(String current, String latest) => UpdateChecker(
        currentVersion: current,
        fetch: (_) async => release(latest),
      );

  test('offers a newer release with this system\'s download', () async {
    final update = await checker('0.2.0', 'v0.10.0').check();
    expect(update?.version, '0.10.0');
    expect(update?.downloadUrl, 'mac');
  });

  test('picks the Windows zip on Windows', () async {
    Host.current = Host.windows;
    addTearDown(() => Host.current = Host.macos);
    expect((await checker('0.2.0', 'v0.3.0').check())?.downloadUrl, 'win');
  });

  test('stays quiet when up to date or ahead', () async {
    expect(await checker('0.3.0', 'v0.3.0').check(), isNull);
    expect(await checker('0.4.0', 'v0.3.0').check(), isNull);
  });

  test('a build with no version never nags', () async {
    expect(await checker('', 'v9.0.0').check(), isNull);
  });

  test('offline is not an error', () async {
    final offline = UpdateChecker(
      currentVersion: '0.1.0',
      fetch: (_) async => throw Exception('no network'),
    );
    expect(await offline.check(), isNull);
  });
}
