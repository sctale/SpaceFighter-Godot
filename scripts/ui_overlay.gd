class_name UIOverlay
extends Node2D

## 立即模式 UI 总控：菜单 / HUD / 暂停 / 结算 与点击热区共用同一份布局。
## 放在 CanvasLayer 里，不受画面震动影响；坐标全部跟随实际视口。

const CFG := preload("res://scripts/game_config.gd")

var main: Node
var skin: UISkin
var font: Font

var pressed := ""
var pressed_t := 0.0
var menu_buttons := {}
var game_buttons := {}
var pause_buttons := {}
var over_buttons := {}
var upgrade_buttons := {}

var _t := 0.0
var _banner_t := 0.0
var _banner_zone := 1
var _warning_t := 0.0
var _warning_shown := false
var _last_zone := 1
var _fade := 1.0
var _last_state := ""
var _modal_t := 0.0


func _ready() -> void:
	skin = UISkin.new(font)


func _process(delta: float) -> void:
	_t += delta
	pressed_t = maxf(0.0, pressed_t - delta)
	if main == null:
		return
	var state := _state()
	if state != _last_state:
		if _last_state != "" and (state == "menu" or _last_state == "menu"):
			_fade = 1.0
		_modal_t = 0.0
		_last_state = state
	_fade = maxf(0.0, _fade - delta * 3.4)
	if state == "paused" or state == "over" or state == "upgrade":
		_modal_t += delta
	main.display_score = lerpf(float(main.display_score), float(main.score),
		1.0 - exp(-7.0 * delta))
	if main.boss != null:
		main.display_boss_hp = lerpf(float(main.display_boss_hp), float(main.boss.hp_frac()),
			1.0 - exp(-6.0 * delta))
	else:
		main.display_boss_hp = 1.0
	if not bool(main.in_menu):
		if int(main.zone) != _last_zone:
			_last_zone = int(main.zone)
			_banner_zone = _last_zone
			_banner_t = 2.4
		if main.boss != null and bool(main.boss_pending):
			if not _warning_shown:
				_warning_t = 1.6
				_warning_shown = true
		else:
			_warning_shown = false
	_banner_t = maxf(0.0, _banner_t - delta)
	_warning_t = maxf(0.0, _warning_t - delta)
	queue_redraw()


func _state() -> String:
	if bool(main.in_menu):
		return "menu"
	if bool(main.game_over):
		return "over"
	if bool(main.upgrade_pending):
		return "upgrade"
	if bool(main.paused):
		return "paused"
	return "game"


func _ease_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _draw_fade(vw: float, vh: float) -> void:
	if _fade > 0.0:
		draw_rect(Rect2(0, 0, vw, vh), Color(0.10, 0.07, 0.16, _fade * 0.82))


func _draw() -> void:
	if main == null:
		return
	var vs := get_viewport_rect().size
	var vw := vs.x
	var vh := vs.y
	var st: float = CFG.SAFE_TOP
	var sb: float = CFG.SAFE_BOTTOM
	var sl: float = CFG.SAFE_LEFT
	var sr: float = CFG.SAFE_RIGHT
	var flash := pressed if pressed_t > 0.0 else ""
	if bool(main.in_menu):
		menu_buttons = UIMenu.draw(self, skin, main, vw, vh, st, sb, _t)
		_draw_fade(vw, vh)
		return
	game_buttons = UIHud.draw(self, skin, main, vw, vh, st, sb, sl, sr, _t, flash)
	if bool(main.upgrade_pending):
		_draw_upgrade(vw, vh, st, sb, flash)
	elif bool(main.paused):
		_draw_pause(vw, vh, st, sb, flash)
	elif bool(main.game_over):
		_draw_results(vw, vh, st, sb, flash)
	else:
		_draw_banners(vw, vh, st)
	_draw_fade(vw, vh)


func press(p: Vector2) -> String:
	if main == null:
		return ""
	if bool(main.upgrade_pending):
		for k in upgrade_buttons:
			if Rect2(upgrade_buttons[k]).has_point(p):
				return _flash_action("upgrade_" + String(k))
		return ""
	if bool(main.in_menu):
		for k in menu_buttons:
			if Rect2(menu_buttons[k]).has_point(p):
				return _flash_action("diff_" + String(k) if k != "start" else "start")
		return ""
	if bool(main.game_over):
		for k in over_buttons:
			if Rect2(over_buttons[k]).has_point(p):
				return _flash_action(String(k))
		if float(main.game_over_time) > 0.6:
			return _flash_action("retry")
		return ""
	if bool(main.paused):
		for k in pause_buttons:
			if Rect2(pause_buttons[k]).has_point(p):
				return _flash_action(String(k))
		return ""
	for k in game_buttons:
		if Rect2(game_buttons[k]).has_point(p):
			return _flash_action(String(k))
	return ""


