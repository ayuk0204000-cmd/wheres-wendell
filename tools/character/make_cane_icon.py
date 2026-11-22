"""
Draws the two icons of the cane in one texture.

Top: the inventory icon, in colour: black shaft with white bands, metal grip and tip.
Bottom: the HUD icon (next to the health bar): a white line drawing, as the HUD icons of the base
game, with the white bands filled.

Both are side views with the tip at the left, as the base-game icons of the cane weapon.

usage: make_cane_icon.py <out_png>
`build_character.py` reads WIDTH, HEIGHT, ICON_RECT and HUD_RECT for the rectangles of the atlas.
"""
import sys

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 512, 256
# Rectangles (left, top, right, bottom) in texture pixels. The proportions are those of the base
# icons: 320 x 71 in the inventory, 368 x 93 on the HUD.
ICON_RECT = (0, 0, 512, 114)
HUD_RECT = (0, 130, 480, 251)
SCALE = 4  # drawn larger, then made smaller, for smooth edges

# Inventory icon, measures in texture pixels.
SHAFT_Y = 44
SHAFT_HALF = 5
TIP_LEFT, TIP_RIGHT = 16, 34
GRIP_LEFT, GRIP_RIGHT = 446, 476
BAND = 21
HANDLE_HALF = 8
HANDLE_TOP, HANDLE_BOTTOM = 26, 96

BLACK = (26, 26, 30)
WHITE = (226, 226, 220)
METAL = (150, 156, 164)

# HUD icon, measures in texture pixels from the corner of HUD_RECT.
HUD_LINE = 3
HUD_SHAFT_Y = 42
HUD_SHAFT_HALF = 7
HUD_TIP_LEFT, HUD_TIP_RIGHT = 8, 26
HUD_GRIP_LEFT, HUD_GRIP_RIGHT = 414, 442
HUD_BAND = 20
HUD_HANDLE_LEFT, HUD_HANDLE_RIGHT = 442, 464
HUD_HANDLE_TOP, HUD_HANDLE_BOTTOM = 14, 108


def shade(color, y, centre, half):
    """Makes a round bar: light above the centre line, dark below."""
    t = (y - centre) / half
    factor = 1.0 - 0.38 * t - 0.25 * t * t + 0.12
    return tuple(max(0, min(255, int(c * factor))) for c in color) + (255,)


def bar(draw, left, right, centre, half, color):
    for y in range(int((centre - half) * SCALE), int((centre + half) * SCALE)):
        draw.line([(left * SCALE, y), (right * SCALE - 1, y)], fill=shade(color, y / SCALE, centre, half))


def upright(draw, top, bottom, centre, half, color):
    for x in range(int((centre - half) * SCALE), int((centre + half) * SCALE)):
        draw.line([(x, top * SCALE), (x, bottom * SCALE - 1)], fill=shade(color, x / SCALE, centre, half))


def draw_inventory_icon(image):
    draw = ImageDraw.Draw(image)

    # Shaft: bands from the grip to the tip, black next to the grip.
    x, index = GRIP_LEFT, 0
    while x > TIP_RIGHT:
        left = max(TIP_RIGHT, x - BAND)
        bar(draw, left, x, SHAFT_Y, SHAFT_HALF, BLACK if index % 2 == 0 else WHITE)
        x, index = left, index + 1

    # Metal tip and grip collar, a little thicker than the shaft.
    bar(draw, TIP_LEFT, TIP_RIGHT, SHAFT_Y, SHAFT_HALF - 1, METAL)
    bar(draw, GRIP_LEFT, GRIP_RIGHT, SHAFT_Y, SHAFT_HALF + 2, METAL)

    # Handle: a bar across the end of the shaft, longer on the lower side.
    centre = GRIP_RIGHT + HANDLE_HALF - 2
    upright(draw, HANDLE_TOP, HANDLE_BOTTOM, centre, HANDLE_HALF, METAL)
    for y in (HANDLE_TOP, HANDLE_BOTTOM):
        box = [(centre - HANDLE_HALF) * SCALE, (y - HANDLE_HALF) * SCALE, (centre + HANDLE_HALF) * SCALE - 1, (y + HANDLE_HALF) * SCALE - 1]
        draw.ellipse(box, fill=shade(METAL, y - 2, y, HANDLE_HALF))


def draw_hud_icon(image):
    """White lines on a clear background: 255 in the mask is white, 0 is clear."""
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    ox, oy = HUD_RECT[0], HUD_RECT[1]

    def box(left, top, right, bottom, value):
        draw.rectangle([(ox + left) * SCALE, (oy + top) * SCALE, (ox + right) * SCALE - 1, (oy + bottom) * SCALE - 1], fill=value)

    def frame(left, top, right, bottom):
        box(left, top, right, bottom, 255)
        box(left + HUD_LINE, top + HUD_LINE, right - HUD_LINE, bottom - HUD_LINE, 0)

    top, bottom = HUD_SHAFT_Y - HUD_SHAFT_HALF, HUD_SHAFT_Y + HUD_SHAFT_HALF
    # Shaft: an outline, with each second band filled (the white bands). Clear next to the grip.
    frame(HUD_TIP_RIGHT - HUD_LINE, top, HUD_GRIP_LEFT + HUD_LINE, bottom)
    x, index = HUD_GRIP_LEFT, 0
    while x > HUD_TIP_RIGHT:
        left = max(HUD_TIP_RIGHT, x - HUD_BAND)
        if index % 2 == 1:
            box(left, top, x, bottom, 255)
        x, index = left, index + 1
    # Tip and grip collar: filled. Handle: an outline across the end of the shaft.
    box(HUD_TIP_LEFT, top + 2, HUD_TIP_RIGHT, bottom - 2, 255)
    box(HUD_GRIP_LEFT, top - 3, HUD_GRIP_RIGHT, bottom + 3, 255)
    frame(HUD_HANDLE_LEFT - HUD_LINE, HUD_HANDLE_TOP, HUD_HANDLE_RIGHT, HUD_HANDLE_BOTTOM)

    white = Image.new("RGBA", image.size, (255, 255, 255, 0))
    white.putalpha(mask)
    image.alpha_composite(white)


def main():
    image = Image.new("RGBA", (WIDTH * SCALE, HEIGHT * SCALE), (0, 0, 0, 0))
    draw_inventory_icon(image)
    draw_hud_icon(image)
    image = image.resize((WIDTH, HEIGHT), Image.LANCZOS)
    image.save(sys.argv[1])


if __name__ == "__main__":
    main()
