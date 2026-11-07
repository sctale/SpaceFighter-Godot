#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""主菜单主视觉：3/4 视角赛璐璐 Hero 机体 + 3D 标题 Logo + 星球。

复用 tools/artgen_anime.py 的材质与描边设置，输出到 assets/keyart/。
用法：
  blender -b --factory-startup --python tools/artgen_keyart.py -- --only hero,logo
"""
import math
import os
import sys

sys.dont_write_bytecode = True

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import artgen_anime as aa  # noqa: E402
import anime_toon as at  # noqa: E402

ga = aa.ga
OUT = os.path.join(ROOT, "assets", "keyart")


def install_patches():
    """复用 artgen_anime 的赛璐璐材质/描边/渲染设置。"""
    ga.setup_render = aa.setup_render
    ga.setup_lights = aa.setup_lights
    ga.mat_pbr = aa.mat_pbr
    ga.mat_emit = aa.mat_emit
    ga.mat_glass = aa.mat_glass
    ga.render_to = aa.render_to
    ga.fit_to_contract = aa.fit_to_contract
    ga.render_asset = aa.render_asset


def _camera_look(cam, target=Vector((0, 0, 0))):
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()


def _render(path, w, h, ss=2):
    sc = bpy.context.scene
    sc.render.resolution_x = w * ss
    sc.render.resolution_y = h * ss
    sc.render.resolution_percentage = 100
    tmp = path + "~ss.png"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    img.scale(w, h)
    img.save_render(path, scene=sc)
    bpy.data.images.remove(img)
    os.remove(tmp)
    print("RENDER", os.path.basename(path))


def _setup_hero():
    accent = at.hex_rgb(at.boost_hex("#35E0C8"))
    at.CURRENT_ACCENT = accent
    aa.setup_render(48)
    ga.setup_world()
    body, ring = ga.build_player_pulse(accent)
    body = ga._flat(body)
    ga.normalize(body, radius=0.84)
    cam_data = bpy.data.cameras.new("HeroCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.05
    cam = bpy.data.objects.new("HeroCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (1.25, -2.15, 1.95)
    _camera_look(cam)
    bpy.context.scene.camera = cam
    at.configure_freestyle(1024)


def _text_mesh(name, body, size, y, mat, spacing=1.0):
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = body
    font_path = "C:/Windows/Fonts/simhei.ttf"
    if not os.path.exists(font_path):
        font_path = "C:/Windows/Fonts/msyhbd.ttc"
    curve.font = bpy.data.fonts.load(font_path)
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = size
    curve.space_character = spacing
    curve.extrude = size * 0.10
    curve.bevel_depth = size * 0.018
    curve.bevel_resolution = 2
    ob = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(ob)
    ob.location = (0, y, 0.10)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target="MESH")
    ob = bpy.context.view_layer.objects.active
    ob.data.materials.append(mat)
    return ob


def _setup_logo():
    pink = at.hex_rgb("#F0557F")
    at.CURRENT_ACCENT = pink
    aa.setup_render(40)
    ga.setup_world()
    title_mat = at.make_toon("logo_title", (0.08, 0.04, 0.06), accent=pink)
    sub_mat = at.make_toon("logo_sub", (0.08, 0.04, 0.06), accent=pink)
    _text_mesh("logo_title", "裂隙巡航", 0.36, 0.13, title_mat)
    _text_mesh("logo_sub", "A U R O R A   R I F T", 0.085, -0.24, sub_mat, 1.0)
    cam_data = bpy.data.cameras.new("LogoCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.95
    cam = bpy.data.objects.new("LogoCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0, 0, 6)
    cam.rotation_euler = (0, 0, 0)
    bpy.context.scene.camera = cam
    at.configure_freestyle(1024)


def _setup_planet():
    accent = at.hex_rgb("#8FE8D8")
    at.CURRENT_ACCENT = accent
    aa.setup_render(40)
    ga.setup_world()
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.72, location=(0, 0, 0))
    planet = bpy.context.object
    bpy.ops.object.shade_smooth()
    planet.data.materials.append(at.make_toon("planet_hull", (0.4, 0.55, 0.9), accent=accent))
    ring_mat = at.make_toon("planet_ring", (0.9, 0.7, 0.8), accent=accent)
    pts = []
    seg = 64
    for i in range(seg):
        a = math.pi * 2 * i / seg
        pts.append((math.cos(a) * 1.28, math.sin(a) * 1.28))
    inner = []
    for i in range(seg):
        a = -math.pi * 2 * i / seg
        inner.append((math.cos(a) * 0.98, math.sin(a) * 0.98))
    mesh = bpy.data.meshes.new("planet_ring")
    ob = bpy.data.objects.new("planet_ring", mesh)
    bpy.context.collection.objects.link(ob)
    verts = [(x, y, 0) for x, y in pts + inner]
    faces = []
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((i, j, seg + j, seg + i))
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(ring_mat)
    ob.rotation_euler = (math.radians(24), 0, math.radians(-8))
    cam_data = bpy.data.cameras.new("PlanetCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.0
    cam = bpy.data.objects.new("PlanetCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.7, -2.6, 1.9)
    _camera_look(cam)
    bpy.context.scene.camera = cam
    at.configure_freestyle(1024)


def main():
    install_patches()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = "hero,logo,planet"
    for i, a in enumerate(argv):
        if a == "--only" and i + 1 < len(argv):
            only = argv[i + 1]
    os.makedirs(OUT, exist_ok=True)
    for name in [s.strip() for s in only.split(",") if s.strip()]:
        ga.reset_scene()
        if name == "hero":
            _setup_hero()
            _render(os.path.join(OUT, "hero.png"), 1024, 1024)
        elif name == "logo":
            _setup_logo()
            _render(os.path.join(OUT, "logo.png"), 1024, 512)
        elif name == "planet":
            _setup_planet()
            _render(os.path.join(OUT, "planet.png"), 1024, 1024)


if __name__ == "__main__":
    main()
