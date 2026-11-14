#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用豆包出图生成 3D 像素块启动图标三件套（参考《像素飞机大战》）。

输出：
  assets/icons/icon_1024.png     桌面/商店图标（保留背景）
  assets/icons/icon_fg_1024.png  安卓自适应图标前景（透明底，机体居中 70%）
  assets/icons/icon_bg_1024.png  安卓自适应图标背景（暗红底 + 金色放射光 + 奶油像素云）

用法：python tools/gen_icon_pixel.py [--raw build/raw_art2/app_icon.jpg]
"""
import argparse
import math
import os
from collections import deque

from PIL import Image, ImageDraw, ImageFilter

GOLD = (255, 198, 55)
CREAM = (255, 243, 214)
DEEP = (26, 6, 12)
TAU = math.tau

# 与 tools/pixel_neon.py 保持同一套 3D 像素块色板
PALETTE = [
    (24, 6, 10), (42, 10, 16), (58, 16, 22), (78, 24, 28),
    (120, 32, 32), (168, 44, 40), (216, 69, 60), (244, 116, 87),
    (224, 154, 30), (255, 198, 55), (255, 230, 150),
    (255, 243, 214), (232, 220, 200),
    (46, 155, 69), (79, 203, 94), (160, 235, 150),
    (47, 184, 201), (95, 224, 232),
    (61, 107, 224), (123, 91, 214),
]


def quantize(img: Image.Image) -> Image.Image:
    pal = Image.new("P", (1, 1))
    flat = []
    for c in PALETTE:
        flat.extend(c)
    flat.extend([0, 0, 0] * (256 - len(PALETTE)))
    pal.putpalette(flat)
    return img.convert("RGB").quantize(palette=pal, dither=Image.NONE).convert("RGB")


def flood_bg(img: Image.Image, tol: int = 40) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    q = deque()

    def is_bg(x: int, y: int) -> bool:
        r, g, b, _ = px[x, y]
        return max(r, g, b) <= tol

    for x in range(w):
        for y in (0, h - 1):
            if not seen[y * w + x] and is_bg(x, y):
                seen[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not seen[y * w + x] and is_bg(x, y):
                seen[y * w + x] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and is_bg(nx, ny):
                seen[ny * w + nx] = 1
                q.append((nx, ny))
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def make_bg(size: int = 1024) -> Image.Image:
    """程序化背景：暗红底 + 金色放射光 + 奶油像素云 + 暗角。"""
    img = Image.new("RGB", (size, size), DEEP)
    d = ImageDraw.Draw(img, "RGBA")
    cx = cy = size // 2
    # 金色放射光（参考图标里的爆炸光线）
    rays = 18
    for i in range(rays):
        a0 = TAU * i / rays
        a1 = a0 + TAU / rays * 0.42
        r = size * 0.78
        pts = [(cx, cy), (cx + math.cos(a0) * r, cy + math.sin(a0) * r),
               (cx + math.cos(a1) * r, cy + math.sin(a1) * r)]
        d.polygon(pts, fill=(GOLD[0], GOLD[1], GOLD[2], 26))
    # 中心暖光
    for i in range(16, 0, -1):
        rr = int(size * 0.46 * i / 16.0)
        a = int(4 + 8 * (1.0 - i / 16.0))
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr],
                  fill=(GOLD[0], GOLD[1], GOLD[2], a))
    # 四角像素星点（奶油色，避免灰云块）
    for (px, py, s) in [(0.14, 0.16, 0.012), (0.86, 0.12, 0.010), (0.10, 0.84, 0.009),
                        (0.90, 0.86, 0.013), (0.72, 0.24, 0.008), (0.26, 0.72, 0.008)]:
        sx, sy, ss = int(px * size), int(py * size), int(s * size)
        d.rectangle([sx - ss, sy - ss, sx + ss, sy + ss],
                    fill=(CREAM[0], CREAM[1], CREAM[2], 150))
    # 四角暗角
    vig = Image.new("L", (size, size), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-size * 0.28, -size * 0.28, size * 1.28, size * 1.28], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(size * 0.10))
    dark = Image.new("RGB", (size, size), (16, 4, 8))
    return Image.composite(img, dark, vig)


def make_fg(sprite_path: str, size: int = 1024) -> Image.Image:
    """前景直接用游戏内自机精灵（alpha 干净），放大后加金色外发光。"""
    sprite = Image.open(sprite_path).convert("RGBA")
    inner = int(size * 0.70)
    ship = sprite.resize((inner, inner), Image.NEAREST)
    # 外发光
    glow_a = ship.split()[3].filter(ImageFilter.GaussianBlur(inner * 0.035))
    glow = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    glow.putalpha(glow_a.point(lambda v: int(v * 0.75)))
    gold = Image.new("RGBA", (inner, inner), GOLD + (255,))
    glow = Image.composite(gold, Image.new("RGBA", (inner, inner), (0, 0, 0, 0)), glow.split()[3])
    composed = Image.alpha_composite(glow, ship)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    out.paste(composed, (off, off), composed)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="build/raw_art2/app_icon_v190.jpg")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    raw = args.raw if os.path.isabs(args.raw) else os.path.join(root, args.raw)
    out = os.path.join(root, "assets", "icons")
    os.makedirs(out, exist_ok=True)

    src = Image.open(raw).convert("RGB")
    # 先缩到 512 再量化，最后最近邻放大：保证 1024 上像素块大小一致
    small = src.resize((512, 512), Image.LANCZOS)
    icon = quantize(small).resize((1024, 1024), Image.NEAREST)
    icon.save(os.path.join(out, "icon_1024.png"))

    # 前景：取游戏内自机精灵（红金 + 星徽），透明底，缩到画布 70%（自适应图标安全区）
    sprite = os.path.join(root, "assets", "ships", "player_pulse.png")
    make_fg(sprite, 1024).save(os.path.join(out, "icon_fg_1024.png"))

    make_bg(1024).save(os.path.join(out, "icon_bg_1024.png"))
    for name in ("icon_1024", "icon_fg_1024", "icon_bg_1024"):
        p = os.path.join(out, name + ".png")
        print("ICON", name, "%d KB" % (os.path.getsize(p) // 1024))


if __name__ == "__main__":
    main()
