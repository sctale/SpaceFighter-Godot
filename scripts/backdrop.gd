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
		_draw_planet(Vector2(view_size.x * 0.88, view_size.y * 0.105), minf(view_size.x * 0.19, 108.0), 0.22)
		_draw_moon(Vector2(view_size.x * 0.10, view_size.y * 0.205), minf(view_size.x * 0.068, 34.0))


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


func _draw_planet(center: Vector2, radius: float, tilt: float) -> void:
	var base := Color(_colors["neb_b"]).lerp(Color(_colors["bottom"]), 0.30)
	var shadow := Color(_colors["mid"]).darkened(0.30)
	var rim := Color(_colors["glow"]).lerp(Color.WHITE, 0.55)
	# 柔光 + 后方半环
	glow_blob(center, radius * 1.55, Color(rim.r, rim.g, rim.b, 0.18), 8)
	draw_set_transform(center, tilt, Vector2(1.0, 0.26))
	draw_arc(Vector2.ZERO, radius * 1.45, PI * 0.10, PI * 0.90, 40,
		Color(base.r, base.g, base.b, 0.28), maxf(2.0, radius * 0.028), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 球体 + 纬向云带
	draw_circle(center, radius, base)
	draw_set_transform(center, 0.0, Vector2(1.0, 0.28))
	for i in range(3):
		var yy := -radius * 0.34 + i * radius * 0.26
		var rr := radius * (0.92 - i * 0.08)
		draw_arc(Vector2(0, yy), rr, 0.0, TAU, 48, Color(1, 1, 1, 0.10),
			maxf(2.0, radius * 0.07), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 硬边半圆阴影：动画赛璐璐的大色块
	var shadow_dir := Vector2(-0.30, 0.95).normalized()
	var start := shadow_dir.angle() - PI * 0.5
	var pts := PackedVector2Array()
	for i in range(33):
		var a := start + PI * float(i) / 32.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius * 0.985)
	draw_colored_polygon(pts, Color(shadow.r, shadow.g, shadow.b, 0.72))
	# 亮侧边缘 + 前后半环
	draw_arc(center, radius * 0.98, PI * 0.98, PI * 1.72, 40,
		Color(rim.r, rim.g, rim.b, 0.55), maxf(1.5, radius * 0.022), true)
	draw_set_transform(center, tilt, Vector2(1.0, 0.26))
	draw_arc(Vector2.ZERO, radius * 1.45, PI * 1.08, PI * 1.92, 40,
		Color(base.r, base.g, base.b, 0.72), maxf(2.0, radius * 0.032), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_moon(center: Vector2, radius: float) -> void:
	var c := Color(_colors["neb_a"]).lerp(Color.WHITE, 0.38)
	var sh := c.darkened(0.26)
	glow_blob(center, radius * 1.6, Color(c.r, c.g, c.b, 0.16), 6)
	draw_circle(center, radius, c)
	var start := 0.35
	var pts := PackedVector2Array()
	for i in range(25):
		var a := start + PI * float(i) / 24.0
		pts.append(center + Vector2(cos(a), sin(a)) * radius * 0.97)
	draw_colored_polygon(pts, Color(sh.r, sh.g, sh.b, 0.62))
	draw_arc(center, radius * 0.95, PI * 1.0, PI * 1.7, 24, Color(1, 1, 1, 0.42), 1.5, true)


func glow_blob(center: Vector2, radius: float, col: Color, layers: int) -> void:
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		draw_circle(center, radius * t, Color(col.r, col.g, col.b, col.a / float(layers)))
