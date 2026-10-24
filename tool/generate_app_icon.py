"""Generates the macOS app icon set into macos/Runner/Assets.xcassets.

Janus: one head, two faces looking opposite ways — one person, a work identity
and a personal one. Drawn as SVG and rasterised with Quick Look (macOS only).

Sizes 16 and 32 use a simplified variant: the gold ring turns to noise and a
thin seam vanishes, leaving a plain head, so the small variant drops the ring
and widens the seam that makes it read as two faces.
"""

import os
import subprocess
import tempfile

from PIL import Image, ImageDraw

OUT = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
SIZES = [16, 32, 64, 128, 256, 512, 1024]
S = 1024

# Left-facing profile; the right face is its mirror across x = 512.
FACE = ("M 512 262 C 440 262 382 292 360 352 C 348 388 350 410 346 432 "
        "C 342 450 330 462 318 486 L 294 534 C 290 544 300 550 316 552 "
        "C 322 558 320 568 314 574 C 310 582 316 588 322 592 C 316 600 318 610 326 614 "
        "C 328 642 334 666 352 682 C 380 706 420 708 438 714 L 446 792 L 512 792 Z")
EYE = "M 360 450 Q 378 438 396 450 Q 378 460 360 450 Z"


def mirror(path):
    out, is_x = [], True
    for tok in path.split():
        try:
            v = float(tok)
        except ValueError:
            out.append(tok)
            is_x = True
            continue
        out.append(f"{S - v:g}" if is_x else f"{v:g}")
        is_x = not is_x
    return " ".join(out)


def svg(small):
    ring = "" if small else (
        '<circle cx="512" cy="530" r="356" fill="none" stroke="#f2c66d" '
        'stroke-opacity=".45" stroke-width="6"/>')
    seam = 28 if small else 10
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#3b4fe6"/><stop offset="1" stop-color="#141c6e"/></linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity=".18"/><stop offset=".45" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <linearGradient id="marble" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fbf6ee"/><stop offset="1" stop-color="#d8cab6"/></linearGradient>
  <filter id="drop" x="-40%" y="-40%" width="180%" height="180%">
    <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#000" flood-opacity=".38"/></filter>
</defs>
<rect width="{S}" height="{S}" fill="url(#bg)"/>
{ring}
<g filter="url(#drop)">
  <path d="{FACE}" fill="url(#marble)"/>
  <path d="{mirror(FACE)}" fill="url(#marble)"/>
  <rect x="396" y="792" width="232" height="40" rx="12" fill="#cbb99f"/>
</g>
<line x1="512" y1="270" x2="512" y2="790" stroke="#2236b8" stroke-width="{seam}"/>
<path d="{EYE}" fill="#1e2a8a"/><path d="{mirror(EYE)}" fill="#1e2a8a"/>
<rect width="{S}" height="{S}" fill="url(#sheen)"/>
</svg>"""


def rasterise(svg_text, workdir, name):
    src = os.path.join(workdir, f"{name}.svg")
    with open(src, "w") as f:
        f.write(svg_text)
    subprocess.run(["qlmanage", "-t", "-s", str(S), "-o", workdir, src],
                   check=True, capture_output=True)
    return Image.open(f"{src}.png").convert("RGBA").resize((S, S), Image.LANCZOS)


def tile(src):
    """Masks a full-bleed render into the macOS icon shape, with a hairline edge."""
    big = 4 * S
    inset, radius = big * 0.088, big * 0.225
    box = [inset, inset, big - inset, big - inset]
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(src, (0, 0), mask.resize((S, S), Image.LANCZOS))
    edge = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 70), width=10)
    out.alpha_composite(edge.resize((S, S), Image.LANCZOS))
    return out


with tempfile.TemporaryDirectory() as tmp:
    full = tile(rasterise(svg(small=False), tmp, "full"))
    small = tile(rasterise(svg(small=True), tmp, "small"))

os.makedirs(OUT, exist_ok=True)
for size in SIZES:
    (small if size <= 32 else full).resize((size, size), Image.LANCZOS).save(f"{OUT}/app_icon_{size}.png")
    print(f"  app_icon_{size}.png")
print("app icon set written")
