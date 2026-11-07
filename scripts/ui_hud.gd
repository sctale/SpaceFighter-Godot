class_name UIHud
extends RefCounted

const CFG := preload("res://scripts/game_config.gd")

## 战斗 HUD：奶油贴纸面板 + 糖果色状态条 + 右下角圆形技能键。
## 所有坐标跟随 CFG.VIEW / 安全区，长屏会自动把底栏压到导航栏上方。

static func draw(ci: CanvasItem, skin: UISkin, main: Node, vw: float, vh: float,
		safe_top: float, safe_bottom: float, safe_left: float, safe_right: float,
		t: float, pressed: String) -> Dictionary:
	var rects := {}
	var top := safe_top + 10.0
	var bottom := vh - safe_bottom - 14.0
	var score_r := Rect2(safe_left + 14.0, top, 204.0, 84.0)
	var pause_r := Rect2(vw - safe_right - 62.0, top, 48.0, 48.0)
	var hull_r := Rect2(pause_r.position.x - 166.0, top, 158.0, 84.0)
	rects["pause"] = pause_r

	# 分数板
	skin.panel(ci, score_r, Color(1, 1, 1, 0.93), 18.0, skin.INK, 3.0, true)
	skin.text(ci, score_r.position + Vector2(16, 22), "S C O R E", 11, skin.INK_SOFT)
	skin.text(ci, score_r.position + Vector2(16, 56), "%d" % int(main.score), 30, skin.INK)
	skin.text(ci, score_r.position + Vector2(16, 68), "擦弹 %d" % int(main.graze), 10,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.85))
	var combo := int(main.multiplier)
	if combo > 1:
		var chip := Rect2(score_r.position.x + 116.0, score_r.position.y + 10.0, 74.0, 34.0)
		skin.panel(ci, chip, skin.GOLD, 12.0, skin.INK, 2.5, false)
		skin.text_center(ci, chip.position.x + chip.size.x * 0.5, chip.position.y + 25.0,
			"×%d" % combo, 22, skin.INK, 0)

	# 船体板
	skin.panel(ci, hull_r, Color(1, 1, 1, 0.93), 18.0, skin.INK, 3.0, true)
	skin.text(ci, hull_r.position + Vector2(14, 21), "船 体", 11, skin.INK_SOFT)
	var lives := int(main.player_lives)
	for i in range(3):
		var on := i < lives
		skin.icon_ship(ci, hull_r.position + Vector2(24 + i * 24.0, 42.0), 9.0,
			skin.PINK_DEEP if on else Color(skin.INK.r, skin.INK.g, skin.INK.b, 0.18))
	var shields := int(main.player_shields)
	for i in range(3):
		var on := i < shields
		skin.icon_shield(ci, hull_r.position + Vector2(106 + i * 17.0, 42.0), 7.0,
			skin.CYAN_DEEP if on else Color(skin.INK.r, skin.INK.g, skin.INK.b, 0.15))
	skin.text_right(ci, hull_r.end.x - 14.0, hull_r.position.y + 68.0,
		String(CFG.DIFFICULTY[String(main.difficulty)]["name"]), 10,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.75))

	# 暂停
	skin.panel(ci, pause_r, skin.PAPER, 16.0, skin.INK, 3.0, true)
	if pressed == "pause":
		skin.panel(ci, Rect2(pause_r.position + Vector2(0, 2), pause_r.size), skin.CREAM, 16.0, skin.INK, 3.0, false)
	skin.icon_pause(ci, pause_r.get_center(), 10.0, skin.INK)

	# 星区胶囊 / Boss 血条
	var boss = main.boss
	if boss != null:
		var bar_w := minf(vw - safe_left - safe_right - 64.0, 470.0)
		var bar_x := (vw - bar_w) * 0.5
		var bar_y := top + 112.0
		var name_r := Rect2(vw * 0.5 - 142.0, bar_y - 32.0, 284.0, 28.0)
		skin.panel(ci, name_r, skin.CREAM, 10.0, skin.INK, 2.5, false)
		skin.text_center(ci, vw * 0.5, name_r.position.y + 20.0,
			"%s · %s  P%d" % [String(boss.title_zh), String(boss.name_zh), int(boss.phase) + 1],
			13, skin.INK, 0)
		var bar_r := Rect2(bar_x, bar_y, bar_w, 18.0)
		skin.panel(ci, bar_r, Color(0.15, 0.11, 0.20, 0.92), 9.0, skin.INK, 3.0, false)
		var frac := clampf(float(boss.hp_frac()), 0.0, 1.0)
		if frac > 0.0:
			var inner := Rect2(bar_r.position + Vector2(3, 3), Vector2((bar_r.size.x - 6.0) * frac, 12.0))
			skin.panel(ci, inner, skin.PINK_DEEP, 6.0, skin.PINK_DEEP, 0.0, false)
			for k in range(4):
				ci.draw_line(inner.position + Vector2(inner.size.x * 0.25 + k * 3.0, 2),
					inner.position + Vector2(inner.size.x * 0.25 + k * 3.0 - 6.0, 10),
					Color(1, 1, 1, 0.22), 1.0)
		var status_y := bar_y + 36.0
		if float(boss.stun) > 0.0:
			status_chip(ci, skin, vw * 0.5, status_y, "破防！伤害 +35%", skin.GOLD)
		elif String(boss.cast_label) != "":
			var label := ("预告 · " if float(boss.telegraph) > 0.0 else "") + String(boss.cast_label)
			status_chip(ci, skin, vw * 0.5, status_y, label, skin.PINK)
		elif bool(boss.desperate):
			status_chip(ci, skin, vw * 0.5, status_y, "临界", skin.GOLD)
	else:
		var zone_r := Rect2(score_r.position.x, score_r.end.y + 8.0, 150.0, 26.0)
		skin.panel(ci, zone_r, Color(1, 1, 1, 0.82), 10.0, skin.INK, 2.0, false)
		ci.draw_circle(zone_r.position + Vector2(16, 13), 5.0, skin.CYAN)
		ci.draw_arc(zone_r.position + Vector2(16, 13), 8.0, 0.2, 2.4, 16,
			Color(1, 1, 1, 0.55), 1.5, true)
		skin.text(ci, zone_r.position + Vector2(30, 18), "ZONE %02d" % int(main.zone), 11, skin.INK)

	# 武器板
	var wp_r := Rect2(safe_left + 14.0, bottom - 86.0, 216.0, 86.0)
	skin.panel(ci, wp_r, Color(1, 1, 1, 0.93), 18.0, skin.INK, 3.0, true)
	var wdef: Dictionary = CFG.WEAPON_LINES[String(main.weapons.active_id)]
	var wtint := Color.html(String(wdef["tint"]))
	ci.draw_circle(wp_r.position + Vector2(27, 32), 18.0, Color(wtint.r, wtint.g, wtint.b, 0.18))
	ci.draw_arc(wp_r.position + Vector2(27, 32), 18.0, 0, TAU, 28, wtint, 2.0, true)
	draw_weapon_icon(ci, wp_r.position + Vector2(27, 32), String(main.weapons.active_id), wtint)
	skin.text(ci, wp_r.position + Vector2(52, 30),
		CFG.weapon_name(String(main.weapons.active_id), int(main.weapons.active().level)), 17, skin.INK)
	var lv := int(main.weapons.active().level)
	var lv_r := Rect2(wp_r.end.x - 54.0, wp_r.position.y + 10.0, 42.0, 22.0)
	skin.panel(ci, lv_r, wtint, 8.0, skin.INK, 2.0, false)
	skin.text_center(ci, lv_r.get_center().x, lv_r.position.y + 16.0, "LV%d" % lv, 11, skin.INK, 0)
	var charge := clampf(float(main.weapons.active().charge) / 100.0, 0.0, 1.0)
	var bar := Rect2(wp_r.position + Vector2(52, 48), Vector2(146, 9))
	skin.panel(ci, bar, Color(0.15, 0.11, 0.20, 0.20), 4.0, Color(0, 0, 0, 0), 0.0, false)
	if charge > 0.01:
		skin.panel(ci, Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)),
			Color(1.0, 0.42, 0.30) if bool(main.weapons.active().detuned) else wtint,
			4.0, Color(0, 0, 0, 0), 0.0, false)
	if bool(main.weapons.active().detuned):
		skin.text(ci, wp_r.position + Vector2(52, 74), "失谐排气", 10, skin.RED)
	else:
		skin.text(ci, wp_r.position + Vector2(52, 74), "火力充能 %d%%" % int(charge * 100.0), 10,
			Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
	if float(main.weapons.resonance) > 0.0:
		status_chip(ci, skin, wp_r.end.x + 54.0, wp_r.position.y + 20.0,
			"共鸣 ×%d" % int(main.weapons.resonance), skin.VIOLET)
	if float(main.overdrive) > 0.0:
		status_chip(ci, skin, wp_r.end.x + 54.0, wp_r.position.y + 54.0,
			"超频 %.1fs" % float(main.overdrive), skin.GOLD)

	# 右下角技能键
	var nova_c := Vector2(vw - safe_right - 60.0, bottom - 58.0)
	var dash_c := Vector2(vw - safe_right - 148.0, bottom - 46.0)
	var swap_c := Vector2(vw - safe_right - 52.0, bottom - 150.0)
	var focus_c := Vector2(vw - safe_right - 128.0, bottom - 138.0)
	var nova_r := 38.0
	var dash_r := 30.0
	var swap_r := 27.0
	var focus_r := 27.0
	rects["nova"] = Rect2(nova_c - Vector2(nova_r, nova_r), Vector2(nova_r * 2, nova_r * 2))
	rects["dash"] = Rect2(dash_c - Vector2(dash_r, dash_r), Vector2(dash_r * 2, dash_r * 2))
	rects["weapon"] = Rect2(swap_c - Vector2(swap_r, swap_r), Vector2(swap_r * 2, swap_r * 2))
	rects["focus"] = Rect2(focus_c - Vector2(focus_r, focus_r), Vector2(focus_r * 2, focus_r * 2))
	var nova_ready := float(main.nova) >= 100.0
	action_button(ci, skin, nova_c, nova_r, skin.GOLD if nova_ready else Color("#F6E3B4"),
		"burst", "星爆", "%d%%" % int(float(main.nova)), float(main.nova) / 100.0,
		skin.GOLD_DEEP, pressed == "nova", nova_ready)
	action_button(ci, skin, dash_c, dash_r, skin.CYAN, "chevron", "冲刺",
		"%.1f" % float(main.dash_cd) if float(main.dash_cd) > 0.0 else "",
		1.0 - clampf(float(main.dash_cd) / CFG.DASH_COOLDOWN, 0.0, 1.0),
		skin.CYAN_DEEP, pressed == "dash", float(main.dash_cd) <= 0.0)
	var swap_tint := wtint
	action_button(ci, skin, swap_c, swap_r, swap_tint, "swap", "换线",
		"L%d" % lv, 1.0, skin.INK_SOFT, pressed == "weapon", false)
	action_button(ci, skin, focus_c, focus_r,
		skin.VIOLET if bool(main.focus_locked) else Color("#E6DFF7"),
		"focus", "精准", "ON" if bool(main.focus_locked) else "",
		1.0 if bool(main.focus_locked) else 0.0, skin.VIOLET_DEEP,
		pressed == "focus", bool(main.focus_locked))

	# 大连击数字
	if combo > 1 and not bool(main.game_over):
		var cc := Vector2(score_r.end.x + 34.0, score_r.position.y + 152.0)
		var pop := 1.0 + 0.12 * sin(t * 8.0) * clampf(float(main.combo_timer) / 2.8, 0.0, 1.0)
		ci.draw_set_transform(cc, 0.0, Vector2(pop, pop))
		skin.text_center(ci, 0, 18, "×%d" % combo, 30, skin.GOLD, 3)
		skin.text_center(ci, 0, 34, "COMBO", 9, skin.INK, 0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return rects


static func status_chip(ci: CanvasItem, skin: UISkin, cx: float, y: float, text: String,
		tint: Color) -> void:
	var w := skin.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
	var r := Rect2(cx - w * 0.5, y - 24.0, w, 24.0)
	skin.panel(ci, r, Color(1, 1, 1, 0.90), 9.0, tint, 2.0, false)
	skin.text_center(ci, cx, y - 7.0, text, 12, skin.INK, 0)


static func draw_weapon_icon(ci: CanvasItem, c: Vector2, id: String, tint: Color) -> void:
	match id:
		"pulse":
			ci.draw_line(c + Vector2(-12, 0), c + Vector2(12, 0), tint, 3.0)
			ci.draw_circle(c + Vector2(12, 0), 4.0, tint)
			ci.draw_circle(c + Vector2(-12, 0), 3.0, tint)
		"prism":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -12), c + Vector2(8, 0), c + Vector2(0, 12), c + Vector2(-8, 0)]), tint)
		"swarm":
			ci.draw_circle(c + Vector2(-6, -5), 3.0, tint)
			ci.draw_circle(c + Vector2(6, -5), 3.0, tint)
			ci.draw_circle(c + Vector2(0, 7), 3.0, tint)
			ci.draw_line(c + Vector2(-6, -5), c + Vector2(0, 7), tint, 1.5)
			ci.draw_line(c + Vector2(6, -5), c + Vector2(0, 7), tint, 1.5)