func _flash_action(action: String) -> String:
	pressed = action.trim_prefix("diff_") if action.begins_with("diff_") else action
	if action.begins_with("diff_"):
		pressed = action.substr(5)
	pressed_t = 0.20
	return action


func _draw_upgrade(vw: float, vh: float, st: float, sb: float, flash: String) -> void:
	var k := _ease_out(_modal_t / 0.40)
	draw_rect(Rect2(0, 0, vw, vh), Color(0.10, 0.07, 0.16, 0.62 * k))
	var w := minf(vw - 48.0, 470.0)
	var h := minf(vh - st - sb - 48.0, 500.0)
	var card := Rect2((vw - w) * 0.5, (vh - h) * 0.5 + (1.0 - k) * 38.0, w, h)
	skin.panel(self, card, skin.PAPER, 26.0, skin.INK, 4.0, true)
	skin.halftone(self, Rect2(card.position + Vector2(18, 16), Vector2(64, 44)),
		Color(skin.CYAN.r, skin.CYAN.g, skin.CYAN.b, 0.13), 12.0)
	skin.sparkle(self, card.position + Vector2(w - 46, 46), 12.0, skin.GOLD, _t)
	skin.text_center(self, vw * 0.5, card.position.y + 52.0, "星区突破", 34, skin.PINK_DEEP, 0)
	skin.text_center(self, vw * 0.5, card.position.y + 76.0,
		"BOSS 已击破 · 选择一项巡航强化", 11, skin.INK_SOFT, 0)
	upgrade_buttons.clear()
	var opt_h := 108.0
	var gap := 10.0
	var start_y := card.position.y + 112.0
	for i in range(main.upgrade_options.size()):
		var opt: Dictionary = main.upgrade_options[i]
		var r := Rect2(card.position.x + 22.0, start_y + i * (opt_h + gap),
			card.size.x - 44.0, opt_h)
		var pressed := flash == "upgrade_%d" % i
		if pressed:
			r.position.y += 2.0
		upgrade_buttons[str(i)] = r
		var tint := Color.html(String(opt.get("tint", "#FF8FB1")))
		skin.panel(self, r, skin.CREAM, 18.0, tint, 2.5, not pressed)
		self.draw_circle(r.position + Vector2(36, 54), 24.0,
			Color(tint.r, tint.g, tint.b, 0.18))
		self.draw_arc(r.position + Vector2(36, 54), 24.0, 0, TAU, 32, tint, 2.0, true)
		var ic := r.position + Vector2(36, 54)
		var ic_col := skin.INK
		match String(opt.get("icon", "burst")):
			"ship":
				skin.icon_ship(self, ic, 13.0, ic_col)
			"heart":
				skin.icon_heart(self, ic, 12.0, ic_col)
			"shield":
				skin.icon_shield(self, ic, 13.0, ic_col)
			"star":
				skin.icon_star(self, ic, 13.0, ic_col)
			"chevron":
				skin.icon_chevron(self, ic, 13.0, ic_col, 1.0)
			"burst4":
				skin.icon_burst(self, ic, 14.0, ic_col, 4)
			_:
				skin.icon_burst(self, ic, 14.0, ic_col, 8)
		var label := String(opt.get("name", "强化"))
		var stacks := int(opt.get("stacks", 0))
		if stacks > 0:
			label += "  ×%d" % stacks
		skin.text(self, r.position + Vector2(70, 42), label, 18, skin.INK)
		skin.text(self, r.position + Vector2(70, 68), String(opt.get("desc", "")),
			11, Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.9))
		skin.keycap(self, Rect2(r.end.x - 40.0, r.position.y + 12.0, 24.0, 22.0),
			str(i + 1), 10)
		skin.icon_chevron(self, r.position + Vector2(r.size.x - 30.0, 54.0),
			10.0, tint, 1.0)
	skin.text_center(self, vw * 0.5, card.end.y - 18.0,
		"选择后立即生效 · 进入下一星区", 11, skin.INK_SOFT, 0)


