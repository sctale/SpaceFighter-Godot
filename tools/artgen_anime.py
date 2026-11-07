#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""在归档 Blender 几何之上重渲一套赛璐璐（日系动画）机体。

复用 reference/artgen/blender/gen_art.py 的程序化模型，只替换材质、描边与
色彩管理，因此画布尺寸 / 0.46 外接半径 / mask / ring 合同全部保持不变。

用法：
  blender -b --factory-startup --python tools/artgen_anime.py -- \
      --only player_pulse,enemy_drifter --out build/art_anime --samples 64
"""
import importlib.util
import os
import sys

# 不往 reference/ 写 __pycache__，保持归档目录只读
sys.dont_write_bytecode = True

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "artgen", "blender", "gen_art.py")
sys.path.insert(0, os.path.join(ROOT, "tools"))

import anime_toon as at  # noqa: E402


def _load_reference():
    spec = importlib.util.spec_from_file_location("aurora_gen_art", REF)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["aurora_gen_art"] = mod
    spec.loader.exec_module(mod)
    return mod


ga = _load_reference()


def setup_render(samples=64):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    try:
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices_for_type("OPTIX")
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception:
        sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 2
    sc.cycles.transparent_max_bounces = 4
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.image_settings.compression = 30
    sc.render.use_persistent_data = True
    sc.render.filter_size = 1.30
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.render.use_freestyle = True


def setup_lights():
    # 全部材质是 Emission，布光不参与成像；清掉灯以缩短渲染时间。
    for ob in list(bpy.data.objects):
        if ob.type == "LIGHT":
            bpy.data.objects.remove(ob, do_unlink=True)


def mat_pbr(name, base, metallic=0.88, rough=0.34, emit=None, emit_strength=0.0):
    return at.make_toon(name, base, metallic, rough, emit, emit_strength)


def mat_emit(name, color, strength=1.6):
    return at.make_neon(name, color, strength)


def mat_glass(name_or_accent, accent=None):
    if accent is None:
        return at.make_glass("glass", name_or_accent)
    return at.make_glass(name_or_accent, accent)


def render_to(path, canvas):
    sc = bpy.context.scene
    is_mask = "_mask" in os.path.basename(path)
    sc.render.use_freestyle = not is_mask
    if not is_mask:
        at.configure_freestyle(canvas)
    # 2 倍超采样后降回合同尺寸：Freestyle 的线稿在 1x 下会有锯齿
    ss = 2
    sc.render.resolution_x = canvas * ss
    sc.render.resolution_y = canvas * ss
    sc.render.resolution_percentage = 100
    tmp = path + "~ss.png"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    img.scale(canvas, canvas)
    img.save_render(path, scene=sc)
    bpy.data.images.remove(img)
    os.remove(tmp)
    print("RENDER", os.path.basename(path))


def fit_to_contract(objs, out_dir, name, preview=160):
    sc = bpy.context.scene
    saved = sc.render.use_freestyle
    sc.render.use_freestyle = False
    try:
        return _ORIG_FIT(objs, out_dir, name, preview)
    finally:
        sc.render.use_freestyle = saved


_ORIG_FIT = ga.fit_to_contract


def render_asset(name, out_dir, samples):
    builder, canvas, accent_hex = ga.MODELS[name]
    boosted = at.boost_hex(accent_hex)
    ga.MODELS[name] = (builder, canvas, boosted)
    at.CURRENT_ACCENT = ga.hex_rgb(boosted)
    _ORIG_RENDER_ASSET(name, out_dir, samples)


_ORIG_RENDER_ASSET = ga.render_asset


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--list" in argv:
        print("ASSETS", ",".join(sorted(ga.MODELS)))
        return
    only = "player_pulse"
    out = os.path.join(ROOT, "build", "art_anime")
    samples = 64
    for i, a in enumerate(argv):
        if a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
        elif a == "--out" and i + 1 < len(argv):
            out = argv[i + 1]
        elif a == "--samples" and i + 1 < len(argv):
            samples = int(argv[i + 1])
    os.makedirs(out, exist_ok=True)

    ga.setup_render = setup_render
    ga.setup_lights = setup_lights
    ga.mat_pbr = mat_pbr
    ga.mat_emit = mat_emit
    ga.mat_glass = mat_glass
    ga.render_to = render_to
    ga.fit_to_contract = fit_to_contract
    ga.render_asset = render_asset

    for name in [s.strip() for s in only.split(",") if s.strip()]:
        if name not in ga.MODELS:
            print("SKIP unknown asset:", name)
            continue
        render_asset(name, out, samples)


if __name__ == "__main__":
    main()
