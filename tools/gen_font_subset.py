#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 Godot 版中文字体子集（Noto Sans CJK SC）。

扫描 scripts/*.gd 里用到的全部字符，用 pyftsubset 裁出 ~300KB 的小字体，
避免在缺少中文字体的设备上出现豆腐块。源文件：reference/artgen/fontwork。

用法：python tools/gen_font_subset.py
"""
import glob
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "reference", "artgen", "fontwork", "NotoSansCJK-Regular.ttc")
OUT = os.path.join(ROOT, "assets", "fonts", "AuroraCJK.ttf")

EXTRA = "×·—…！？、。：；「」『』（）【】《》％＋－÷＝０１２３４５６７８９"

def main():
    if not os.path.exists(SRC):
        print("缺少源字体:", SRC)
        return 1
    chars = set(EXTRA)
    for p in glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True) + \
             glob.glob(os.path.join(ROOT, "tools", "**", "*.gd"), recursive=True):
        with open(p, encoding="utf-8") as f:
            chars.update(f.read())
    text = "".join(sorted(c for c in chars if ord(c) >= 0x20 and (ord(c) < 128 or ord(c) >= 0xA0)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    cmd = [
        "pyftsubset", SRC, "--font-number=2",
        "--text=" + text,
        "--unicodes=U+0000-00FF,U+2000-206F,U+2190-21FF,U+25A0-25FF",
        "--layout-features=", "--no-hinting",
        "--output-file=" + OUT,
    ]
    subprocess.run(cmd, check=True)
    print("wrote", OUT, os.path.getsize(OUT), "bytes,", len(text), "chars")
    return 0

if __name__ == "__main__":
    sys.exit(main())