func _draw_pause(vw: float, vh: float, st: float, sb: float, flash: String) -> void:
	var k := _ease_out(_modal_t / 0.32)
	draw_rect(Rect2(0, 0, vw, vh), Color(0.10, 0.07, 0.16, 0.55 * k))
	var w := minf(vw - 56.0, 440.0)
	var h := minf(vh - st - sb - 80.0, 470.0)
	var card := Rect2((vw - w) * 0.5, (vh - h) * 0.5 + (1.0 - k) * 30.0, w, h)
	skin.panel(self, card, skin.PAPER, 26.0, skin.INK, 4.0, true)
	skin.halftone(self, Rect2(card.position + Vector2(16, 16), Vector2(70, 46)),
		Color(skin.PINK.r, skin.PINK.g, skin.PINK.b, 0.15), 12.0)
	skin.sparkle(self, card.position + Vector2(w - 46, 48), 13.0, skin.GOLD, _t)
	skin.text_center(self, vw * 0.5, card.position.y + 70.0, "暂停", 42, skin.PINK_DEEP, 0)
	skin.text_center(self, vw * 0.5, card.position.y + 96.0, "巡航已冻结", 13, skin.INK_SOFT, 0)
	var stats := [
		["分数", "%d" % int(main.score)], ["星区", "%02d" % int(main.zone)],
		["击坠", "%d" % int(main.total_kills)], ["擦弹", "%d" % int(main.graze)],
	]
	for i in range(4):
		var rr := Rect2(card.position.x + 24.0 + (i % 2) * (w - 48.0) * 0.5,
			card.position.y + 122.0 + (i / 2) * 52.0, (w - 60.0) * 0.5, 42.0)
		skin.panel(self, rr, skin.CREAM, 10.0, skin.INK, 2.0, false)
		skin.text(self, rr.position + Vector2(12, 17), stats[i][0], 11, skin.INK_SOFT)
		skin.text_right(self, rr.end.x - 12.0, rr.position.y + 28.0, stats[i][1], 18, skin.INK)
	var by := card.position.y + 238.0
	var bw := w - 56.0
	var bh := 56.0
	var gap := 12.0
	pause_buttons = {
		"resume": Rect2(card.position.x + 28.0, by, bw, bh),
		"restart": Rect2(card.position.x + 28.0, by + bh + gap, bw, bh),
		"menu": Rect2(card.position.x + 28.0, by + (bh + gap) * 2.0, bw, bh),
	}
	skin.button(self, pause_buttons["resume"], "继续巡航", skin.PINK, flash == "resume", 24, skin.WHITE)
	skin.button(self, pause_buttons["restart"], "重新出击", skin.CYAN, flash == "restart", 24, skin.INK)
	skin.button(self, pause_buttons["menu"], "返回主菜单", skin.PAPER, flash == "menu", 22, skin.INK)
	skin.text_center(self, vw * 0.5, card.end.y - 20.0,
		"点按按钮继续" if bool(main.is_mobile) else "也可以按 P / Esc 继续", 11, skin.INK_SOFT, 0)


