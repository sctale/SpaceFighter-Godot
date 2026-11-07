class_name SpaceBackdrop
extends Node2D

## 全屏自适应深空背景：程序化星云 shader + 三层视差星 + 赛璐璐星球/月面。
## 不占用预渲染贴图，540x960 / 540x1200 / 720x960 都能铺满。

const PALETTES := [
	{"top": "#1B2450", "mid": "#4C6BD6", "bottom": "#F3C6D9",
	 "neb_a": "#8FE8D8", "neb_b": "#B9A6FF", "glow": "#FFF0C2"},
	{"top": "#2A1D4A", "mid": "#A84F96", "bottom": "#FFD8E3",
	 "neb_a": "#FFB4DA", "neb_b": "#FFE0A8", "glow": "#FFE9C4"},
	{"top": "#103C48", "mid": "#2A9E99", "bottom": "#F4F2D6",
	 "neb_a": "#B4FFE0", "neb_b": "#FFE7A8", "glow": "#FFF6CC"},
	{"top": "#2C1B44", "mid": "#D96D6F", "bottom": "#FFE1B4",
	 "neb_a": "#FF9E8C", "neb_b": "#FFD27A", "glow": "#FFECC0"},
	{"top": "#0C1130", "mid": "#3B3F88", "bottom": "#BBAEFF",
	 "neb_a": "#8B7CFF", "neb_b": "#6FE7FF", "glow": "#D9D2FF"},
]
const ZONE_PALETTE := [0, 0, 1, 1, 2, 2, 3, 3, 4, 4]

var main: Node = null
var view_size := Vector2(540.0, 960.0)
var sky: ColorRect
var sky_mat: ShaderMaterial
var grad_rect: TextureRect
var grad_tex: GradientTexture2D
var grad: Gradient
var planet_rect: ColorRect
var planet_mat: ShaderMaterial
var moon_rect: ColorRect
var moon_mat: ShaderMaterial
var stars: Array = []
var use_shader := true

var _time := 0.0
var _scroll := 0.0
var _dim := 1.0
var _palette_i := 0
var _colors := {}
var _target := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_as_relative = false
	z_index = -1000
	_rng.seed = 20261107
	# 软件渲染（SwiftShader）uniform 上限过低，退回无自定义 shader 的渐变纹理；
	# 真机/硬件模拟器继续用 FBM 星云 shader。
	var adapter := String(RenderingServer.get_video_adapter_name())
	use_shader = not adapter.to_lower().contains("swiftshader")
	if use_shader:
		sky = ColorRect.new()
		sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sky.show_behind_parent = true
		sky_mat = ShaderMaterial.new()
		sky_mat.shader = load("res://shaders/space_bg.gdshader")
		sky.material = sky_mat
		add_child(sky)
	else:
		grad = Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		grad.colors = PackedColorArray([Color("#1B2450"), Color("#4C6BD6"), Color("#F3C6D9")])
		grad_tex = GradientTexture2D.new()
		grad_tex.gradient = grad
		grad_tex.width = 4
		grad_tex.height = 256
		grad_tex.fill_from = Vector2(0, 0)
		grad_tex.fill_to = Vector2(0, 1)
		grad_rect = TextureRect.new()
		grad_rect.texture = grad_tex
		grad_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grad_rect.stretch_mode = TextureRect.STRETCH_SCALE
		grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grad_rect.show_behind_parent = true
		add_child(grad_rect)
	# 赛璐璐星球 / 月面：作为子节点画在天空之后、星层/行星环之前
	planet_rect = ColorRect.new()
	planet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet_rect.show_behind_parent = true
	planet_rect.visible = false
	planet_mat = ShaderMaterial.new()
	planet_mat.shader = load("res://shaders/planet_orb.gdshader")
	planet_rect.material = planet_mat
	add_child(planet_rect)
	moon_rect = ColorRect.new()
	moon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moon_rect.show_behind_parent = true
	moon_rect.visible = false
	moon_mat = ShaderMaterial.new()
	moon_mat.shader = load("res://shaders/planet_orb.gdshader")
	moon_mat.set_shader_parameter("bands", 3.0)
	moon_mat.set_shader_parameter("band_strength", 0.10)
	moon_rect.material = moon_mat
	add_child(moon_rect)
	_init_stars()
	_resize()
	_apply_palette(0, true)
	get_viewport().size_changed.connect(_resize)


