class_name UISkin
extends RefCounted

## 日系贴纸风 UI 调色板与绘制原语：奶油纸面 + 深梅描边 + 糖果色高光。
## 所有控件用 StyleBoxFlat 绘制，圆角/描边/投影一次缓存，避免每帧新建资源。

const INK := Color("#2B2338")
const INK_SOFT := Color("#4A435E")
const PAPER := Color("#FFF8EC")
const CREAM := Color("#FFF1DC")
const WHITE := Color("#FFFFFF")
const PINK := Color("#FF8FB1")
const PINK_DEEP := Color("#F0557F")
const CYAN := Color("#57E6D8")
const CYAN_DEEP := Color("#14A79E")
const GOLD := Color("#FFC554")
const GOLD_DEEP := Color("#E69B2D")
const VIOLET := Color("#A78BFA")
const VIOLET_DEEP := Color("#6C55D6")
const RED := Color("#FF6B7A")
const BLUE := Color("#6FA8FF")

var font: Font
var _styles := {}


func _init(p_font: Font = null) -> void:
	font = p_font if p_font != null else ThemeDB.fallback_font


func panel_style(fill: Color, radius := 18.0, border := INK, border_w := 3.0,
		shadow := true) -> StyleBoxFlat:
	var key := "%s|%s|%s|%s|%s" % [fill.to_html(), radius, border.to_html(), border_w, shadow]
	if _styles.has(key):
		return _styles[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(round(border_w)))
	sb.set_corner_radius_all(int(round(radius)))
	sb.anti_aliasing = true
	if shadow:
		sb.shadow_color = Color(INK.r, INK.g, INK.b, 0.24)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 5)
	_styles[key] = sb
	return sb


func panel(ci: CanvasItem, rect: Rect2, fill: Color, radius := 18.0, border := INK,
		border_w := 3.0, shadow := true) -> void:
	ci.draw_style_box(panel_style(fill, radius, border, border_w, shadow), rect)


func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	if outline > 0:
		var o := float(outline)
		for d in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o),
				Vector2(-o * 0.7, -o * 0.7), Vector2(o * 0.7, -o * 0.7),
				Vector2(-o * 0.7, o * 0.7), Vector2(o * 0.7, o * 0.7)]:
			ci.draw_string(font, pos + d, s, align, width, size, INK)
	ci.draw_string(font, pos, s, align, width, size, color)


func text_center(ci: CanvasItem, center_x: float, baseline_y: float, s: String,
		size: int, color: Color, outline := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(ci, Vector2(center_x - w * 0.5, baseline_y), s, size, color, HORIZONTAL_ALIGNMENT_LEFT, -1, outline)


func text_right(ci: CanvasItem, right_x: float, baseline_y: float, s: String,
		size: int, color: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	text(ci, Vector2(right_x - w, baseline_y), s, size, color)


func button(ci: CanvasItem, rect: Rect2, label: String, fill: Color,
		pressed := false, size := 22, text_color := WHITE) -> void:
	var r := rect
	if pressed:
		r.position.y += 3.0
	panel(ci, r, fill, 18.0, INK, 3.0, not pressed)
	# 顶部高光条与底部内阴影
	var hi := Color(1, 1, 1, 0.35) if not pressed else Color(1, 1, 1, 0.18)
	ci.draw_rect(Rect2(r.position + Vector2(14, 9), Vector2(r.size.x - 28, 3)), hi)
	ci.draw_rect(Rect2(r.position + Vector2(14, r.size.y - 8), Vector2(r.size.x - 28, 3)),
		Color(INK.r, INK.g, INK.b, 0.20))
	text_center(ci, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + size * 0.36,
		label, size, text_color, 0)


func keycap(ci: CanvasItem, rect: Rect2, label: String, size := 12) -> void:
	panel(ci, rect, CREAM, 7.0, INK, 2.0, false)
	text_center(ci, rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5 + size * 0.36,
		label, size, INK)


func star_points(c: Vector2, r: float, inner: float, points := 5, rot := -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var a := rot + PI * float(i) / float(points)
		var rr := r if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


func icon_star(ci: CanvasItem, c: Vector2, r: float, color: Color, points := 5) -> void:
	ci.draw_colored_polygon(star_points(c, r, r * 0.44, points), color)


func icon_burst(ci: CanvasItem, c: Vector2, r: float, color: Color, points := 8) -> void:
	ci.draw_colored_polygon(star_points(c, r, r * 0.22, points, -PI * 0.5), color)


func icon_ship(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -r), c + Vector2(r * 0.55, r * 0.45),
		c + Vector2(0, r * 0.18), c + Vector2(-r * 0.55, r * 0.45),
	])
	ci.draw_colored_polygon(pts, color)


func icon_shield(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.62, -r * 0.62), c + Vector2(r * 0.62, -r * 0.62),
		c + Vector2(r * 0.52, r * 0.28), c + Vector2(0, r * 0.78),
		c + Vector2(-r * 0.52, r * 0.28),
	])
	ci.draw_colored_polygon(pts, color)


