"""Draws the app icons and the link-preview image into img/. Run: python tools/make_icons.py"""
from PIL import Image, ImageDraw, ImageFont

INK, GOLD, RED, BLUE, PAPER = "#131820", "#e6b440", "#d6453d", "#2f6fdb", "#e8ecf2"
IMPACT = "C:/Windows/Fonts/impact.ttf"
BOLD = "C:/Windows/Fonts/arialbd.ttf"


def icon(size, pad=0.0, radius=0.18):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if radius:
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius), fill=INK)
    else:
        d.rectangle([0, 0, size, size], fill=INK)
    inner = size * (1 - 2 * pad)
    f = ImageFont.truetype(IMPACT, int(inner * 0.72))
    d.text((size / 2, size / 2 - inner * 0.04), "W", font=f, fill=GOLD, anchor="mm")
    # the two team colors as a score bar
    bw, bh, y = inner * 0.56, max(2, inner * 0.06), size / 2 + inner * 0.33
    x0 = size / 2 - bw / 2
    d.rectangle([x0, y, x0 + bw * 0.55, y + bh], fill=RED)
    d.rectangle([x0 + bw * 0.55, y, x0 + bw, y + bh], fill=BLUE)
    return im


icon(192).save("img/icon-192.png")
icon(512).save("img/icon-512.png")
icon(512, pad=0.12, radius=0).save("img/icon-maskable-512.png")
icon(180, radius=0).convert("RGB").save("img/apple-touch-icon.png")

# 1200x630 link preview
im = Image.new("RGB", (1200, 630), INK)
d = ImageDraw.Draw(im)
d.text((80, 90), "SEASON 7  ·  NOW PLAYING", font=ImageFont.truetype(BOLD, 30), fill="#8a93a3")
d.text((76, 140), "WORKOUT GANG", font=ImageFont.truetype(IMPACT, 150), fill=PAPER)
d.text((80, 330), "Log your days. Win weeks for your team.", font=ImageFont.truetype(BOLD, 40), fill=GOLD)
d.text((80, 420), "RED", font=ImageFont.truetype(BOLD, 26), fill=RED)
d.text((80, 450), "519", font=ImageFont.truetype(IMPACT, 90), fill=PAPER)
d.text((330, 420), "BLUE", font=ImageFont.truetype(BOLD, 26), fill=BLUE)
d.text((330, 450), "464", font=ImageFont.truetype(IMPACT, 90), fill=PAPER)
d.rounded_rectangle([80, 565, 80 + 1040 * 0.53, 585], radius=10, fill=RED)
d.rounded_rectangle([80 + 1040 * 0.53, 565, 1120, 585], radius=10, fill=BLUE)
im.save("img/preview.png", optimize=True)