func _resize() -> void:
	view_size = get_viewport_rect().size
	if sky != null:
		sky.position = Vector2.ZERO
		sky.size = view_size
	if grad_rect != null:
		grad_rect.position = Vector2.ZERO
		grad_rect.size = view_size
	if planet_rect != null:
		var pr := minf(view_size.x * 0.19, 108.0)
		planet_rect.size = Vector2(pr * 2.0, pr * 2.0)
		planet_rect.position = Vector2(view_size.x * 0.88, view_size.y * 0.105) - Vector2(pr, pr)
	if moon_rect != null:
		var mr := minf(view_size.x * 0.068, 34.0)
		moon_rect.size = Vector2(mr * 2.0, mr * 2.0)
		moon_rect.position = Vector2(view_size.x * 0.10, view_size.y * 0.205) - Vector2(mr, mr)
	queue_redraw()


func _init_stars() -> void:
	stars.clear()
	for layer in range(3):
		var count: int = [46, 34, 20][layer]
		for i in range(count):
			stars.append({
				"u": _rng.randf(),
				"v": _rng.randf(),
				"depth": [0.28, 0.55, 1.0][layer],
				"size": _rng.randf_range(0.7, 2.4) * [0.8, 1.0, 1.25][layer],
				"phase": _rng.randf() * TAU,
				"sparkle": _rng.randf() < [0.02, 0.10, 0.28][layer],
			})


func _process(delta: float) -> void:
	_time += delta
	var speed := 8.0
	var menu := true
	if main != null:
		menu = bool(main.get("in_menu"))
		if not menu:
			speed = 22.0 if not bool(main.get("paused")) else 8.0
	# 战斗时压暗天空，保证弹幕/机体对比；菜单保持明亮插画感
	var dim_target := 1.0 if menu else 0.74
	_dim = lerpf(_dim, dim_target, 1.0 - exp(-2.4 * delta))
	if sky != null:
		sky.modulate = Color(_dim * 0.98, _dim, _dim * 1.06, 1.0)
		sky_mat.set_shader_parameter("game_dim", clampf((1.0 - _dim) / 0.26, 0.0, 1.0))
	if grad_rect != null:
		grad_rect.modulate = Color(_dim * 0.98, _dim, _dim * 1.06, 1.0)
	if planet_rect != null:
		planet_rect.visible = menu
		planet_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) if menu else Color(1.0, 1.0, 1.0, 0.0)
	if moon_rect != null:
		moon_rect.visible = menu
		moon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) if menu else Color(1.0, 1.0, 1.0, 0.0)
	_scroll += delta * speed * 0.06
	for s in stars:
		s["v"] = float(s["v"]) + delta * speed * float(s["depth"]) * 0.00045
		if float(s["v"]) > 1.02:
			s["v"] = -0.02
			s["u"] = _rng.randf()
	# 星区调色板平滑过渡
	if main != null and not menu:
		var zone := clampf(float(main.get("zone")), 1.0, 10.0)
		var idx: int = ZONE_PALETTE[int(zone) - 1]
		if idx != _palette_i:
			_apply_palette(idx)
	for key in _target:
		_colors[key] = Color(_colors[key]).lerp(Color(_target[key]), 1.0 - exp(-1.8 * delta))
	_upload_colors()
	queue_redraw()


func _apply_palette(idx: int, instant := false) -> void:
	_palette_i = idx
	var p: Dictionary = PALETTES[idx]
	_target = {
		"top": Color.html(p["top"]), "mid": Color.html(p["mid"]), "bottom": Color.html(p["bottom"]),
		"neb_a": Color.html(p["neb_a"]), "neb_b": Color.html(p["neb_b"]), "glow": Color.html(p["glow"]),
	}
	if instant or _colors.is_empty():
		for k in _target:
			_colors[k] = Color(_target[k])
	_upload_colors()