static func action_button(ci: CanvasItem, skin: UISkin, c: Vector2, r: float, fill: Color,
		icon: String, label: String, badge: String, ring: float, ring_col: Color,
		pressed: bool, ready: bool) -> void:
	var cc := c + Vector2(0, 2.0 if pressed else 0.0)
	if ready:
		skin.glow(ci, cc, r + 14.0, ring_col, 5, 0.24)
	ci.draw_circle(cc, r + 5.0, skin.PAPER)
	ci.draw_circle(cc, r + 2.0, skin.INK)
	ci.draw_circle(cc, r - 1.0, fill)
	ci.draw_circle(cc + Vector2(-r * 0.22, -r * 0.28), r * 0.52, Color(1, 1, 1, 0.14))
	var icon_c := cc + Vector2(0, -r * 0.18)
	var icon_col := Color(1, 1, 1, 0.95) if fill.get_luminance() < 0.75 else skin.INK
	match icon:
		"burst":
			skin.icon_burst(ci, icon_c, r * 0.42, icon_col, 8)
		"chevron":
			skin.icon_chevron(ci, icon_c + Vector2(-r * 0.12, 0), r * 0.42, icon_col, 1.0)
			skin.icon_chevron(ci, icon_c + Vector2(r * 0.26, 0), r * 0.42, icon_col, 1.0)
		"swap":
			skin.icon_burst(ci, icon_c, r * 0.38, icon_col, 4)
			ci.draw_arc(icon_c, r * 0.52, -0.5, PI * 1.05, 24, icon_col, 2.0, true)
		"focus":
			skin.icon_crosshair(ci, icon_c, r * 0.46, icon_col)
	skin.text_center(ci, cc.x, cc.y + r * 0.58, label, 12 if r < 30.0 else 14, icon_col, 0)
	if badge != "":
		skin.text_center(ci, cc.x, cc.y + r * 0.58 + 12.0, badge, 8,
			Color(icon_col.r, icon_col.g, icon_col.b, 0.75), 0)
	if ring > 0.0:
		ci.draw_arc(cc, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(ring, 0.0, 1.0), 40,
			ring_col, 3.0, true)
	if pressed:
		ci.draw_arc(cc, r + 5.0, 0, TAU, 32, Color(1, 1, 1, 0.45), 2.0, true)
