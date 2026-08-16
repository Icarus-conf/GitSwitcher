# Vendored dependencies

## tray_manager 0.5.3 (patched)

Vendored from pub.dev and wired in through `dependency_overrides` in the root
`pubspec.yaml`.

**Why:** upstream's macOS menu builder
(`macos/tray_manager/Classes/TrayMenu.swift`) reads only `id`, `type`, `label`,
`toolTip`, `checked` and `disabled` from each menu item. It silently drops both
`icon` and `sublabel`, even though the Dart-side `MenuItem` class accepts them.
That makes account avatars impossible and hides the per-account setup hint.

**The patch** is confined to `TrayMenu.swift` and is marked inline with
`// GitSwitcher patch:` comments. It adds two things:

- `icon` is loaded into `menuItem.image`, masked to a 16pt circle with
  `isTemplate = false` — avatars are photographs, and a template image would be
  flattened into a solid silhouette. The mask is drawn through
  `NSImage(size:flipped:drawingHandler:)` so AppKit rasterises at the display's
  scale and the result stays sharp on Retina.
- `sublabel` becomes a second, smaller, dimmed line via `attributedTitle`.

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
