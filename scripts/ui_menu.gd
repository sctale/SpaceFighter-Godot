class_name UIMenu
extends RefCounted

## 主菜单：奶油贴纸标题 + 大尺寸 Hero 机体 + 三档难度胶囊 + 大号出发按钮。
## 布局全部按视口比例计算，长屏/平板会自动拉开间距。

const ZONE_NAMES := ["裂隙入口", "星云回廊", "静默空域", "熔星带", "镜面深空",
	"花火云", "冰晶环", "赤色风暴", "翡翠墓园", "终焉之门"]


static func draw(ci: CanvasItem, skin: UISkin, main: Node, vw: float, vh: float,
		safe_top: float, safe_bottom: float, t: float) -> Dictionary:
	var rects := {}
	var w := minf(vw - 64.0, 460.0)
	var cx := vw * 0.5
	var hero_size := minf(minf(vw * 0.64, vh * 0.28), 330.0)
	var hero_c := Vector2(cx, safe_top + vh * 0.140)
	var title_y := safe_top + vh * 0.345
	var best_y := safe_top + vh * 0.525
	var diff_y := safe_top + vh * 0.610
	var start_y := safe_top + vh * 0.705
	var hint_y := safe_top + vh * 0.850

	# Hero 机体：轻微上下浮动 + 光晕 + 环绕轨道
	var bob := sin(t * 1.15) * 7.0
	skin.glow(ci, hero_c + Vector2(0, bob), hero_size * 0.52, Color("#FFE8F2"), 7, 0.26)
	ci.draw_arc(hero_c + Vector2(0, bob), hero_size * 0.50, t * 0.35, t * 0.35 + PI * 1.35, 48,
		Color(1, 1, 1, 0.20), 2.0, true)
	ci.draw_arc(hero_c + Vector2(0, bob), hero_size * 0.58, -t * 0.24, -t * 0.24 + PI * 0.9, 40,
		Color(1, 1, 1, 0.12), 1.5, true)
	var hero_tex: Texture2D = main._keyart_tex("hero")
	if hero_tex == null:
		hero_tex = main._ship_tex("player_pulse")
	if hero_tex != null:
		ci.draw_set_transform(hero_c + Vector2(0, bob), sin(t * 0.75) * 0.022, Vector2.ONE)
		ci.draw_texture_rect(hero_tex, Rect2(-hero_size * 0.5, -hero_size * 0.5, hero_size, hero_size),
			false, Color.WHITE)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(6):
		var a := t * 0.8 + i * TAU / 6.0
		var p := hero_c + Vector2(cos(a), sin(a) * 0.42) * (hero_size * 0.55)
		skin.sparkle(ci, p, 7.0, Color(1.0, 0.93, 0.75, 0.8), t + i)

	# 标题贴纸：优先使用 Blender 渲的 3D Logo，缺图时回退到文字
	var title_c := Vector2(cx, title_y)
	var logo_tex: Texture2D = main._keyart_tex("logo")
	ci.draw_set_transform(title_c + Vector2(2, 6), -0.018, Vector2.ONE)
	skin.panel(ci, Rect2(-190, -77, 380, 154), skin.PAPER, 22.0, skin.INK, 3.5, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_set_transform(title_c, -0.018, Vector2.ONE)
	if logo_tex != null:
		ci.draw_texture_rect(logo_tex, Rect2(-180, -90, 360, 180), false, Color.WHITE)
	else:
		ci.draw_rect(Rect2(-162, -56, 324, 3), Color(skin.PINK.r, skin.PINK.g, skin.PINK.b, 0.55))
		skin.text_center(ci, 0, 16, "裂隙巡航", 52, skin.INK, 0)
		skin.text_center(ci, 0, 36, "A U R O R A   R I F T", 12, skin.PINK_DEEP, 0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	skin.sparkle(ci, title_c + Vector2(-212, -12), 13.0, Color(1, 0.95, 0.78), t)
	skin.sparkle(ci, title_c + Vector2(214, 6), 10.0, Color(1, 0.95, 0.78), t + 1.2)

	# 最高分
	var best_rect := Rect2(cx - 138.0, best_y - 86.0, 276.0, 54.0)
	skin.panel(ci, best_rect, skin.CREAM, 16.0, skin.INK, 3.0, true)
	skin.icon_star(ci, best_rect.position + Vector2(28, 27), 11.0, skin.GOLD)
	skin.text(ci, best_rect.position + Vector2(48, 35), "最高分", 14, skin.INK_SOFT)
	skin.text_right(ci, best_rect.end.x - 18.0, best_rect.position.y + 37.0,
		"%d" % int(main.best_score), 24, skin.INK)

	# 难度胶囊
	var names := ["巡航", "标准", "深渊"]
	var keys := ["cruise", "standard", "abyss"]
	var tints := [skin.CYAN, skin.PINK, skin.VIOLET]
	var icons := ["ship", "star", "burst"]
	var gap := 10.0
	var chip_w := (w - gap * 2.0) / 3.0
	for i in range(3):
		var r := Rect2(cx - w * 0.5 + i * (chip_w + gap), diff_y - 92.0, chip_w, 56.0)
		rects[keys[i]] = r
		var on: bool = String(main.difficulty) == keys[i]
		var fill: Color = tints[i] if on else skin.PAPER
		skin.panel(ci, r, fill, 16.0, skin.INK, 3.0, not on)
		if on:
			ci.draw_rect(Rect2(r.position + Vector2(12, 8), Vector2(r.size.x - 24, 3)),
				Color(1, 1, 1, 0.38))
		var ic := Vector2(r.position.x + 26.0, r.position.y + r.size.y * 0.42)
		var ic_col: Color = skin.INK if not on else Color(1, 1, 1, 0.92)
		match icons[i]:
			"ship":
				skin.icon_ship(ci, ic, 10.0, ic_col)
			"star":
				skin.icon_star(ci, ic, 10.0, ic_col)
			_:
				skin.icon_burst(ci, ic, 11.0, ic_col)
		skin.text_center(ci, r.position.x + r.size.x * 0.58, r.position.y + 35.0, names[i], 18,
			ic_col if on else skin.INK, 0)
		skin.text_center(ci, r.position.x + r.size.x * 0.58, r.position.y + 49.0,
			["EASY", "NORMAL", "ABYSS"][i], 8, Color(1, 1, 1, 0.55) if on else skin.INK_SOFT, 0)

	# 出发按钮
	var start_rect := Rect2(cx - w * 0.5, start_y - 112.0, w, 76.0)
	rects["start"] = start_rect
	var pulse := 0.5 + 0.5 * sin(t * 2.2)
	skin.panel(ci, start_rect.grow(6.0 + pulse * 3.0), Color(skin.PINK.r, skin.PINK.g, skin.PINK.b, 0.10),
		22.0, Color(0, 0, 0, 0), 0.0, false)
	skin.button(ci, start_rect, "开始巡航", skin.PINK, false, 30, skin.WHITE)
	# 斜向扫光：只在按钮内部移动，不越出圆角
	var shimmer := fmod(t * 72.0, maxf(1.0, start_rect.size.x - 56.0))
	for i in range(3):
		var sx := start_rect.position.x + 28.0 + shimmer + i * 7.0
		if sx < start_rect.end.x - 28.0:
			ci.draw_line(Vector2(sx, start_rect.position.y + 11.0),
				Vector2(sx - 24.0, start_rect.end.y - 11.0), Color(1, 1, 1, 0.09), 5.0)
	skin.icon_chevron(ci,
		start_rect.position + Vector2(start_rect.size.x - 36.0 + sin(t * 4.0) * 4.0,
			start_rect.size.y * 0.5), 13.0, Color(1, 1, 1, 0.85), 1.0)

	# 操作提示卡
	var hint_rect := Rect2(cx - w * 0.5, hint_y - 86.0, w, 112.0)
	skin.panel(ci, hint_rect, Color(1, 1, 1, 0.82), 16.0, skin.INK, 2.5, false)
	skin.halftone(ci, Rect2(hint_rect.position + Vector2(10, 10), Vector2(42, 30)),
		Color(skin.PINK.r, skin.PINK.g, skin.PINK.b, 0.16), 9.0)
	if bool(main.is_mobile):
		var items := [
			[["拖动屏幕", "移动"], ["右下角", "冲刺 · 星爆 · 换线"]],
			[["右上角", "暂停"], ["换线键", "切换武器"]],
		]
		for ri in range(2):
			var yy := hint_rect.position.y + 36.0 + ri * 36.0
			var xx := hint_rect.position.x + 24.0
			for item in items[ri]:
				var pill_w := 82.0 if item[0].length() >= 4 else 58.0
				skin.keycap(ci, Rect2(xx, yy - 18.0, pill_w, 24.0), item[0], 10)
				var label_w: float = skin.font.get_string_size(item[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				skin.text(ci, Vector2(xx + pill_w + 8.0, yy), item[1], 11, skin.INK_SOFT)
				xx += pill_w + 20.0 + label_w
		skin.text(ci, hint_rect.position + Vector2(24, hint_rect.size.y - 12),
			"点按技能键，拖动屏幕控制机体", 11,
			Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
	else:
		var rows := [
			[["拖动 / WASD", "移动"], ["Tab", "换线"]],
			[["空格", "冲刺"], ["X", "星爆"], ["P", "暂停"]],
		]
		for ri in range(2):
			var yy := hint_rect.position.y + 33.0 + ri * 42.0
			var xx := hint_rect.position.x + 26.0
			for item in rows[ri]:
				var key_w: float = 54.0 if item[0].length() <= 2 else 88.0
				skin.keycap(ci, Rect2(xx, yy - 20.0, key_w, 26.0), item[0], 11)
				skin.text(ci, Vector2(xx + key_w + 8.0, yy), item[1], 12, skin.INK_SOFT)
				xx += key_w + 30.0
		skin.text(ci, hint_rect.position + Vector2(26, hint_rect.size.y - 12),
			"支持触屏与键盘操作", 11, Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))

	# 页脚
	var ver := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	skin.text_center(ci, cx, vh - safe_bottom - 18.0, "v%s  ·  Godot %d.%d" % [ver,
		Engine.get_version_info()["major"], Engine.get_version_info()["minor"]], 11,
		Color(1, 1, 1, 0.55), 0)
	return rects
