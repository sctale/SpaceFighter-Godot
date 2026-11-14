#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用豆包出图生成像素霓虹启动图标三件套。

输出：
  assets/icons/icon_1024.png     桌面/商店图标（保留背景）
  assets/icons/icon_fg_1024.png  安卓自适应图标前景（透明底，机体居中 62%）
  assets/icons/icon_bg_1024.png  安卓自适应图标背景（程序化霓虹网格）

用法：python tools/gen_icon_pixel.py [--raw build/raw_art/app_icon.jpg]
"""
import argparse
import math
import os
from collections import deque

from PIL import Image, ImageDraw, ImageFilter

NEON_PINK = (255, 46, 136)
NEON_CYAN = (34, 240, 224)
DEEP = (5, 3, 12)


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
    """程序化背景：深空底 + 中心洋红辉光 + 青色霓虹网格 + 暗角。"""
    img = Image.new("RGB", (size, size), DEEP)
    d = ImageDraw.Draw(img, "RGBA")
    # 中心辉光：低饱和、低透明度，避免盖住前景
    cx = cy = size // 2
    for i in range(18, 0, -1):
        r = int(size * 0.50 * i / 18.0)
        a = int(2 + 5 * (1.0 - i / 18.0))
        d.ellipse([cx - r, cy - int(r * 1.02), cx + r, cy + int(r * 1.02)],
                  fill=(NEON_PINK[0], NEON_PINK[1], NEON_PINK[2], a))
    # 霓虹网格
    step = size // 16
    for i in range(1, 16):
        x = i * step
        d.line([(x, 0), (x, size)], fill=(NEON_CYAN[0], NEON_CYAN[1], NEON_CYAN[2], 20))
        d.line([(0, x), (size, x)], fill=(NEON_CYAN[0], NEON_CYAN[1], NEON_CYAN[2], 20))
    # 四角暗角
    vig = Image.new("L", (size, size), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-size * 0.30, -size * 0.30, size * 1.30, size * 1.30], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(size * 0.10))
    dark = Image.new("RGB", (size, size), (3, 2, 8))
    return Image.composite(img, dark, vig)


def make_fg(sprite_path: str, size: int = 1024) -> Image.Image:
    """前景直接用游戏内自机精灵（alpha 干净），放大后加洋红外发光。"""
    sprite = Image.open(sprite_path).convert("RGBA")
    inner = int(size * 0.70)
    ship = sprite.resize((inner, inner), Image.NEAREST)
    # 外发光
    glow_a = ship.split()[3].filter(ImageFilter.GaussianBlur(inner * 0.035))
    glow = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    glow.putalpha(glow_a.point(lambda v: int(v * 0.75)))
    pink = Image.new("RGBA", (inner, inner), NEON_PINK + (255,))
    glow = Image.composite(pink, Image.new("RGBA", (inner, inner), (0, 0, 0, 0)), glow.split()[3])
    composed = Image.alpha_composite(glow, ship)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    off = (size - inner) // 2
    out.paste(composed, (off, off), composed)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="build/raw_art/app_icon.jpg")
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    raw = args.raw if os.path.isabs(args.raw) else os.path.join(root, args.raw)
    out = os.path.join(root, "assets", "icons")
    os.makedirs(out, exist_ok=True)

    src = Image.open(raw).convert("RGB")
    # 保留像素块：直接最近邻缩放到 1024
    icon = src.resize((1024, 1024), Image.NEAREST)
    icon.save(os.path.join(out, "icon_1024.png"))

    # 前景：取游戏内自机精灵，透明底，缩到画布 70%（自适应图标安全区）
    sprite = os.path.join(root, "assets", "ships", "player_prism.png")
    if not os.path.exists(sprite):
        sprite = os.path.join(root, "assets", "ships", "player_pulse.png")
    make_fg(sprite, 1024).save(os.path.join(out, "icon_fg_1024.png"))

    make_bg(1024).save(os.path.join(out, "icon_bg_1024.png"))
    for name in ("icon_1024", "icon_fg_1024", "icon_bg_1024"):
        p = os.path.join(out, name + ".png")
        print("ICON", name, "%d KB" % (os.path.getsize(p) // 1024))


if __name__ == "__main__":
    main()
