#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用赛璐璐 3/4 Hero 合成应用图标（legacy + Android adaptive）。"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERO = os.path.join(ROOT, "assets", "keyart", "hero.png")
OUT = os.path.join(ROOT, "assets", "icons")
SIZE = 1024
random.seed(7)


def gradient_bg() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    px = img.load()
    top = (27, 36, 80)
    mid = (76, 107, 214)
    bottom = (243, 198, 217)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        if t < 0.55:
            a, b, k = top, mid, t / 0.55
        else:
            a, b, k = mid, bottom, (t - 0.55) / 0.45
        col = tuple(int(a[i] * (1 - k) + b[i] * k) for i in range(3))
        for x in range(SIZE):
            px[x, y] = (*col, 255)
    # 星云光斑
    neb = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    nd = ImageDraw.Draw(neb)
    for cx, cy, r, col in [
        (230, 260, 360, (143, 232, 216, 70)),
        (820, 420, 330, (255, 180, 218, 66)),
        (520, 760, 300, (185, 166, 255, 58)),
    ]:
        for i in range(8, 0, -1):
            rr = r * i / 8
            nd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(col[0], col[1], col[2], col[3] // 8))
    neb = neb.filter(ImageFilter.GaussianBlur(38))
    img = Image.alpha_composite(img, neb)
    # 星星
    d = ImageDraw.Draw(img)
    for _ in range(120):
        x, y = random.randrange(SIZE), random.randrange(SIZE)
        r = random.choice([1, 1, 1, 2, 2, 3])
        a = random.randint(120, 235)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 250, 235, a))
        if r == 3:
            d.line((x - 9, y, x + 9, y), fill=(255, 250, 235, 90), width=1)
            d.line((x, y - 9, x, y + 9), fill=(255, 250, 235, 90), width=1)
    return img


def place_hero(bg: Image.Image, hero_size: int, glow: int) -> Image.Image:
    hero = Image.open(HERO).convert("RGBA")
    hero.thumbnail((hero_size, hero_size), Image.LANCZOS)
    canvas = bg.copy()
    cx = (SIZE - hero.width) // 2
    cy = (SIZE - hero.height) // 2 - int(SIZE * 0.02)
    # 背后柔光
    mask = hero.getchannel("A").filter(ImageFilter.GaussianBlur(glow))
    glow_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow_img.paste((255, 240, 255, 120), (cx, cy), mask)
    canvas = Image.alpha_composite(canvas, glow_img)
    canvas.alpha_composite(hero, (cx, cy))
    return canvas


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = gradient_bg()
    legacy = place_hero(bg, 790, 46)
    legacy.convert("RGB").save(os.path.join(OUT, "icon_1024.png"))
    fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    fg = place_hero(fg, 640, 30)
    fg.save(os.path.join(OUT, "icon_fg_1024.png"))
    bg.save(os.path.join(OUT, "icon_bg_1024.png"))
    print("wrote icons", SIZE)


if __name__ == "__main__":
    main()
