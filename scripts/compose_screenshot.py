#!/usr/bin/env python3
"""Composite the real popover capture onto a 2880x1800 App Store hero image."""
import sys
from PIL import Image, ImageDraw, ImageFont

POPOVER = sys.argv[1] if len(sys.argv) > 1 else "/tmp/popover.png"
OUT = sys.argv[2] if len(sys.argv) > 2 else "fastlane/screenshots/en-US/01-main.png"
HEADLINE = "Never overcharge your Mac."
SUBHEAD = "Alerts at the exact battery % you choose."

W, H = 2880, 1800
BG = (18, 18, 20)  # very dark gray to match popover

canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)

# Try a couple of system font paths in priority order.
def load_font(size, weight="Bold"):
    candidates = [
        f"/System/Library/Fonts/SF-Pro-Display-{weight}.otf",
        f"/System/Library/Fonts/SFNS{'Display-Bold' if weight=='Bold' else 'Display'}.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for p in candidates:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()

font_h = load_font(140, "Bold")
font_s = load_font(60, "Regular")

# Headline centered horizontally near top.
def draw_centered(text, font, y, fill):
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    draw.text(((W - tw) / 2, y), text, font=font, fill=fill)

draw_centered(HEADLINE, font_h, 120, (255, 255, 255))
draw_centered(SUBHEAD, font_s, 300, (180, 180, 185))

# Popover centered below text.
pop = Image.open(POPOVER).convert("RGBA")
# Scale popover to dominate the lower portion of the canvas.
target_h = 1380
ratio = target_h / pop.height
target_w = int(pop.width * ratio)
pop = pop.resize((target_w, target_h), Image.LANCZOS)

px = (W - target_w) // 2
py = 410
canvas.paste(pop, (px, py), pop)

canvas.save(OUT, "PNG", optimize=True)
print(f"wrote {OUT} ({W}x{H})")