func icon_heart(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.34, -r * 0.24), r * 0.46, color)
	ci.draw_circle(c + Vector2(r * 0.34, -r * 0.24), r * 0.46, color)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.74, -r * 0.02), c + Vector2(r * 0.74, -r * 0.02),
		c + Vector2(0, r * 0.80),
	])
	ci.draw_colored_polygon(pts, color)


func icon_pause(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(-r * 0.42, -r * 0.55), Vector2(r * 0.30, r * 1.10)), color)
	ci.draw_rect(Rect2(c + Vector2(r * 0.12, -r * 0.55), Vector2(r * 0.30, r * 1.10)), color)


func icon_play(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.35, -r * 0.55), c + Vector2(r * 0.60, 0), c + Vector2(-r * 0.35, r * 0.55),
	])
	ci.draw_colored_polygon(pts, color)


func icon_chevron(ci: CanvasItem, c: Vector2, r: float, color: Color, dir := 1.0) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.22 * dir, -r * 0.55), c + Vector2(r * 0.34 * dir, 0),
		c + Vector2(-r * 0.22 * dir, r * 0.55), c + Vector2(-r * 0.52 * dir, r * 0.36),
		c + Vector2(0, 0), c + Vector2(-r * 0.52 * dir, -r * 0.36),
	])
	ci.draw_colored_polygon(pts, color)


func icon_crossed(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_line(c + Vector2(-r * 0.75, -r * 0.75), c + Vector2(r * 0.75, r * 0.75), color, r * 0.20)
	ci.draw_line(c + Vector2(r * 0.75, -r * 0.75), c + Vector2(-r * 0.75, r * 0.75), color, r * 0.20)


func sparkle(ci: CanvasItem, c: Vector2, r: float, color: Color, t: float) -> void:
	var k := 0.6 + 0.4 * sin(t * 2.0)
	ci.draw_line(c + Vector2(-r * k, 0), c + Vector2(r * k, 0), Color(color.r, color.g, color.b, color.a * 0.6), 1.5)
	ci.draw_line(c + Vector2(0, -r * k), c + Vector2(0, r * k), Color(color.r, color.g, color.b, color.a * 0.6), 1.5)
	ci.draw_circle(c, r * 0.22, color)


func glow(ci: CanvasItem, c: Vector2, r: float, color: Color, layers := 6, alpha := 0.18) -> void:
	for i in range(layers, 0, -1):
		var t := float(i) / float(layers)
		ci.draw_circle(c, r * t, Color(color.r, color.g, color.b, alpha / float(layers)))


func halftone(ci: CanvasItem, rect: Rect2, color: Color, spacing := 14.0) -> void:
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x + (spacing * 0.5 if int(y / spacing) % 2 == 0 else 0.0)
		while x < rect.end.x:
			ci.draw_circle(Vector2(x, y), 1.6, color)
			x += spacing
		y += spacing
