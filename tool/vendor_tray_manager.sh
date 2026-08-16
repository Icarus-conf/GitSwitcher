#!/usr/bin/env bash
#
# Re-vendors tray_manager from pub.dev and re-applies the GitSwitcher patch.
#
# The published package drops `icon` and `sublabel` on macOS menu items, which
# the app needs for avatars and per-account hints. Rather than hand-editing the
# vendored copy after every upgrade, this script rebuilds it from upstream and
# applies third_party/tray_manager.patch.
#
# It fails loudly if the patch does not apply, which is the point: a silent
# failure would ship a build with no avatars and no explanation.
#
# Usage: tool/vendor_tray_manager.sh [version]     (default: current version)

set -euo pipefail

VERSION="${1:-0.5.3}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/third_party/tray_manager"
PATCH="$ROOT/third_party/tray_manager.patch"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Downloading tray_manager $VERSION from pub.dev"
curl -fsSL "https://pub.dev/packages/tray_manager/versions/$VERSION.tar.gz" \
  | tar xz -C "$WORK"

if [ ! -f "$WORK/macos/tray_manager/Classes/TrayMenu.swift" ]; then
  echo "error: unexpected package layout — TrayMenu.swift not found." >&2
  echo "       Upstream may have restructured; re-make the patch by hand." >&2
  exit 1
fi

echo "==> Applying $(basename "$PATCH")"
if ! patch -p1 --directory="$WORK" --forward < "$PATCH"; then
  cat >&2 <<'MSG'

error: the patch did not apply cleanly.

Upstream changed the code the patch touches. Fix it once, by hand:

  1. Open the rejected hunks (*.rej) printed above.
  2. Re-apply those changes to the new TrayMenu.swift, keeping the
     "// GitSwitcher patch:" markers.
  3. Regenerate the patch:
       diff -u --label a/macos/tray_manager/Classes/TrayMenu.swift \
               --label b/macos/tray_manager/Classes/TrayMenu.swift \
               <clean>/macos/tray_manager/Classes/TrayMenu.swift \
               third_party/tray_manager/macos/tray_manager/Classes/TrayMenu.swift \
         > third_party/tray_manager.patch
MSG
  exit 1
fi

# The example app is a Flutter project of its own; vendoring it would make the
# analyzer walk a second package.
rm -rf "$WORK/example"

echo "==> Replacing $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$WORK/." "$DEST/"

echo "==> Verifying the patch survived"
if ! grep -q "GitSwitcher patch:" "$DEST/macos/tray_manager/Classes/TrayMenu.swift"; then
  echo "error: patch markers missing after copy." >&2
  exit 1
fi

echo
echo "Done. tray_manager $VERSION vendored and patched."
echo "Next: update the version in third_party/README.md, then run"
echo "  flutter pub get && flutter test && flutter build macos --release"
