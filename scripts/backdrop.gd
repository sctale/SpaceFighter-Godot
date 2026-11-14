class_name SpaceBackdrop
extends Node2D

## 全屏自适应深空背景：程序化星云 shader + 三层视差星 + 赛璐璐星球/月面。
## 不占用预渲染贴图，540x960 / 540x1200 / 720x960 都能铺满。

## 五套关卡主题（参考《像素飞机大战》）：白昼天空 / 黄昏 / 深蓝太空 / 暗红工业 / 翡翠星云。
## cloud 控制像素云覆盖率，stars 控制星点亮度。
const PALETTES := [
	{"top": "#0E3560", "mid": "#1F639B", "bottom": "#58A6D2",
	 "neb_a": "#FFF3D6", "neb_b": "#FFE9BE", "glow": "#FFF6E0",
	 "cloud": 0.44, "stars": 0.0, "dim": 0.70, "terrain": 1.0},
	{"top": "#3D1030", "mid": "#7A2438", "bottom": "#C25A2E",
	 "neb_a": "#FFC66B", "neb_b": "#FF9AA8", "glow": "#FFE9C0",
	 "cloud": 0.38, "stars": 0.0, "dim": 0.74, "terrain": 0.8},
	{"top": "#0A0F2A", "mid": "#14224A", "bottom": "#1F3468",
	 "neb_a": "#3D6BE0", "neb_b": "#5FE0E8", "glow": "#EAF6FF",
	 "cloud": 0.10, "stars": 1.0, "dim": 0.92},
	{"top": "#1E060C", "mid": "#3A0D14", "bottom": "#58181C",
	 "neb_a": "#C22C2C", "neb_b": "#FF8A3D", "glow": "#FFD9A0",
	 "cloud": 0.24, "stars": 0.35, "dim": 0.90},
	{"top": "#07180F", "mid": "#0F3324", "bottom": "#174A33",
	 "neb_a": "#4FCB5E", "neb_b": "#5FE0E8", "glow": "#EFFFE0",
	 "cloud": 0.12, "stars": 0.9, "dim": 0.90},
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
var rain: Array = []
var use_shader := true

# 动态天气（参考《像素飞机大战》的云/闪电/雷雨）：clear / rain / storm
var weather := "clear"
var _weather_mix := 0.0
var _flash := 0.0
var _flash_cd := 2.6

var _time := 0.0
var _scroll := 0.0
var _dim := 1.0
var _palette_i := 0
var _colors := {}
var _target := {}
var _cloud := 0.9
var _cloud_target := 0.9
var _stars_k := 0.0
var _stars_target := 0.0
var _dim_target := 0.9
var _terrain_k := 0.0
var _terrain_target := 0.0
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
		grad.colors = PackedColorArray([Color("#1E5FA8"), Color("#3E8FD0"), Color("#8FD3EE")])
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
	_init_rain()
	_resize()
	_apply_palette(0, true)
	get_viewport().size_changed.connect(_resize)


## 天候切换：rain=雨丝，storm=雨丝+闪电白光。由 Main 按星区调用。
func set_weather(w: String) -> void:
	if w == weather:
		return
	weather = w
	if weather == "clear":
		_flash = 0.0
	else:
		_flash_cd = 1.2


func _init_rain() -> void:
	rain.clear()
	for i in range(84):
		rain.append({
			"u": _rng.randf(),
			"v": _rng.randf(),
			"speed": _rng.randf_range(0.55, 1.35),
			"len": _rng.randf_range(12.0, 30.0),
			"alpha": _rng.randf_range(0.16, 0.44),
		})


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
	# 战斗时轻微压暗天空，保证弹幕/机体对比；参考作本身是高饱和亮背景，不再大幅压暗
	var dim_target := 1.0 if menu else _dim_target
	_dim = lerpf(_dim, dim_target, 1.0 - exp(-2.4 * delta))
	if sky != null:
		sky.modulate = Color(_dim, _dim, _dim, 1.0)
		sky_mat.set_shader_parameter("game_dim", clampf((1.0 - _dim) / 0.26, 0.0, 1.0))
	if grad_rect != null:
		grad_rect.modulate = Color(_dim, _dim, _dim, 1.0)
	# 天空主题不显示星球/卫星（参考作为云海+岛屿构图）
	var show_orbs: bool = menu and _terrain_target < 0.5
	if planet_rect != null:
		planet_rect.visible = show_orbs
		planet_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) if show_orbs else Color(1.0, 1.0, 1.0, 0.0)
	if moon_rect != null:
		moon_rect.visible = show_orbs
		moon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) if show_orbs else Color(1.0, 1.0, 1.0, 0.0)
	_scroll += delta * speed * 0.06
	for s in stars:
		s["v"] = float(s["v"]) + delta * speed * float(s["depth"]) * 0.00045
		if float(s["v"]) > 1.02:
			s["v"] = -0.02
			s["u"] = _rng.randf()
	# 天气：雨丝下落、雷暴间歇闪光
	var wet := 1.0 if weather != "clear" else 0.0
	_weather_mix = lerpf(_weather_mix, wet, 1.0 - exp(-1.6 * delta))
	if _weather_mix > 0.01:
		for d in rain:
			d["v"] = float(d["v"]) + delta * float(d["speed"]) * 0.85
			if float(d["v"]) > 1.03:
				d["v"] = -0.03
				d["u"] = _rng.randf()
	if weather == "storm":
		_flash_cd -= delta
		if _flash_cd <= 0.0:
			_flash = 1.0
			_flash_cd = _rng.randf_range(2.4, 5.2)
	_flash = maxf(0.0, _flash - delta * 3.4)
	# 星区调色板平滑过渡；无尽模式星区超过 10 后循环调色板
	if main != null and not menu:
		var idx: int = ZONE_PALETTE[(maxi(1, int(main.get("zone"))) - 1) % 10]
		if idx != _palette_i:
			_apply_palette(idx)
		var w := String(main.weather_for_zone(int(main.get("zone"))))
		if w != weather:
			set_weather(w)
	elif menu:
		set_weather("clear")
	for key in _target:
		_colors[key] = Color(_colors[key]).lerp(Color(_target[key]), 1.0 - exp(-1.8 * delta))
	_cloud = lerpf(_cloud, _cloud_target, 1.0 - exp(-1.8 * delta))
	_stars_k = lerpf(_stars_k, _stars_target, 1.0 - exp(-1.8 * delta))
	_terrain_k = lerpf(_terrain_k, _terrain_target, 1.0 - exp(-1.8 * delta))
	_upload_colors()
	queue_redraw()


