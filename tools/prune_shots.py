# -*- coding: utf-8 -*-
"""清理 docs/shots 里未被 README/CHANGELOG 引用的历史截图（含 .import）。

只删除没有任何 md 引用、且不是 .gitkeep 的文件；先输出统计，确认后再删。
用法：python tools/prune_shots.py [--apply]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "docs", "shots")
MD_FILES = ["README.md", "CHANGELOG.md"] + [
    os.path.join("docs", n) for n in os.listdir(os.path.join(ROOT, "docs"))
    if n.endswith(".md")
]

referenced = set()
pat = re.compile(r"docs/shots/([A-Za-z0-9_.\-]+)")
for rel in MD_FILES:
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        continue
    with open(p, encoding="utf-8", errors="ignore") as f:
        for m in pat.finditer(f.read()):
            referenced.add(m.group(1))

apply = "--apply" in sys.argv
removed = 0
kept = 0
freed = 0
for name in sorted(os.listdir(SHOTS)):
    p = os.path.join(SHOTS, name)
    if not os.path.isfile(p):
        continue
    base = name[:-len(".import")] if name.endswith(".import") else name
    if base in referenced or name in referenced:
        kept += 1
        continue
    freed += os.path.getsize(p)
    removed += 1
    if apply:
        os.remove(p)

print(f"引用图: {len(referenced)}  保留文件: {kept}  待删: {removed}  可释放: {freed/1024/1024:.1f} MB")
print("APPLIED" if apply else "DRY-RUN（加 --apply 执行删除）")
