class_name UISkin
extends RefCounted

## 暗色科幻 UI 设计系统（UI 重构 Phase 1）：深空底 + 蓝青高亮 + 金色奖励 + 红色警示。
## Token 取自《UI 全面重构实施方案》；旧常量名保留为语义别名，调用方无需改名。
## 所有控件用 StyleBoxFlat 绘制，圆角/描边/投影一次缓存，避免每帧新建资源。

# ---- Design Tokens（3D 像素块 · 参考《像素飞机大战》）----
const BG_PRIMARY := Color("#1A060C")   # 暗红主背景
const BG_PANEL := Color("#2A0B12")     # 面板底
const BG_CARD := Color("#3A121A")      # 卡片/次级面板底
const ACCENT_BLUE := Color("#E8453C")  # 主高亮（出发/选中/武器）→ 樱桃红
const ACCENT_CYAN := Color("#4FD8E4")  # 次高亮（冲刺/护盾/进度）→ 天空青
const COLOR_GOLD := Color("#FFC637")   # 奖励/连击/星爆
const COLOR_DANGER := Color("#FF5A4D") # 警示/失谐/危险
const WARNING_BG := Color(0.23, 0.04, 0.05)  # Boss 预警横幅底（暗红）
const WARNING_TINT := Color(1.0, 0.69, 0.23)  # 预警箭头/强调
const WARNING_TEXT := Color(1.0, 0.95, 0.84)  # 预警副文字
const TEXT_PRIMARY := Color("#FFF3D6") # 主文字（奶油白）
const TEXT_SECONDARY := Color("#E0B49A") # 次文字（暖灰）
const BORDER := Color("#7A2A2A")       # 面板描边（暗红铜）
const BORDER_SOFT := Color("#4A1A20")  # 弱描边/分隔

# ---- Design Tokens（字号阶梯，逐屏阶段逐步采用）----
const TEXT_XS := 9
const TEXT_SM := 11
const TEXT_MD := 13
const TEXT_LG := 18
const TEXT_XL := 24
const TEXT_H1 := 34
const TEXT_H2 := 42

# ---- Design Tokens（圆角 / 间距）：像素块风格用接近直角的厚边 ----
const R_SM := 2.0
const R_MD := 4.0
const R_LG := 6.0
const SP_1 := 4.0
const SP_2 := 8.0
const SP_3 := 12.0
const SP_4 := 16.0
const SP_5 := 24.0

# ---- 语义别名（旧常量名 → 暗色 Token，保持调用方兼容）----
const INK := TEXT_PRIMARY            # 主文字（描边请显式用 BORDER）
const INK_SOFT := TEXT_SECONDARY     # 次文字
const PAPER := BG_PANEL              # 面板底
const CREAM := BG_CARD               # 卡片底
const WHITE := Color("#FFFFFF")
const PINK := ACCENT_BLUE            # 主高亮
const PINK_DEEP := Color("#FF7A45")  # 亮橙（标题/Boss 血条，暗底可读）
const CYAN := ACCENT_CYAN
const CYAN_DEEP := Color("#2E9BA8")
const GOLD := COLOR_GOLD
const GOLD_DEEP := Color("#E09A1E")
const VIOLET := Color("#8A6BE0")
const VIOLET_DEEP := Color("#5B47B0")
const RED := COLOR_DANGER
const BLUE := Color("#3D6BE0")

var font: Font
var _styles := {}


func _init(p_font: Font = null) -> void:
	font = p_font if p_font != null else ThemeDB.fallback_font


func panel_style(fill: Color, radius := R_MD, border := BORDER, border_w := 2.0,
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
		sb.shadow_color = Color(BG_PRIMARY.r, BG_PRIMARY.g, BG_PRIMARY.b, 0.45)
		sb.shadow_size = 5
		sb.shadow_offset = Vector2(0, 5)
	_styles[key] = sb
	return sb


func panel(ci: CanvasItem, rect: Rect2, fill: Color, radius := R_MD, border := BORDER,
		border_w := 3.0, shadow := true) -> void:
	ci.draw_style_box(panel_style(fill, radius, border, border_w, shadow), rect)


func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	if outline > 0:
		var o := float(outline)
		for d in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o),
				Vector2(-o * 0.7, -o * 0.7), Vector2(o * 0.7, -o * 0.7),
				Vector2(-o * 0.7, o * 0.7), Vector2(o * 0.7, o * 0.7)]:
			ci.draw_string(font, pos + d, s, align, width, size, BG_PRIMARY)
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
	panel(ci, r, fill, R_LG, BORDER, 3.0, not pressed)
	# 顶部高光条与底部内阴影
	var hi := Color(1, 1, 1, 0.30) if not pressed else Color(1, 1, 1, 0.14)
	ci.draw_rect(Rect2(r.position + Vector2(14, 9), Vector2(r.size.x - 28, 3)), hi)
	ci.draw_rect(Rect2(r.position + Vector2(14, r.size.y - 8), Vector2(r.size.x - 28, 3)),
		Color(BG_PRIMARY.r, BG_PRIMARY.g, BG_PRIMARY.b, 0.30))
	text_center(ci, r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + size * 0.36,
		label, size, text_color, 0)


func keycap(ci: CanvasItem, rect: Rect2, label: String, size := 12) -> void:
	panel(ci, rect, CREAM, 7.0, BORDER, 2.0, false)
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


func icon_gear(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 0.55, c + d * r, color, r * 0.34)
	ci.draw_circle(c, r * 0.62, color)
	ci.draw_circle(c, r * 0.26, PAPER)


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


func edge_flash(ci: CanvasItem, vw: float, vh: float, col: Color, k: float,
		depth := 56.0) -> void:
	## 纯视觉事件反馈：四边渐变晕光（受击红闪 / 护盾青闪），不触碰判定。
	## draw_colored_polygon 不支持逐顶点色，用多层二次衰减色带模拟渐变。
	if k <= 0.0:
		return
	var a := clampf(k, 0.0, 1.0) * 0.5
	var bands := 12
	var bw := depth / float(bands)
	for i in range(bands):
		var f := 1.0 - float(i) / float(bands)
		var c := Color(col.r, col.g, col.b, a * f * f)
		var o := float(i) * bw
		ci.draw_rect(Rect2(0, o, vw, bw + 1.0), c)
		ci.draw_rect(Rect2(0, vh - o - bw - 1.0, vw, bw + 1.0), c)
		ci.draw_rect(Rect2(o, 0, bw + 1.0, vh), c)
		ci.draw_rect(Rect2(vw - o - bw - 1.0, 0, bw + 1.0, vh), c)


func halftone(ci: CanvasItem, rect: Rect2, color: Color, spacing := 14.0) -> void:
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x + (spacing * 0.5 if int(y / spacing) % 2 == 0 else 0.0)
		while x < rect.end.x:
			ci.draw_circle(Vector2(x, y), 1.6, color)
			x += spacing
		y += spacing