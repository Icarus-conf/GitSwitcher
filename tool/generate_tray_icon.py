"""Generates assets/tray_icon.png — a black-on-alpha macOS template image.

The glyph is two opposing horizontal arrows, reading as "switch".
Rendered at 4x then downsampled so the edges are smooth.
"""

from PIL import Image, ImageDraw

SIZE = 36  # 2x of the 18pt menu bar icon size
SCALE = 4
W = SIZE * SCALE

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

bar = 3 * SCALE          # shaft thickness
head = 7 * SCALE         # arrowhead half-height
left = 5 * SCALE
right = W - 5 * SCALE
top_y = 12 * SCALE       # upper arrow centre
bot_y = 24 * SCALE       # lower arrow centre

# Upper arrow: shaft pointing right, head on the right.
d.rectangle([left, top_y - bar // 2, right - head, top_y + bar // 2], fill=(0, 0, 0, 255))
d.polygon(
    [(right - head, top_y - head), (right, top_y), (right - head, top_y + head)],
    fill=(0, 0, 0, 255),
)

# Lower arrow: shaft pointing left, head on the left.
d.rectangle([left + head, bot_y - bar // 2, right, bot_y + bar // 2], fill=(0, 0, 0, 255))
d.polygon(
    [(left + head, bot_y - head), (left, bot_y), (left + head, bot_y + head)],
    fill=(0, 0, 0, 255),
)

img.resize((SIZE, SIZE), Image.LANCZOS).save("assets/tray_icon.png")
print("wrote assets/tray_icon.png")
