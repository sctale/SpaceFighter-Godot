"""程序化生成 3D 像素块补给箱（参考《像素飞机大战》的厚边金框木箱）。

10 种补给箱统一为「暗红面板 + 金色厚边 + 四角铆钉 + 类型图标」，
24x24 像素网格，最近邻放大到 192，并输出 alpha mask。

用法：python tools/gen_crates_chunky.py
"""
import os

from PIL import Image, ImageDraw

GRID = 24
SCALE = 192 // GRID

DARK = (24, 6, 10)
OUTLINE = (42, 10, 16)
PANEL = (58, 16, 22)
PANEL_LIGHT = (78, 24, 28)
GOLD = (255, 198, 55)
GOLD_DEEP = (224, 154, 30)
CREAM = (255, 243, 214)

RED = (216, 69, 60)
RED_LIGHT = (244, 116, 87)
GREEN = (79, 203, 94)
GREEN_LIGHT = (160, 235, 150)
CYAN = (95, 224, 232)
CYAN_DEEP = (47, 184, 201)
ORANGE = (255, 138, 61)
VIOLET = (123, 91, 214)
BLUE = (61, 107, 224)


def frame(d: ImageDraw.ImageDraw) -> None:
    """暗红面板 + 金色厚边 + 顶部高光 + 四角铆钉。"""
    d.rectangle([1, 1, GRID - 2, GRID - 2], fill=OUTLINE)
    d.rectangle([2, 2, GRID - 3, GRID - 3], fill=GOLD_DEEP)
    d.rectangle([3, 3, GRID - 4, GRID - 4], fill=GOLD)
    d.rectangle([4, 4, GRID - 5, GRID - 5], fill=PANEL)
    d.rectangle([5, 5, GRID - 6, GRID - 6], fill=PANEL)
    # 顶部/左侧高光，右下阴影，做出塑料块体积
    d.line([(5, 5), (GRID - 6, 5)], fill=PANEL_LIGHT)
    d.line([(5, 5), (5, GRID - 6)], fill=PANEL_LIGHT)
    d.line([(GRID - 6, 6), (GRID - 6, GRID - 6)], fill=OUTLINE)
    d.line([(6, GRID - 6), (GRID - 6, GRID - 6)], fill=OUTLINE)
    for (x, y) in [(3, 3), (GRID - 4, 3), (3, GRID - 4), (GRID - 4, GRID - 4)]:
        d.point((x, y), fill=CREAM)


def icon_weapon(d: ImageDraw.ImageDraw) -> None:
    d.polygon([(12, 6), (16, 13), (8, 13)], fill=RED)
    d.rectangle([10, 13, 14, 16], fill=RED_LIGHT)
    d.rectangle([11, 16, 13, 18], fill=CREAM)


def icon_prism(d: ImageDraw.ImageDraw) -> None:
    d.polygon([(12, 5), (18, 12), (12, 19), (6, 12)], fill=VIOLET)
    d.polygon([(12, 7), (16, 12), (12, 17), (8, 12)], fill=CREAM)
    d.point((12, 12), fill=CYAN)


def icon_drone(d: ImageDraw.ImageDraw) -> None:
    d.rectangle([11, 8, 13, 17], fill=GOLD)
    d.rectangle([6, 11, 18, 13], fill=GOLD_DEEP)
    d.rectangle([5, 10, 7, 14], fill=GOLD)
    d.rectangle([17, 10, 19, 14], fill=GOLD)
    d.point((12, 10), fill=CREAM)


def icon_life(d: ImageDraw.ImageDraw) -> None:
    d.rectangle([10, 6, 14, 18], fill=RED)
    d.rectangle([6, 10, 18, 14], fill=RED)
    d.rectangle([11, 6, 13, 12], fill=RED_LIGHT)
    d.point((12, 8), fill=CREAM)


def icon_reflect(d: ImageDraw.ImageDraw) -> None:
    d.arc([6, 6, 18, 18], 30, 300, fill=ORANGE, width=2)
    d.polygon([(16, 5), (20, 9), (15, 10)], fill=ORANGE)
    d.point((12, 12), fill=CREAM)


def icon_shield(d: ImageDraw.ImageDraw) -> None:
    d.polygon([(12, 5), (18, 8), (17, 15), (12, 19), (7, 15), (6, 8)], fill=CYAN_DEEP)
    d.polygon([(12, 7), (16, 9), (15, 14), (12, 17), (9, 14), (8, 9)], fill=PANEL)
    d.rectangle([11, 9, 13, 14], fill=CYAN)


def icon_swap(d: ImageDraw.ImageDraw) -> None:
    d.line([(7, 9), (17, 9)], fill=GREEN, width=2)
    d.polygon([(17, 6), (21, 9), (17, 12)], fill=GREEN_LIGHT)
    d.line([(7, 15), (17, 15)], fill=GREEN, width=2)
    d.polygon([(7, 12), (3, 15), (7, 18)], fill=GREEN_LIGHT)


def icon_swarm(d: ImageDraw.ImageDraw) -> None:
    for (x, y) in [(12, 8), (8, 13), (16, 13), (12, 17)]:
        d.polygon([(x, y - 3), (x + 3, y), (x, y + 3), (x - 3, y)], fill=GREEN)
    d.point((12, 17), fill=GREEN_LIGHT)


def icon_charge(d: ImageDraw.ImageDraw) -> None:
    d.polygon([(14, 5), (8, 13), (12, 13), (10, 19), (17, 10), (13, 10)], fill=GOLD)
    d.point((13, 8), fill=CREAM)


def icon_gem(d: ImageDraw.ImageDraw) -> None:
    d.polygon([(12, 5), (17, 10), (12, 19), (7, 10)], fill=CYAN)
    d.polygon([(12, 7), (15, 10), (12, 16), (9, 10)], fill=CYAN_DEEP)
    d.line([(9, 10), (15, 10)], fill=CREAM)


ICONS = {
    "weapon": icon_weapon,
    "prism": icon_prism,
    "drone": icon_drone,
    "life": icon_life,
    "reflect": icon_reflect,
    "shield": icon_shield,
    "swap": icon_swap,
    "swarm": icon_swarm,
    "charge": icon_charge,
    "gem": icon_gem,
}


def make(name: str, draw_icon) -> Image.Image:
    grid = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)
    frame(d)
    draw_icon(d)
    big = grid.resize((GRID * SCALE, GRID * SCALE), Image.NEAREST)
    canvas = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    off = (192 - big.size[0]) // 2
    canvas.paste(big, (off, off), big)
    return canvas


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "assets", "ships")
    for kind, fn in ICONS.items():
        img = make(kind, fn)
        img.save(os.path.join(out, "crate_" + kind + ".png"))
        mask = Image.new("RGBA", img.size, (255, 255, 255, 0))
        mask.putalpha(img.split()[3])
        mask.save(os.path.join(out, "crate_" + kind + "_mask.png"))
        print("CRATE", kind, "%d KB" % (os.path.getsize(os.path.join(out, "crate_" + kind + ".png")) // 1024))


if __name__ == "__main__":
    main()