func _apply_palette(idx: int, instant := false) -> void:
	_palette_i = idx
	var p: Dictionary = PALETTES[idx]
	_target = {
		"top": Color.html(p["top"]), "mid": Color.html(p["mid"]), "bottom": Color.html(p["bottom"]),
		"neb_a": Color.html(p["neb_a"]), "neb_b": Color.html(p["neb_b"]), "glow": Color.html(p["glow"]),
	}
	_cloud_target = float(p.get("cloud", 0.0))
	_stars_target = float(p.get("stars", 1.0))
	_dim_target = float(p.get("dim", 0.9))
	_terrain_target = float(p.get("terrain", 0.0))
	if instant or _colors.is_empty():
		for k in _target:
			_colors[k] = Color(_target[k])
		_cloud = _cloud_target
		_stars_k = _stars_target
		_terrain_k = _terrain_target
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
	sky_mat.set_shader_parameter("cloud_cover", _cloud)
	if planet_mat != null:
		planet_mat.set_shader_parameter("light_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.32))
		planet_mat.set_shader_parameter("mid_col", Color(_colors["neb_b"]).lerp(Color(_colors["bottom"]), 0.28))
		planet_mat.set_shader_parameter("dark_col", Color(_colors["mid"]).darkened(0.38))
		planet_mat.set_shader_parameter("band_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.55))
		planet_mat.set_shader_parameter("rim_col", Color(_colors["glow"]).lerp(Color.WHITE, 0.65))
		planet_mat.set_shader_parameter("ink_col", Color("#3A1520"))
	if moon_mat != null:
		moon_mat.set_shader_parameter("light_col", Color(_colors["neb_a"]).lerp(Color.WHITE, 0.42))
		moon_mat.set_shader_parameter("mid_col", Color(_colors["neb_a"]).lerp(Color.WHITE, 0.12))
		moon_mat.set_shader_parameter("dark_col", Color(_colors["neb_a"]).darkened(0.30))
		moon_mat.set_shader_parameter("band_col", Color.WHITE)
		moon_mat.set_shader_parameter("rim_col", Color.WHITE)
		moon_mat.set_shader_parameter("ink_col", Color("#3A1520"))


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
	# 天空主题（有岛屿层）不画星球，避免与参考作的"云海+岛屿"构图冲突
	if menu and _terrain_target < 0.5:
		_draw_planet_ring(Vector2(view_size.x * 0.88, view_size.y * 0.105), minf(view_size.x * 0.19, 108.0), 0.22)
	_draw_terrain()
	_draw_weather()


## 天空关卡的像素岛屿剪影（参考《像素飞机大战》的地面/岛屿层），底部两层视差。
func _draw_terrain() -> void:
	if _terrain_k <= 0.02:
		return
	var vh := view_size.y
	for layer in range(2):
		var a := _terrain_k * (0.85 if layer == 0 else 0.62)
		var col := Color(0.10, 0.28, 0.22, a) if layer == 0 else Color(0.05, 0.17, 0.15, a)
		var pts := PackedVector2Array()
		pts.append(Vector2(0, vh))
		var step := 12.0
		var x := 0.0
		while x <= view_size.x + step:
			var phase := (x + _scroll * 26.0 * float(layer + 1)) * 0.018
			var h := 24.0 + sin(phase) * 15.0 + sin(phase * 2.6 + 1.7) * 7.0 + float(layer) * 18.0
			pts.append(Vector2(x, vh - 2.0 - h))
			x += step
		pts.append(Vector2(view_size.x, vh))
		draw_colored_polygon(pts, col)


## 雨丝与雷暴闪光：像素风短线段，风暴时追加一次全屏白光。
func _draw_weather() -> void:
	if _weather_mix <= 0.01:
		return
	var tint := 0.80 if weather == "storm" else 0.60
	for d in rain:
		var p := Vector2(float(d["u"]) * view_size.x, float(d["v"]) * view_size.y)
		var l := float(d["len"]) * _weather_mix
		draw_line(p, p + Vector2(-l * 0.34, l), Color(0.72, 0.86, 1.0, float(d["alpha"]) * tint), 1.0)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.86, 0.92, 1.0, _flash * 0.30))


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
	if _stars_k <= 0.02:
		return
	for s in stars:
		var pos := Vector2(float(s["u"]) * view_size.x, float(s["v"]) * view_size.y)
		var depth := float(s["depth"])
		var tw := 0.62 + 0.38 * sin(_time * 2.2 + float(s["phase"]))
		var col := Color(1.0, 0.97, 0.90, (0.25 + 0.75 * depth) * tw * _stars_k)
		if depth > 0.9:
			col = Color(1.0, 0.88, 0.94, 0.95 * tw * _stars_k)
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