func _draw_results(vw: float, vh: float, st: float, sb: float, flash: String) -> void:
	var k := _ease_out(_modal_t / 0.40)
	draw_rect(Rect2(0, 0, vw, vh), Color(0.10, 0.07, 0.16, 0.62 * k))
	var w := minf(vw - 48.0, 470.0)
	var h := minf(vh - st - sb - 48.0, 640.0)
	var card := Rect2((vw - w) * 0.5, (vh - h) * 0.5 + (1.0 - k) * 40.0, w, h)
	skin.panel(self, card, skin.PAPER, 26.0, skin.INK, 4.0, true)
	var grade: String = String(main._grade())
	var tint := skin.GOLD
	match grade:
		"A":
			tint = skin.PINK
		"B":
			tint = skin.CYAN
		"C":
			tint = skin.VIOLET
	skin.text_center(self, vw * 0.5, card.position.y + 52.0, "巡航终止", 32, skin.PINK_DEEP, 0)
	skin.text_center(self, vw * 0.5, card.position.y + 74.0, "信号消失在裂隙深处", 11, skin.INK_SOFT, 0)
	# 评级星章
	var gc := Vector2(vw * 0.5, card.position.y + 142.0)
	skin.icon_burst(self, gc, 56.0, Color(tint.r, tint.g, tint.b, 0.18), 10)
	skin.icon_burst(self, gc, 47.0, tint, 10)
	skin.text_center(self, gc.x, gc.y + 20.0, grade, 48, skin.INK, 0)
	skin.text_center(self, gc.x, gc.y + 44.0, "评级", 9, skin.PAPER, 0)
	skin.text_center(self, vw * 0.5, card.position.y + 228.0, "%d" % int(main.score), 44, skin.INK, 0)
	skin.text_center(self, vw * 0.5, card.position.y + 248.0, "得分", 10, skin.INK_SOFT, 0)
	if int(main.score) >= int(main.best_score) and int(main.score) > 0:
		var rr := Rect2(vw * 0.5 - 74.0, card.position.y + 258.0, 148.0, 24.0)
		skin.panel(self, rr, skin.GOLD, 8.0, skin.INK, 2.0, false)
		skin.text_center(self, vw * 0.5, rr.position.y + 17.0, "新纪录", 11, skin.INK, 0)
	var rows := [
		["最远星区", "%02d  %s" % [int(main.zone), UIMenu.ZONE_NAMES[clampi(int(main.zone) - 1, 0, 9)]]],
		["击坠", "%d" % int(main.total_kills)],
		["擦弹 / 裂隙", "%d / %d" % [int(main.graze), int(main.rift)]],
		["最高分", "%d" % int(main.best_score)],
	]
	for i in range(4):
		var rr := Rect2(card.position.x + 26.0, card.position.y + 296.0 + i * 40.0, w - 52.0, 32.0)
		skin.panel(self, rr, skin.CREAM, 8.0, skin.INK, 1.5, false)
		skin.text(self, rr.position + Vector2(12, 21), rows[i][0], 12, skin.INK_SOFT)
		skin.text_right(self, rr.end.x - 12.0, rr.position.y + 22.0, rows[i][1], 15, skin.INK)
	var by := card.position.y + 296.0 + 4 * 40.0 + 14.0
	var bw := w - 56.0
	over_buttons = {
		"retry": Rect2(card.position.x + 28.0, by, bw, 58.0),
		"menu": Rect2(card.position.x + 28.0, by + 70.0, bw, 48.0),
	}
	skin.button(self, over_buttons["retry"], "再来一次", skin.PINK, flash == "retry", 26, skin.WHITE)
	skin.button(self, over_buttons["menu"], "返回主菜单", skin.PAPER, flash == "menu", 20, skin.INK)


func _draw_banners(vw: float, vh: float, st: float) -> void:
	if _banner_t > 0.0:
		var a := clampf(_banner_t / 0.6, 0.0, 1.0) * clampf((2.4 - _banner_t) / 0.25, 0.0, 1.0)
		var y := st + vh * 0.30
		draw_rect(Rect2(0, y - 54.0, vw, 108.0), Color(0.10, 0.07, 0.16, 0.55 * a))
		draw_rect(Rect2(0, y - 54.0, vw, 3), Color(1, 1, 1, 0.35 * a))
		draw_rect(Rect2(0, y + 51.0, vw, 3), Color(1, 1, 1, 0.35 * a))
		skin.text_center(self, vw * 0.5, y - 8.0, "星区 %02d" % _banner_zone, 12, Color(1, 1, 1, a), 0)
		skin.text_center(self, vw * 0.5, y + 32.0, UIMenu.ZONE_NAMES[clampi(_banner_zone - 1, 0, 9)],
			34, Color(1, 1, 1, a), 3)
	if _warning_t > 0.0:
		var a := clampf(_warning_t / 0.5, 0.0, 1.0)
		var y := st + vh * 0.40
		draw_rect(Rect2(0, y - 40.0, vw, 80.0), Color(0.16, 0.06, 0.12, 0.72 * a))
		skin.icon_chevron(self, Vector2(vw * 0.5 - 150.0, y + 8.0), 18.0, Color(1, 0.7, 0.7, a), -1.0)
		skin.icon_chevron(self, Vector2(vw * 0.5 + 150.0, y + 8.0), 18.0, Color(1, 0.7, 0.7, a), 1.0)
		skin.text_center(self, vw * 0.5, y + 18.0, "W A R N I N G", 30, Color(1, 1, 1, a), 3)
		skin.text_center(self, vw * 0.5, y + 36.0, "大型旗舰接近", 11, Color(1, 0.85, 0.85, a), 0)
