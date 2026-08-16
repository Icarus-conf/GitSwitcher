"""Generates the macOS app icon set into macos/Runner/Assets.xcassets.

Two arrows circling each other: a swap, not a transfer. The two dots are the
identities being exchanged, in the same blue and purple the app uses for
accounts — the left one solid because one identity is always the active one.

Each size is drawn parametrically rather than downscaled from a single master.
A stroke that reads at 1024px is sub-pixel at 16px, so the small renditions get
proportionally heavier strokes and drop the dots, which would otherwise merge
into noise.
"""

import math
import os

from PIL import Image, ImageDraw

OUT = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
SIZES = [16, 32, 64, 128, 256, 512, 1024]
SUPERSAMPLE = 4

INK_TOP = (22, 27, 34)      # GitHub #161B22
INK_BOT = (8, 11, 15)
BLUE = (88, 166, 255)
PURPLE = (191, 90, 242)


def render(size: int) -> Image.Image:
    small = size <= 32
    s = size * SUPERSAMPLE

    # Tiny icons need to fill more of the tile and carry heavier strokes.
    inset = s * (0.06 if small else 0.088)
    radius = s * (0.20 if small else 0.225)
    stroke = s * (0.085 if small else 0.053)
    ring = s * 0.205

    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    grad = Image.new("RGBA", (s, s))
    g = ImageDraw.Draw(grad)
    for y in range(s):
        t = y / s
        g.line(
            [(0, y), (s, y)],
            fill=tuple(
                int(a + (b - a) * t) for a, b in zip(INK_TOP, INK_BOT)
            ) + (255,),
        )
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, s - inset, s - inset], radius=radius, fill=255
    )
    img.paste(grad, (0, 0), mask)

    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [inset, inset, s - inset, s - inset],
        radius=radius,
        outline=(255, 255, 255, 34),
        width=max(1, int(s * 0.003)),
    )

    cx = cy = s / 2
    box = [cx - ring, cy - ring, cx + ring, cy + ring]
    d.arc(box, 200, 340, fill=BLUE, width=int(stroke))
    d.arc(box, 20, 160, fill=PURPLE, width=int(stroke))

    def head(angle_deg: float, colour, length: float):
        a = math.radians(angle_deg)
        px, py = cx + ring * math.cos(a), cy + ring * math.sin(a)
        t = a + math.pi / 2
        tip = (px + length * math.cos(t), py + length * math.sin(t))
        n = t + math.pi / 2
        w = length * 0.66
        d.polygon(
            [
                tip,
                (px + w * math.cos(n), py + w * math.sin(n)),
                (px - w * math.cos(n), py - w * math.sin(n)),
            ],
            fill=colour,
        )

    head_len = stroke * (1.5 if small else 1.45)
    head(340, BLUE, head_len)
    head(160, PURPLE, head_len)

    # The identities being swapped. Omitted on tiny renditions, where they
    # would blur into the arcs instead of reading as two things.
    if not small:
        r = s * 0.033
        gap = s * 0.082
        d.ellipse([cx - gap - r, cy - r, cx - gap + r, cy + r], fill=BLUE)
        d.ellipse(
            [cx + gap - r, cy - r, cx + gap + r, cy + r], fill=(*PURPLE, 170)
        )

    return img.resize((size, size), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
for size in SIZES:
    render(size).save(f"{OUT}/app_icon_{size}.png")
    print(f"  app_icon_{size}.png")
print("app icon set written")