func _upload_colors() -> void:
	if sky_mat == null or _colors.is_empty():
		return
	sky_mat.set_shader_parameter("top_color", _colors["top"])
	sky_mat.set_shader_parameter("mid_color", _colors["mid"])
	sky_mat.set_shader_parameter("bottom_color", _colors["bottom"])
	sky_mat.set_shader_parameter("nebula_a", _colors["neb_a"])
	sky_mat.set_shader_parameter("nebula_b", _colors["neb_b"])
	sky_mat.set_shader_parameter("glow_color", _colors["glow"])
	sky_mat.set_shader_parameter("scroll", _scroll)
	sky_mat.set_shader_parameter("time_scale", 1.0)
	if planet_mat != null:
		planet_mat.set_shader_parameter("light_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.32))
		planet_mat.set_shader_parameter("mid_col", Color(_colors["neb_b"]).lerp(Color(_colors["bottom"]), 0.28))
		planet_mat.set_shader_parameter("dark_col", Color(_colors["mid"]).darkened(0.38))
		planet_mat.set_shader_parameter("band_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.55))
		planet_mat.set_shader_parameter("rim_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.65))
		planet_mat.set_shader_parameter("ink_col", Color("#2B2338"))
	if moon_mat != null:
		moon_mat.set_shader_parameter("light_col", Color(_colors["neb_a"]).lerp(Color.WHITE, 0.42))
		moon_mat.set_shader_parameter("mid_col", Color(_colors["neb_a"]).lerp(Color.WHITE, 0.12))
		moon_mat.set_shader_parameter("dark_col", Color(_colors["neb_a"]).darkened(0.30))
		moon_mat.set_shader_parameter("band_col", Color.WHITE)
		moon_mat.set_shader_parameter("rim_col", Color.WHITE)
		moon_mat.set_shader_parameter("ink_col", Color("#2B2338"))


func _draw() -> void:
	if _colors.is_empty():
		return
	var menu := true
	if main != null:
		menu = bool(main.in_menu)
	if not use_shader:
		_draw_gradient_fallback(menu)
	else:
		_draw_stars()
	if menu:
		_draw_planet_ring(Vector2(view_size.x * 0.88, view_size.y * 0.105), minf(view_size.x * 0.19, 108.0), 0.22)


func _draw_gradient_fallback(menu: bool) -> void:
	# 渐变由 GradientTexture2D 铺底，这里只补柔光星云与星层
	_gradient_blob(Vector2(view_size.x * 0.28, view_size.y * 0.32), view_size.x * 0.72,
		Color(_colors["neb_a"]), 0.10 if menu else 0.06)
	_gradient_blob(Vector2(view_size.x * 0.78, view_size.y * 0.58), view_size.x * 0.62,
		Color(_colors["neb_b"]), 0.10 if menu else 0.05)
	_draw_stars()


func _gradient_blob(c: Vector2, r: float, col: Color, alpha: float) -> void:
	for i in range(8, 0, -1):
		var t := float(i) / 8.0
		draw_circle(c, r * t, Color(col.r, col.g, col.b, alpha / 8.0))


func _draw_stars() -> void:
	for s in stars:
		var pos := Vector2(float(s["u"]) * view_size.x, float(s["v"]) * view_size.y)
		var depth := float(s["depth"])
		var tw := 0.62 + 0.38 * sin(_time * 2.2 + float(s["phase"]))
		var col := Color(1.0, 0.97, 0.90, (0.25 + 0.75 * depth) * tw)
		if depth > 0.9:
			col = Color(1.0, 0.88, 0.94, 0.95 * tw)
		var r := float(s["size"])
		if bool(s["sparkle"]) and depth > 0.5:
			var l := r * 5.0
			draw_line(pos + Vector2(-l, 0), pos + Vector2(l, 0), Color(col.r, col.g, col.b, col.a * 0.45), 1.0)
			draw_line(pos + Vector2(0, -l), pos + Vector2(0, l), Color(col.r, col.g, col.b, col.a * 0.45), 1.0)
			draw_circle(pos, r * 1.2, col)
		else:
			draw_circle(pos, r, col)


func _draw_planet_ring(center: Vector2, radius: float, tilt: float) -> void:
	var base := Color(_colors["neb_b"]).lerp(Color(_colors["bottom"]), 0.30)
	var rim := Color(_colors["glow"]).lerp(Color.WHITE, 0.55)
	# 整圈淡环 + 下半圈高亮，形成土星环的前后层次
	draw_set_transform(center, tilt, Vector2(1.0, 0.26))
	draw_arc(Vector2.ZERO, radius * 1.46, 0, TAU, 64,
		Color(base.r, base.g, base.b, 0.34), maxf(2.0, radius * 0.030), true)
	draw_arc(Vector2.ZERO, radius * 1.56, 0, TAU, 64,
		Color(rim.r, rim.g, rim.b, 0.18), maxf(1.5, radius * 0.012), true)
	draw_arc(Vector2.ZERO, radius * 1.46, PI * 1.06, PI * 1.94, 42,
		Color(base.r, base.g, base.b, 0.82), maxf(2.0, radius * 0.042), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
