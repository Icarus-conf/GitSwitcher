import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the patch applied to the vendored tray_manager.
///
/// Upstream drops `icon` on macOS menu items. Losing the patch —
/// by upgrading the package, or re-vendoring without running
/// `tool/vendor_tray_manager.sh` — would remove account avatars with no error
/// anywhere: the app would build, run, and just quietly look wrong. These tests
/// turn that into a failing build instead.
void main() {
  final trayMenu = File(
    'third_party/tray_manager/macos/tray_manager/Classes/TrayMenu.swift',
  );
  final patch = File('third_party/tray_manager.patch');

  test('the vendored plugin is present', () {
    expect(
      trayMenu.existsSync(),
      isTrue,
      reason: 'run tool/vendor_tray_manager.sh',
    );
  });

  test('the patch file is kept alongside it', () {
    expect(
      patch.existsSync(),
      isTrue,
      reason: 'third_party/tray_manager.patch is how the patch is re-applied',
    );
  });

  group('the patch is still applied', () {
    late String source;

    setUp(() => source = trayMenu.readAsStringSync());

    test('is marked so it is not mistaken for upstream code', () {
      expect(source, contains('// GitSwitcher patch:'));
    });

    test('renders the item icon, which upstream ignores', () {
      expect(source, contains(r'itemDict["icon"]'));
      expect(source, contains('circularImage'));
    });

    test('draws the avatar inside the title, not in the image slot', () {
      // macOS 27 does not draw NSMenuItem.image in a status-item menu at all,
      // so an avatar set there is silently invisible.
      expect(source, contains('NSTextAttachment'));
      expect(source, contains('menuItem.attributedTitle'));
      expect(source, isNot(contains('menuItem.image =')));
    });

    test('avatars are not template images', () {
      // A template image is flattened to a silhouette, which would turn every
      // avatar into the same grey blob.
      expect(source, contains('isTemplate = false'));
    });
  });

  test('the re-vendoring script is executable', () {
    final script = File('tool/vendor_tray_manager.sh');
    expect(script.existsSync(), isTrue);
    expect(
      script.statSync().mode & 0x40 != 0,
      isTrue,
      reason: 'chmod +x tool/vendor_tray_manager.sh',
    );
  });
}
