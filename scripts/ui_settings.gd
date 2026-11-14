class_name UISettings
extends RefCounted

## 独立设置屏（参考《像素飞机大战/Sky Wings》）：
## 音乐/音效/震屏/震动 开关 + 语言切换 + 灵敏度三档。
## 动作字符串与暂停页一致（opt_*），持久化走 main._save_opts。

static func draw(ci: CanvasItem, skin: UISkin, main: Node, vw: float, vh: float,
		safe_top: float, safe_bottom: float, t: float, pressed: String,
		k: float) -> Dictionary:
	var rects := {}
	var w := minf(vw - 56.0, 460.0)
	var h := minf(vh - safe_top - safe_bottom - 80.0, 620.0)
	var card := Rect2((vw - w) * 0.5, (vh - h) * 0.5 + (1.0 - k) * 30.0, w, h)
	skin.panel(ci, card, skin.PAPER, 26.0, skin.BORDER, 4.0, true)
	skin.halftone(ci, Rect2(card.position + Vector2(16, 16), Vector2(70, 46)),
		Color(skin.ACCENT_BLUE.r, skin.ACCENT_BLUE.g, skin.ACCENT_BLUE.b, 0.15), 12.0)
	skin.sparkle(ci, card.position + Vector2(w - 46, 48), 13.0, skin.GOLD, t)
	skin.text_center(ci, vw * 0.5, card.position.y + 66.0, "设置", skin.TEXT_H2, skin.PINK_DEEP, 0)
	skin.text_center(ci, vw * 0.5, card.position.y + 92.0,
		"巡航偏好 · 切换后立即保存", skin.TEXT_SM, skin.INK_SOFT, 0)

	# 4 个开关：音乐 / 音效 / 震屏 / 震动
	var toggles := [
		["opt_music", "音乐", "背景音乐", bool(main.opt_music), "♪"],
		["opt_sfx", "音效", "战斗与按钮音效", bool(main.opt_sfx), "♫"],
		["opt_shake", "震屏", "受击与爆炸震屏", bool(main.opt_shake), "≋"],
		["opt_vibration", "震动", "受击与爆炸震动", bool(main.opt_vibration), "✦"],
	]
	var ry := card.position.y + 116.0
	var row_h := 56.0
	for i in range(4):
		var r := Rect2(card.position.x + 24.0, ry + i * row_h, w - 48.0, row_h - 8.0)
		rects[String(toggles[i][0])] = r
		var on: bool = toggles[i][3]
		var pr := pressed == String(toggles[i][0])
		var rr := r
		if pr:
			rr.position.y += 2.0
		skin.panel(ci, rr, skin.CREAM, 14.0, skin.BORDER, 2.0, not pr)
		# 图标
		skin.text_center(ci, rr.position.x + 26.0, rr.position.y + rr.size.y * 0.68,
			String(toggles[i][4]), 20, skin.PINK if on else skin.INK_SOFT, 0)
		skin.text(ci, rr.position + Vector2(52, 22), String(toggles[i][1]), skin.TEXT_LG, skin.INK)
		skin.text(ci, rr.position + Vector2(52, 40), String(toggles[i][2]), skin.TEXT_XS,
			Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
		var pill := Rect2(rr.end.x - 96.0, rr.position.y + 12.0, 76.0, 32.0)
		skin.panel(ci, pill, skin.CYAN if on else Color("#4A2A3E"), 10.0, skin.BORDER, 2.0, false)
		skin.text_center(ci, pill.get_center().x, pill.position.y + 22.0,
			"开" if on else "关", skin.TEXT_MD, skin.BG_PRIMARY if on else skin.INK_SOFT, 0)

	# 语言切换
	var lang_y := ry + 4 * row_h + 4.0
	var lang_r := Rect2(card.position.x + 24.0, lang_y, w - 48.0, 50.0)
	rects["opt_language"] = lang_r
	var lang_pr := pressed == "opt_language"
	var lang_rr := lang_r
	if lang_pr:
		lang_rr.position.y += 2.0
	skin.panel(ci, lang_rr, skin.CREAM, 14.0, skin.BORDER, 2.0, not lang_pr)
	skin.text_center(ci, lang_rr.position.x + 26.0, lang_rr.position.y + lang_rr.size.y * 0.68,
		"🌐", 20, skin.PINK, 0)
	skin.text(ci, lang_rr.position + Vector2(52, 22), "语言", skin.TEXT_LG, skin.INK)
	skin.text(ci, lang_rr.position + Vector2(52, 40), "Language", skin.TEXT_XS,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
	var lang_val := "中文" if String(main.opt_language) == "zh" else "English"
	skin.text_right(ci, lang_rr.end.x - 18.0, lang_rr.position.y + 32.0,
		lang_val, skin.TEXT_MD, skin.CYAN)

	# 灵敏度三档
	var sens_y := lang_y + 58.0
	var sens_r := Rect2(card.position.x + 24.0, sens_y, w - 48.0, 50.0)
	rects["opt_sensitivity"] = sens_r
	var sens_pr := pressed == "opt_sensitivity"
	var sens_rr := sens_r
	if sens_pr:
		sens_rr.position.y += 2.0
	skin.panel(ci, sens_rr, skin.CREAM, 14.0, skin.BORDER, 2.0, not sens_pr)
	skin.text_center(ci, sens_rr.position.x + 26.0, sens_rr.position.y + sens_rr.size.y * 0.68,
		"⚡", 20, skin.PINK, 0)
	skin.text(ci, sens_rr.position + Vector2(52, 22), "灵敏度", skin.TEXT_LG, skin.INK)
	skin.text(ci, sens_rr.position + Vector2(52, 40), "Sensitivity", skin.TEXT_XS,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
	var sens_val := "低" if main.opt_sensitivity < 0.8 else ("高" if main.opt_sensitivity > 1.2 else "中")
	skin.text_right(ci, sens_rr.end.x - 18.0, sens_rr.position.y + 32.0,
		sens_val, skin.TEXT_MD, skin.GOLD)

	# 关于
	var about_y := sens_y + 58.0
	var about := Rect2(card.position.x + 24.0, about_y, w - 48.0, 56.0)
	skin.panel(ci, about, Color(skin.BG_PRIMARY.r, skin.BG_PRIMARY.g, skin.BG_PRIMARY.b, 0.55),
		12.0, skin.BORDER_SOFT, 1.5, false)
	var ver := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	skin.text_center(ci, vw * 0.5, about.position.y + 22.0,
		"v%s · Godot %d.%d" % [ver, Engine.get_version_info()["major"],
			Engine.get_version_info()["minor"]], skin.TEXT_SM, skin.INK_SOFT, 0)
	skin.text_center(ci, vw * 0.5, about.position.y + 42.0,
		"免费游戏 · 无内购 · 进度仅本机保存", skin.TEXT_XS,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8), 0)

	var back := Rect2(card.position.x + 28.0, card.end.y - 62.0, w - 56.0, 48.0)
	rects["settings_back"] = back
	skin.button(ci, back, "返回", skin.PAPER, pressed == "settings_back", 22, skin.INK)
	return rects
