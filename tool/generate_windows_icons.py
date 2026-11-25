"""Builds the Windows .ico files from the macOS app icon PNGs.

- windows/runner/resources/app_icon.ico: the .exe, taskbar and Alt-Tab icon.
- assets/tray_icon.ico: the tray icon. Unlike macOS, the Windows tray shows a
  colour icon, so it is the app icon at small sizes, not the menu bar glyph.

Each entry is the PNG itself, which .ico has allowed since Windows Vista, so
no image library is needed. Re-run after changing the macOS icon:

    python3 tool/generate_windows_icons.py
"""

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"


def build_ico(sizes, out):
    pngs = [(ICONSET / f"app_icon_{s}.png").read_bytes() for s in sizes]
    header = struct.pack("<HHH", 0, 1, len(pngs))
    offset = 6 + 16 * len(pngs)
    entries, data = b"", b""
    for size, png in zip(sizes, pngs):
        dim = 0 if size >= 256 else size  # 0 means 256 in an .ico entry
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(png), offset)
        offset += len(png)
        data += png
    out.write_bytes(header + entries + data)
    print(f"wrote {out.relative_to(ROOT)} ({', '.join(map(str, sizes))})")


build_ico([16, 32, 64, 128, 256], ROOT / "windows/runner/resources/app_icon.ico")
build_ico([16, 32, 64], ROOT / "assets/tray_icon.ico")
