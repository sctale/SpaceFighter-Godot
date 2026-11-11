class_name UISettings
extends RefCounted

## 独立设置屏（UI 重构 Phase 2）：复用暂停页现有三开关（音乐/音效/震屏），
## 零新机制；动作字符串与暂停页一致（opt_*），持久化走 main._save_opts。

static func draw(ci: CanvasItem, skin: UISkin, main: Node, vw: float, vh: float,
		safe_top: float, safe_bottom: float, t: float, pressed: String,
		k: float) -> Dictionary:
	var rects := {}
	var w := minf(vw - 56.0, 440.0)
	var h := minf(vh - safe_top - safe_bottom - 80.0, 480.0)
	var card := Rect2((vw - w) * 0.5, (vh - h) * 0.5 + (1.0 - k) * 30.0, w, h)
	skin.panel(ci, card, skin.PAPER, 26.0, skin.BORDER, 4.0, true)
	skin.halftone(ci, Rect2(card.position + Vector2(16, 16), Vector2(70, 46)),
		Color(skin.ACCENT_BLUE.r, skin.ACCENT_BLUE.g, skin.ACCENT_BLUE.b, 0.15), 12.0)
	skin.sparkle(ci, card.position + Vector2(w - 46, 48), 13.0, skin.GOLD, t)
	skin.text_center(ci, vw * 0.5, card.position.y + 66.0, "设置", skin.TEXT_H2, skin.PINK_DEEP, 0)
	skin.text_center(ci, vw * 0.5, card.position.y + 92.0, "巡航偏好 · 切换后立即保存", skin.TEXT_SM, skin.INK_SOFT, 0)

	var opts := [["opt_music", "音乐", "背景音乐", bool(main.opt_music)],
		["opt_sfx", "音效", "战斗与按钮音效", bool(main.opt_sfx)],
		["opt_shake", "震屏", "受击与爆炸震屏", bool(main.opt_shake)]]
	var ry := card.position.y + 116.0
	for i in range(3):
		var r := Rect2(card.position.x + 24.0, ry + i * 68.0, w - 48.0, 56.0)
		rects[String(opts[i][0])] = r
		var on: bool = opts[i][3]
		var pr := pressed == String(opts[i][0])
		var rr := r
		if pr:
			rr.position.y += 2.0
		skin.panel(ci, rr, skin.CREAM, 14.0, skin.BORDER, 2.0, not pr)
		skin.text(ci, rr.position + Vector2(18, 26), String(opts[i][1]), skin.TEXT_LG, skin.INK)
		skin.text(ci, rr.position + Vector2(18, 44), String(opts[i][2]), skin.TEXT_XS,
			Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8))
		var pill := Rect2(rr.end.x - 96.0, rr.position.y + 12.0, 76.0, 32.0)
		skin.panel(ci, pill, skin.CYAN if on else Color("#2A3A52"), 10.0, skin.BORDER, 2.0, false)
		skin.text_center(ci, pill.get_center().x, pill.position.y + 22.0,
			"开" if on else "关", skin.TEXT_MD, skin.BG_PRIMARY if on else skin.INK_SOFT, 0)

	var about := Rect2(card.position.x + 24.0, ry + 3 * 68.0 + 4.0, w - 48.0, 62.0)
	skin.panel(ci, about, Color(skin.BG_PRIMARY.r, skin.BG_PRIMARY.g, skin.BG_PRIMARY.b, 0.55),
		12.0, skin.BORDER_SOFT, 1.5, false)
	var ver := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	skin.text_center(ci, vw * 0.5, about.position.y + 25.0,
		"v%s · Godot %d.%d" % [ver, Engine.get_version_info()["major"],
			Engine.get_version_info()["minor"]], skin.TEXT_SM, skin.INK_SOFT, 0)
	skin.text_center(ci, vw * 0.5, about.position.y + 46.0,
		"免费游戏 · 无内购 · 进度仅本机保存", skin.TEXT_XS,
		Color(skin.INK_SOFT.r, skin.INK_SOFT.g, skin.INK_SOFT.b, 0.8), 0)

	var back := Rect2(card.position.x + 28.0, card.end.y - 68.0, w - 56.0, 52.0)
	rects["settings_back"] = back
	skin.button(ci, back, "返回", skin.PAPER, pressed == "settings_back", 22, skin.INK)
	return rects