class_name FXLayer
extends Node2D

## 轻量粒子/拖尾层：火花、碎片、冲击环、拾取文字。全部用 draw 原语，
## 不建节点、不依赖纹理，弹幕多时也不会掉帧。加法混合让亮色更像动画特效。

const MAX_PARTS := 420
const MAX_TEXTS := 40

var font: Font
var parts: Array = []
var texts: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_as_relative = false
	z_index = 100
	_rng.seed = 90210
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


## 粒子数量上限：星爆/连爆叠在一起时丢弃最旧的，避免单帧绘制量失控。
func _push(p: Dictionary) -> void:
	if parts.size() >= MAX_PARTS:
		parts.pop_front()
	parts.append(p)


func _push_text(tx: Dictionary) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()
	texts.append(tx)


func _process(delta: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p["life"] = float(p["life"]) - delta
		if float(p["life"]) <= 0.0:
			parts.remove_at(i)
			continue
		p["pos"] = Vector2(p["pos"]) + Vector2(p["vel"]) * delta
		p["vel"] = Vector2(p["vel"]) * (1.0 - 2.4 * delta)
		if p.has("spin"):
			p["rot"] = float(p["rot"]) + float(p["spin"]) * delta
		if p.has("grow"):
			p["radius"] = float(p["radius"]) + float(p["grow"]) * delta
	for i in range(texts.size() - 1, -1, -1):
		var tx: Dictionary = texts[i]
		tx["life"] = float(tx["life"]) - delta
		if float(tx["life"]) <= 0.0:
			texts.remove_at(i)
			continue
		tx["pos"] = Vector2(tx["pos"]) + Vector2(0, -34.0 * delta)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k := clampf(float(p["life"]) / float(p["max_life"]), 0.0, 1.0)
		var pos := Vector2(p["pos"])
		var col := Color(p["color"])
		col.a *= k
		match String(p["kind"]):
			"spark":
				var tail := pos - Vector2(p["vel"]) * 0.045
				draw_line(tail, pos, col, float(p.get("w", 2.0)), true)
			"shard":
				var s := float(p["size"]) * (0.55 + k * 0.8)
				var rot := float(p.get("rot", 0.0))
				var pts := PackedVector2Array([
					pos + Vector2(0, -s).rotated(rot),
					pos + Vector2(s * 0.55, s * 0.6).rotated(rot),
					pos + Vector2(-s * 0.55, s * 0.6).rotated(rot),
				])
				draw_colored_polygon(pts, col)
			"ring":
				draw_arc(pos, float(p["radius"]), 0, TAU, 48, col, float(p.get("w", 3.0)), true)
			"flash":
				draw_circle(pos, float(p["radius"]) * (0.7 + (1.0 - k) * 0.6), col)
			"dot":
				draw_circle(pos, float(p["size"]) * (0.4 + k * 0.9), col)
	for tx in texts:
		var a := clampf(float(tx["life"]) / float(tx["max_life"]), 0.0, 1.0)
		var c := Color(tx["color"])
		c.a = a
		var s := String(tx["text"])
		var sz := int(tx.get("size", 16))
		var tp := Vector2(tx["pos"])
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(font, tp + Vector2(-w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
			Color(0.12, 0.08, 0.18, a))
		draw_string(font, tp + Vector2(-w * 0.5, -2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)


func explode(pos: Vector2, color: Color, size: float, heavy := false) -> void:
	var n := 9 if not heavy else 16
	for i in range(n):
		var a := _rng.randf() * TAU
		var sp := _rng.randf_range(90.0, 260.0) * (1.3 if heavy else 1.0)
		_push({
			"kind": "shard" if i % 3 != 0 else "spark", "pos": pos,
			"vel": Vector2(cos(a), sin(a)) * sp,
			"life": _rng.randf_range(0.35, 0.70), "max_life": 0.70,
			"size": size * _rng.randf_range(0.16, 0.34),
			"color": color if i % 4 != 0 else Color(1, 1, 1, 0.9),
			"rot": a, "spin": _rng.randf_range(-9.0, 9.0), "w": 2.5 if i % 3 == 0 else 1.0,
		})
	_push({"kind": "ring", "pos": pos, "vel": Vector2.ZERO, "radius": size * 0.35,
		"grow": size * 2.4, "life": 0.38, "max_life": 0.38, "color": color, "w": 3.5 if heavy else 2.5})
	_push({"kind": "flash", "pos": pos, "vel": Vector2.ZERO, "radius": size * 0.9,
		"life": 0.14, "max_life": 0.14, "color": Color(1, 1, 1, 0.85)})


func hit(pos: Vector2, color: Color) -> void:
	_push({"kind": "flash", "pos": pos, "vel": Vector2.ZERO, "radius": 10.0,
		"life": 0.10, "max_life": 0.10, "color": Color(1, 1, 1, 0.75)})
	for i in range(4):
		var a := _rng.randf() * TAU
		_push({"kind": "spark", "pos": pos,
			"vel": Vector2(cos(a), sin(a)) * _rng.randf_range(120.0, 300.0),
			"life": _rng.randf_range(0.12, 0.24), "max_life": 0.24,
			"color": color, "w": 1.8})


func pickup(pos: Vector2, color: Color, label: String) -> void:
	_push({"kind": "ring", "pos": pos, "vel": Vector2.ZERO, "radius": 6.0,
		"grow": 90.0, "life": 0.34, "max_life": 0.34, "color": color, "w": 2.0})
	for i in range(8):
		var a := _rng.randf() * TAU
		_push({"kind": "spark", "pos": pos,
			"vel": Vector2(cos(a), sin(a)) * _rng.randf_range(80.0, 210.0),
			"life": 0.36, "max_life": 0.36, "color": color, "w": 2.0})
	if label != "":
		float_text(pos + Vector2(0, -26), label, color)


func nova(pos: Vector2) -> void:
	for i in range(3):
		_push({"kind": "ring", "pos": pos, "vel": Vector2.ZERO, "radius": 40.0 + i * 24.0,
			"grow": 520.0, "life": 0.55 + i * 0.12, "max_life": 0.55 + i * 0.12,
			"color": Color(1.0, 0.92, 0.55, 0.9), "w": 4.0 - i})
	_push({"kind": "flash", "pos": pos, "vel": Vector2.ZERO, "radius": 120.0,
		"life": 0.20, "max_life": 0.20, "color": Color(1, 1, 1, 0.6)})
	for i in range(24):
		var a := _rng.randf() * TAU
		_push({"kind": "spark", "pos": pos,
			"vel": Vector2(cos(a), sin(a)) * _rng.randf_range(260.0, 640.0),
			"life": _rng.randf_range(0.3, 0.6), "max_life": 0.6,
			"color": Color(1.0, 0.85, 0.45), "w": 3.0})


func dash(pos: Vector2, dir: Vector2, color: Color) -> void:
	for i in range(5):
		_push({"kind": "shard", "pos": pos - dir * (i * 12.0),
			"vel": -dir * 80.0, "life": 0.22 + i * 0.03, "max_life": 0.35,
			"size": 16.0 - i * 2.0, "color": color, "rot": dir.angle() + PI * 0.5,
			"spin": 0.0})


func float_text(pos: Vector2, label: String, color: Color, size := 16) -> void:
	_push_text({"pos": pos, "life": 0.85, "max_life": 0.85, "text": label,
		"color": color, "size": size})
