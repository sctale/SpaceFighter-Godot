# -*- coding: utf-8 -*-
"""赛璐璐材质与描边：给 Blender 渲染管线复用的 toon 节点组。

设计语言：奶油白/淡紫机体 + 深梅色厚描边 + 双色阶硬阴影 + 高饱和霓虹边。
所有材质都是 Emission（对布光免疫），明暗只由法线角度和 AO 决定。
"""
import colorsys
import math

import bpy
from mathutils import Vector

INK = "#2B2338"
CREAM = "#FFF1DC"
PAPER = "#FFFDF7"
DARK = "#4A435E"
DEEP = "#302A40"
GLASS = "#2A5C72"
CRATE = "#FFFDF5"
CRATE_BAND = "#DAD3EA"

# 当前机体的身份色，由渲染入口在每张图前设置（线性 RGB）
CURRENT_ACCENT = (0.2, 0.9, 0.8)
LIGHT_DIR = Vector((0.35, 0.55, 0.76)).normalized()


def _to_linear(v: float) -> float:
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def hex_rgb(s: str) -> tuple:
    s = s.lstrip("#")
    return tuple(_to_linear(int(s[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def mix(a: tuple, b: tuple, t: float) -> tuple:
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def boost_hex(s: str) -> str:
    """把低饱和的旧身份色提亮提纯，保证每个机种在奶油底上仍有辨识色。"""
    s = s.lstrip("#")
    r, g, b = (int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, sat, v = colorsys.rgb_to_hsv(r, g, b)
    if sat > 0.10:
        sat = max(sat, 0.55)
        v = min(1.0, max(v, 0.92))
    r, g, b = colorsys.hsv_to_rgb(h, sat, v)
    return "#%02X%02X%02X" % (round(r * 255), round(g * 255), round(b * 255))


def _ramp(node, stops):
    ramp = node.color_ramp
    ramp.interpolation = "CONSTANT"
    while len(ramp.elements) > len(stops):
        ramp.elements.remove(ramp.elements[-1])
    while len(ramp.elements) < len(stops):
        ramp.elements.new(0.5)
    for el, (pos, col) in zip(ramp.elements, stops):
        el.position = pos
        el.color = (*col, 1.0)


def _tint_factors(name: str) -> tuple:
    """机体阵营决定奶油底色的染色强度：敌机更强，玩家机接近象牙白。"""
    if name.startswith("enemy_"):
        return 0.34, 0.30
    if name.startswith("boss_"):
        return 0.24, 0.22
    if name.startswith("player_"):
        return 0.16, 0.24
    if name.startswith("crate_"):
        return 0.20, 0.18
    return 0.18, 0.16


def palette_color(name: str, accent: tuple) -> tuple:
    """按材质语义映射到赛璐璐亮色板；same-name 材质在不同机体上保持同色。"""
    n = name.lower()
    hull_t, armor_t = _tint_factors(n)
    if "crate_band" in n:
        return hex_rgb(CRATE_BAND)
    if "crate_hull" in n:
        return hex_rgb(CRATE)
    if "glass" in n or "canopy" in n:
        return hex_rgb(GLASS)
    if "bl_rim" in n or "_rim" in n:
        return mix(hex_rgb(DARK), accent, 0.12)
    if "boss_neon" in n or "neon" in n:
        return accent
    if "core" in n:
        return mix(accent, hex_rgb(PAPER), 0.25)
    if "frame" in n or n.endswith("_dark") or "dark" in n:
        return mix(hex_rgb(DEEP), accent, 0.08)
    if "armor" in n or "plate" in n or "petal" in n:
        return mix(hex_rgb(PAPER), accent, armor_t)
    if "hull" in n or "steel" in n or "spine" in n:
        return mix(hex_rgb(CREAM), accent, hull_t)
    return mix(hex_rgb(CREAM), accent, 0.16)


def make_toon(name: str, base, metallic=0.0, rough=0.5, emit=None, emit_strength=0.0, accent=None):
    """双色阶 + AO + 菲涅尔描边光。base/metallic/rough 仅为兼容旧调用签名。"""
    acc = accent if accent is not None else CURRENT_ACCENT
    color = palette_color(name, acc)
    if emit is not None and sum(emit) > 1.2:
        color = mix(color, emit, 0.35)

    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes["Material Output"]

    geo = nt.nodes.new("ShaderNodeNewGeometry")
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    dot.inputs[1].default_value = LIGHT_DIR
    nt.links.new(geo.outputs["Normal"], dot.inputs[0])

    shade = nt.nodes.new("ShaderNodeValToRGB")
    dark = mix(color, hex_rgb(INK), 0.42)
    light = mix(color, hex_rgb(PAPER), 0.55)
    _ramp(shade, [(0.0, dark), (0.30, color), (0.64, light)])
    nt.links.new(dot.outputs["Value"], shade.inputs["Fac"])

    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.16
    if hasattr(ao, "samples"):
        ao.samples = 8
    ao_mix = nt.nodes.new("ShaderNodeMixRGB")
    ao_mix.blend_type = "MULTIPLY"
    ao_mix.inputs["Fac"].default_value = 0.68
    nt.links.new(shade.outputs["Color"], ao_mix.inputs["Color1"])
    nt.links.new(ao.outputs["Color"], ao_mix.inputs["Color2"])

    # 斜向硬阴影：纯俯视下顶面法线都一样，只靠法线分不出层次；
    # 用世界坐标在屏幕方向上的投影切一刀，得到动画赛璐璐的大色块。
    pos = nt.nodes.new("ShaderNodeNewGeometry")
    pdot = nt.nodes.new("ShaderNodeVectorMath")
    pdot.operation = "DOT_PRODUCT"
    pdot.inputs[1].default_value = Vector((0.52, 0.74, 0.0)).normalized()
    nt.links.new(pos.outputs["Position"], pdot.inputs[0])
    band = nt.nodes.new("ShaderNodeValToRGB")
    _ramp(band, [(0.0, (0.54, 0.58, 0.84)), (0.44, (0.92, 0.94, 1.0)), (0.80, (1.0, 1.0, 1.0))])
    nt.links.new(pdot.outputs["Value"], band.inputs["Fac"])
    band_mix = nt.nodes.new("ShaderNodeMixRGB")
    band_mix.blend_type = "MULTIPLY"
    band_mix.inputs["Fac"].default_value = 0.92
    nt.links.new(ao_mix.outputs["Color"], band_mix.inputs["Color1"])
    nt.links.new(band.outputs["Color"], band_mix.inputs["Color2"])

    fres = nt.nodes.new("ShaderNodeFresnel")
    fres.inputs["IOR"].default_value = 1.45
    fres_ramp = nt.nodes.new("ShaderNodeValToRGB")
    _ramp(fres_ramp, [(0.0, (0.0, 0.0, 0.0)), (0.62, (1.0, 1.0, 1.0))])
    fres_ramp.color_ramp.interpolation = "LINEAR"
    nt.links.new(fres.outputs["Fac"], fres_ramp.inputs["Fac"])

    rim = nt.nodes.new("ShaderNodeMixRGB")
    rim.blend_type = "ADD"
    rim.inputs["Fac"].default_value = 0.72 if "glass" not in name else 0.95
    # 斜向白色高光条：给大片平涂色块加一道手绘反光
    pdot2 = nt.nodes.new("ShaderNodeVectorMath")
    pdot2.operation = "DOT_PRODUCT"
    pdot2.inputs[1].default_value = Vector((0.78, 0.48, 0.0)).normalized()
    nt.links.new(pos.outputs["Position"], pdot2.inputs[0])
    gloss = nt.nodes.new("ShaderNodeValToRGB")
    _ramp(gloss, [(0.0, (0, 0, 0)), (0.42, (0, 0, 0)), (0.47, (1, 1, 1)),
                  (0.52, (0, 0, 0)), (1.0, (0, 0, 0))])
    nt.links.new(pdot2.outputs["Value"], gloss.inputs["Fac"])
    gloss_mix = nt.nodes.new("ShaderNodeMixRGB")
    gloss_mix.blend_type = "ADD"
    gloss_mix.inputs["Fac"].default_value = 0.20
    nt.links.new(band_mix.outputs["Color"], gloss_mix.inputs["Color1"])
    nt.links.new(gloss.outputs["Color"], gloss_mix.inputs["Color2"])

    nt.links.new(gloss_mix.outputs["Color"], rim.inputs["Color1"])
    nt.links.new(fres_ramp.outputs["Color"], rim.inputs["Color2"])
    rim_tint = nt.nodes.new("ShaderNodeMixRGB")
    rim_tint.blend_type = "MULTIPLY"
    rim_tint.inputs["Fac"].default_value = 1.0
    rim_tint.inputs["Color1"].default_value = (*mix(acc, hex_rgb(PAPER), 0.55), 1.0)
    nt.links.new(rim.outputs["Color"], rim_tint.inputs["Color2"])

    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(rim_tint.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def make_neon(name: str, color, strength=1.6):
    """纯发光件：不加白核，避免小尺寸下霓虹全糊成白点。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = nt.nodes["Material Output"]
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = min(1.25, max(0.75, strength * 0.75))
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def make_glass(name: str, accent):
    return make_toon(name, (0.02, 0.03, 0.04), accent=accent)


def configure_freestyle(canvas: float) -> None:
    """外轮廓粗线 + 内部结构细线，两层线宽是动画线稿的关键。"""
    sc = bpy.context.scene
    sc.render.use_freestyle = True
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(118.0)
    for ls in list(fs.linesets):
        fs.linesets.remove(ls)

    outer = fs.linesets.new("Outer")
    outer.select_silhouette = True
    outer.select_border = True
    outer.select_contour = False
    outer.select_crease = False
    outer.select_edge_mark = False
    outer.linestyle.color = hex_rgb(INK)
    outer.linestyle.thickness = max(5.0, canvas * 0.014)

    inner = fs.linesets.new("Inner")
    inner.select_silhouette = False
    inner.select_border = False
    inner.select_contour = False
    inner.select_crease = True
    inner.select_edge_mark = False
    inner.linestyle.color = hex_rgb(INK)
    inner.linestyle.thickness = max(2.8, canvas * 0.0070)
