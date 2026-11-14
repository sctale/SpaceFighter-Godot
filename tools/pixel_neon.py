#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把豆包（Seedream）生成的原始插画转成像素霓虹精灵图。

流程：去背景（从边缘泛洪，保留机体内部深色）→ 裁边 → 方化并留 0.46 外接半径
→ 最近邻降采样到像素网格 → 量化到固定霓虹色板 → 最近邻放大到画布尺寸
→ 输出 <name>.png 与 <name>_mask.png（白色剪影，尺寸一致）。

用法：
  python tools/pixel_neon.py --raw build/raw_art --out assets/ships \
      --profile player:pulse,prism,swarm enemy:drifter,... boss:gatekeeper,...
  python tools/pixel_neon.py --one player_pulse --kind player
"""
import argparse
import os
from collections import deque

from PIL import Image

# 霓虹色板：暗底 + 洋红 + 青 + 紫 + 少量点缀色
PALETTE = [
    (5, 3, 12), (12, 8, 32), (26, 16, 56), (42, 27, 94), (59, 42, 140),
    (90, 59, 255), (123, 75, 255), (176, 107, 255),
    (255, 46, 136), (255, 107, 193), (255, 155, 216),
    (15, 168, 160), (34, 240, 224), (124, 249, 238),
    (182, 255, 60), (255, 193, 77), (255, 107, 61),
    (242, 247, 255), (168, 180, 216), (90, 107, 150),
]

# 画布尺寸 / 像素网格：与 main.gd 的 ART_EXTENT=0.46 契约一致
KIND = {
    "player": (512, 56),
    "enemy": (384, 44),
    "boss": (640, 96),
    "crate": (192, 24),
    "drone": (192, 22),
    "icon": (192, 20),
}


def _flood_bg(img: Image.Image, tol: int = 46) -> Image.Image:
    """从四边泛洪去掉背景；tol 控制容差，避免吃掉机体内部深色像素。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    visited = bytearray(w * h)
    q = deque()

    def dark(x: int, y: int) -> bool:
        r, g, b, _ = px[x, y]
        return r <= tol and g <= tol and b <= tol

    for x in range(w):
        for y in (0, h - 1):
            if not visited[y * w + x] and dark(x, y):
                visited[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if not visited[y * w + x] and dark(x, y):
                visited[y * w + x] = 1
                q.append((x, y))

    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx] and dark(nx, ny):
                visited[ny * w + nx] = 1
                q.append((nx, ny))

    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def _trim_alpha(img: Image.Image) -> Image.Image:
    """输入本身已带透明通道时，直接按 alpha 裁边。"""
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def _square_pad(img: Image.Image, extent: float = 0.46) -> Image.Image:
    """方化画布，使最远不透明像素到中心的距离 = extent × 边长。"""
    w, h = img.size
    side = int(round(max(w, h) / (extent * 2.0) * 1.0))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return canvas


def _nearest(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.NEAREST)


def _quantize(img: Image.Image) -> Image.Image:
    """按色板量化 RGB，保留 alpha。"""
    pal = Image.new("P", (1, 1))
    flat = []
    for c in PALETTE:
        flat.extend(c)
    flat.extend([0, 0, 0] * (256 - len(PALETTE)))
    pal.putpalette(flat)
    rgb = img.convert("RGB")
    idx = rgb.quantize(palette=pal, dither=Image.NONE).convert("RGB")
    out = idx.convert("RGBA")
    out.putalpha(img.getchannel("A"))
    return out


def _harden_alpha(img: Image.Image, threshold: int = 128) -> Image.Image:
    a = img.getchannel("A").point(lambda v: 255 if v >= threshold else 0)
    img.putalpha(a)
    return img


def convert(raw_path: str, out_path: str, kind: str, alpha_input: bool = False) -> None:
    canvas_side, grid = KIND[kind]
    src = Image.open(raw_path).convert("RGBA")
    # 统一先缩到 1024 以内，泛洪更快
    if max(src.size) > 1200:
        src = src.resize((1024, int(1024 * src.size[1] / src.size[0])), Image.LANCZOS)
    stripped = _trim_alpha(src) if alpha_input else _flood_bg(src)
    squared = _square_pad(stripped)
    small = _nearest(squared, grid)
    small = _harden_alpha(small)
    small = _quantize(small)
    # 再清一次透明像素的 RGB，避免缩放大时边缘溢色
    px = small.load()
    for y in range(grid):
        for x in range(grid):
            r, g, b, a = px[x, y]
            if a == 0:
                px[x, y] = (0, 0, 0, 0)
    final = small.resize((canvas_side, canvas_side), Image.NEAREST)
    final.save(out_path)

    mask = Image.new("RGBA", (canvas_side, canvas_side), (255, 255, 255, 0))
    mask.putalpha(final.getchannel("A"))
    mask_path = out_path.replace(".png", "_mask.png")
    mask.save(mask_path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="build/raw_art")
    ap.add_argument("--out", default="assets/ships")
    ap.add_argument("--one", default="")
    ap.add_argument("--kind", default="enemy")
    ap.add_argument("--jobs", default="")
    ap.add_argument("--alpha", action="store_true",
                    help="输入已带透明通道（用于把旧美术像素化）")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    raw_dir = args.raw if os.path.isabs(args.raw) else os.path.join(root, args.raw)
    out_dir = args.out if os.path.isabs(args.out) else os.path.join(root, args.out)

    pairs = []
    if args.one:
        pairs.append((args.one, args.kind))
    elif args.jobs:
        for chunk in args.jobs.split(";"):
            if not chunk.strip():
                continue
            kind, names = chunk.split(":")
            for n in names.split(","):
                pairs.append((n.strip(), kind))
    if not pairs:
        raise SystemExit("nothing to do: pass --one or --jobs")

    for name, kind in pairs:
        src = None
        for ext in (".jpg", ".png", ".jpeg"):
            cand = os.path.join(raw_dir, name + ext)
            if os.path.exists(cand):
                src = cand
                break
        if src is None:
            print("MISSING", name)
            continue
        dst = os.path.join(out_dir, name + ".png")
        convert(src, dst, kind, args.alpha)
        print("PIXEL", name, kind, "%d KB" % (os.path.getsize(dst) // 1024))


if __name__ == "__main__":
    main()
