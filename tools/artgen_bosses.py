#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""新增三台 Boss 的赛璐璐渲染：宽体无畏舰 / 纵向蛇形 / 四翼裁决者。

复用 tools/artgen_anime.py 的赛璐璐材质与 2x 超采样管线，只新增程序化几何，
输出仍遵守 ShipArt 合同（0.46 外接半径、body/mask/ring/ring_mask）。

用法：
  blender -b --factory-startup --python tools/artgen_bosses.py -- --samples 48
  blender ... -- --only boss_dreadnought --out build/art_bosses
"""
import math
import os
import sys

sys.dont_write_bytecode = True

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import artgen_anime as aa  # noqa: E402

ga = aa.ga
TAU = math.pi * 2


def _mats(tag, base, armor):
    hull = ga.mat_pbr(tag + "_hull", base, 0.94, 0.28)
    armor_m = ga.mat_pbr(tag + "_armor", armor, 0.90, 0.32)
    dark = ga.mat_pbr(tag + "_frame", (0.018, 0.020, 0.030), 0.70, 0.50)
    return hull, armor_m, dark


def build_boss_dreadnought(accent):
    """塔罗斯：横向宽体要塞舰，双舷炮舱 + 中央舰桥，剪影与三台圆盘完全不同。"""
    hull, armor, dark = _mats("dn", (0.040, 0.060, 0.095), (0.075, 0.105, 0.150))
    neon = ga.mat_emit("dn_neon", accent, 1.35)
    core = ga.mat_emit("dn_core", (0.55, 0.85, 1.0), 1.10)

    objs = []
    shield = [(-0.30, 0.62), (0.30, 0.62), (0.52, 0.30), (0.52, -0.30), (0.30, -0.58),
              (0.12, -0.82), (-0.12, -0.82), (-0.30, -0.58), (-0.52, -0.30), (-0.52, 0.30)]
    objs.append(ga.poly_prism("hull", shield, -0.08, 0.10, hull, 0.02))
    objs.append(ga.box("spine", (0.22, 0.90, 0.10), (0, 0.0, 0.12), armor, 0.012))

    for sx in (-1, 1):
        objs.append(ga.box("pod", (0.22, 0.42, 0.14), (sx * 0.58, 0.10, 0.02), armor, 0.014))
        objs.append(ga.cyl("turret", 0.11, 0.18, (sx * 0.58, 0.10, 0.14), dark, 16))
        objs.append(ga.cyl("turret_neon", 0.065, 0.20, (sx * 0.58, 0.10, 0.15), neon, 12, bevel=0.0))
        for k in range(2):
            objs.append(ga.box("barrel", (0.045, 0.26, 0.05),
                               (sx * (0.52 + k * 0.11), -0.30, 0.10), dark, 0.006))
        objs.append(ga.box("wing", (0.30, 0.55, 0.07), (sx * 0.42, 0.42, 0.04),
                           hull, 0.010, rot=(0, 0, sx * 0.42)))
        objs.append(ga.box("wing_neon", (0.06, 0.42, 0.02), (sx * 0.50, 0.36, 0.075),
                           neon, 0.0, rot=(0, 0, sx * 0.42)))
        objs.append(ga.cyl("thruster", 0.10, 0.14, (sx * 0.22, 0.66, 0.02), dark, 16))
        objs.append(ga.cyl("thruster_neon", 0.055, 0.16, (sx * 0.22, 0.66, 0.03),
                           neon, 12, bevel=0.0))

    objs.append(ga.box("bridge", (0.18, 0.24, 0.12), (0, 0.30, 0.20), dark, 0.008))
    objs.append(ga.box("bridge_neon", (0.10, 0.03, 0.02), (0, 0.30, 0.26), neon, 0.0))
    objs.append(ga.cyl("core_seat", 0.18, 0.20, (0, -0.10, 0.05), dark, 20))
    objs.append(ga.arc_ring("core_ring", 0.13, 0.17, 0, TAU, 0.14, 0.17, neon, seg=24, bevel=0.0))
    objs.append(ga.cyl("core_lens", 0.11, 0.24, (0, -0.10, 0.07), core, 20, bevel=0.0))

    ring = []
    rmat = ga.mat_emit("dn_ring", accent, 0.85)
    for base_a in (0.0, math.pi):
        ring.append(ga.arc_ring("ring_arc", 0.80, 0.86, base_a - 0.55, base_a + 0.55,
                                -0.02, 0.03, rmat))
    return objs, ring


def build_boss_serpent(accent):
    """许德拉：纵向五节蛇形母舰，头部朝下，剪影窄长。"""
    hull, armor, dark = _mats("sv", (0.030, 0.060, 0.062), (0.055, 0.110, 0.105))
    neon = ga.mat_emit("sv_neon", accent, 1.35)
    core = ga.mat_emit("sv_core", (0.55, 1.0, 0.85), 1.10)

    objs = []
    head = [(0, -0.94), (0.20, -0.66), (0.28, -0.30), (0.10, -0.14),
            (-0.10, -0.14), (-0.28, -0.30), (-0.20, -0.66)]
    objs.append(ga.poly_prism("head", head, -0.08, 0.10, hull, 0.018))
    for sx in (-1, 1):
        objs.append(ga.box("mandible", (0.06, 0.34, 0.08), (sx * 0.14, -0.58, 0.02),
                           armor, 0.008, rot=(0, 0, sx * 0.25)))
        objs.append(ga.box("mandible_neon", (0.02, 0.26, 0.02), (sx * 0.18, -0.56, 0.07),
                           neon, 0.0, rot=(0, 0, sx * 0.25)))
        objs.append(ga.cyl("eye", 0.045, 0.08, (sx * 0.10, -0.42, 0.10), neon, 12, bevel=0.0))

    seg_y = [0.02, 0.28, 0.52, 0.74, 0.92]
    seg_w = [0.34, 0.30, 0.26, 0.20, 0.14]
    for i, (y, w) in enumerate(zip(seg_y, seg_w)):
        pts = [(0, y + 0.16), (w, y + 0.02), (w * 0.85, y - 0.14),
               (0, y - 0.22), (-w * 0.85, y - 0.14), (-w, y + 0.02)]
        objs.append(ga.poly_prism("seg", pts, -0.05, 0.08,
                                  armor if i % 2 else hull, 0.014))
        objs.append(ga.box("seg_neon", (w * 1.3, 0.018, 0.02), (0, y, 0.09), neon, 0.0))
        if i < 3:
            for sx in (-1, 1):
                objs.append(ga.box("fin", (0.26, 0.10, 0.05), (sx * (w + 0.13), y - 0.04, 0.02),
                                   hull, 0.006, rot=(0, 0, sx * 0.55)))

    objs.append(ga.cyl("core_seat", 0.15, 0.18, (0, 0.18, 0.05), dark, 20))
    objs.append(ga.cyl("core_lens", 0.09, 0.22, (0, 0.18, 0.07), core, 20, bevel=0.0))

    ring = []
    rmat = ga.mat_emit("sv_ring", accent, 0.85)
    for base_a in (0.0, math.pi):
        ring.append(ga.arc_ring("ring_arc", 0.74, 0.80, base_a - 0.35, base_a + 0.35,
                                -0.02, 0.03, rmat))
    return objs, ring


def build_boss_seraph(accent):
    """塞拉弗：四翼 X 形 + 光环，中央长菱核心。"""
    hull, armor, dark = _mats("sr", (0.070, 0.048, 0.040), (0.120, 0.085, 0.055))
    neon = ga.mat_emit("sr_neon", accent, 1.35)
    core = ga.mat_emit("sr_core", (1.0, 0.85, 0.70), 1.15)

    objs = []
    objs.append(ga.poly_prism("spine", [(0, 0.74), (0.22, 0.20), (0, -0.94), (-0.22, 0.20)],
                              -0.08, 0.10, hull, 0.018))
    for sx in (-1, 1):
        upper = [(sx * 0.10, 0.10), (sx * 0.80, 0.58), (sx * 0.70, 0.74), (sx * 0.06, 0.24)]
        lower = [(sx * 0.10, -0.10), (sx * 0.74, -0.54), (sx * 0.64, -0.70), (sx * 0.06, -0.22)]
        objs.append(ga.poly_prism("wing_up", upper, -0.05, 0.06, hull, 0.012))
        objs.append(ga.poly_prism("wing_lo", lower, -0.045, 0.05, armor, 0.012))
        objs.append(ga.box("wing_neon", (0.44, 0.035, 0.02),
                           (sx * 0.44, 0.40, 0.075), neon, 0.0, rot=(0, 0, sx * 0.55)))
    objs.append(ga.cyl("core_seat", 0.17, 0.20, (0, 0.02, 0.05), dark, 20))
    objs.append(ga.arc_ring("core_ring", 0.12, 0.16, 0, TAU, 0.14, 0.17, neon, seg=24, bevel=0.0))
    objs.append(ga.cyl("core_lens", 0.10, 0.24, (0, 0.02, 0.07), core, 20, bevel=0.0))
    objs.append(ga.box("spear", (0.05, 0.30, 0.02), (0, -0.74, 0.07), neon, 0.0))

    ring = []
    rmat = ga.mat_emit("sr_ring", accent, 0.90)
    for k in range(3):
        a0 = k * TAU / 3 + 0.10
        ring.append(ga.arc_ring("ring_arc", 0.82, 0.88, a0, a0 + 1.70, -0.02, 0.03, rmat))
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        ring.append(ga.cyl("ring_dot", 0.032, 0.05,
                           (math.cos(a) * 0.85, math.sin(a) * 0.85, 0.02), rmat, 12, bevel=0.0))
    return objs, ring


ga.MODELS["boss_dreadnought"] = (build_boss_dreadnought, 640, "#6FA8FF")
ga.MODELS["boss_serpent"] = (build_boss_serpent, 640, "#7CF5C8")
ga.MODELS["boss_seraph"] = (build_boss_seraph, 640, "#FF9F43")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = "boss_dreadnought,boss_serpent,boss_seraph"
    out = os.path.join(ROOT, "assets", "ships")
    samples = 48
    for i, a in enumerate(argv):
        if a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
        elif a == "--out" and i + 1 < len(argv):
            out = argv[i + 1]
        elif a == "--samples" and i + 1 < len(argv):
            samples = int(argv[i + 1])
    os.makedirs(out, exist_ok=True)

    ga.setup_render = aa.setup_render
    ga.setup_lights = aa.setup_lights
    ga.mat_pbr = aa.mat_pbr
    ga.mat_emit = aa.mat_emit
    ga.mat_glass = aa.mat_glass
    ga.render_to = aa.render_to
    ga.fit_to_contract = aa.fit_to_contract
    ga.render_asset = aa.render_asset

    for name in [s.strip() for s in only.split(",") if s.strip()]:
        if name not in ga.MODELS:
            print("SKIP unknown asset:", name)
            continue
        aa.render_asset(name, out, samples)


if __name__ == "__main__":
    main()
