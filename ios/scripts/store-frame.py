#!/usr/bin/env python3
"""App-Store-Bild: Überschrift + Unterzeile über einem gerahmten iPhone-Screenshot (1320 × 2868, 6,9").
Aufruf: store-frame.py <roh.png> <ziel.png> "<Überschrift, \\n für Umbruch>" "<Unterzeile>" [dark]"""
import sys
from PIL import Image, ImageDraw, ImageFont

W, H = 1320, 2868
raw, out, title, sub = sys.argv[1:5]
dark = len(sys.argv) > 5 and sys.argv[5] == "dark"
bg, ink, ink2, rim = ((20, 20, 19), (245, 243, 238), (170, 168, 162), (60, 60, 58)) if dark \
    else ((244, 242, 236), (17, 17, 17), (84, 84, 80), (17, 17, 17))

def font(path, style, size):
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(style)
    return f

canvas = Image.new("RGB", (W, H), bg)
d = ImageDraw.Draw(canvas)
x, y = 96, 170
head = font("/System/Library/Fonts/SFNSRounded.ttf", "Heavy", 124)
for line in title.split("\\n"):
    d.text((x, y), line, font=head, fill=ink)
    y += 138
y += 18
d.text((x, y), sub, font=font("/System/Library/Fonts/SFNS.ttf", "Regular", 48), fill=ink2)

# Telefon: Screenshot mit runden Ecken und dunklem Rand, unten angeschnitten.
shot = Image.open(raw).convert("RGB")
pw = 1066
ph = round(shot.height * pw / shot.width)
shot = shot.resize((pw, ph), Image.LANCZOS)
top, border, radius = y + 150, 12, 150
px = (W - pw) // 2
frame = Image.new("RGB", (pw + 2 * border, ph + 2 * border), rim)
fmask = Image.new("L", frame.size, 0)
ImageDraw.Draw(fmask).rounded_rectangle((0, 0, *frame.size), radius=radius + border, fill=255)
canvas.paste(frame, (px - border, top - border), fmask)
smask = Image.new("L", shot.size, 0)
ImageDraw.Draw(smask).rounded_rectangle((0, 0, *shot.size), radius=radius, fill=255)
canvas.paste(shot, (px, top), smask)
canvas.save(out, optimize=True)
