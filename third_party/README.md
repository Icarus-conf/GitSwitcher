# Vendored dependencies

## tray_manager 0.5.3 (patched)

Vendored from pub.dev and wired in through `dependency_overrides` in the root
`pubspec.yaml`.

**Why:** upstream's macOS menu builder
(`macos/tray_manager/Classes/TrayMenu.swift`) ignores each menu item's `icon`,
even though the Dart-side `MenuItem` accepts it. That makes account avatars
impossible.

**The patch** is confined to `TrayMenu.swift` and is marked inline with
`// GitSwitcher patch:` comments. It loads `icon`, masks it to a circle, and
draws it at the start of the item's title as a text attachment.

It goes in the title rather than `menuItem.image` on purpose: macOS 27 does not
draw `NSMenuItem.image` in a status-item menu at all — not even system symbols —
so an avatar there is silently invisible.

Nothing else is modified.

## Upgrading

Do not hand-edit the vendored copy. Run:

```bash
tool/vendor_tray_manager.sh 0.6.0
```

It downloads that version from pub.dev, applies `tray_manager.patch`, and
replaces this directory. If upstream has changed the code the patch touches, it
stops with a non-zero exit and tells you which hunks were rejected — a silent
failure would ship a build with no avatars and no explanation.

Afterwards, update the version in this file's heading and run:

```bash
flutter pub get && flutter test && flutter build macos --release
```

`test/vendored_patch_test.dart` asserts the patch is still present, so a
re-vendor that loses it fails the suite rather than shipping.
