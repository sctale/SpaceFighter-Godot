class_name UpgradeSystem
extends RefCounted

## 星区突破：强化池过滤、三选一抽卡与应用。
## 强化字典与卡面状态仍挂在 Main 上，UI 读取路径不变。

const CFG := preload("res://scripts/game_config.gd")

var m  # Main


func _init(main_ref) -> void:
	m = main_ref


func reset() -> void:
	m.upgrades = {
		"damage_mul": 1.0, "drone_rate": 1.0, "max_hull": float(CFG.START_LIVES),
		"nova_gain": 1.0, "overdrive_bonus": 0.0, "speed": 1.0,
		"crate_rate": 1.0, "break_mul": 1.0,
		"rift_gain": 1.0, "rift_score": 1.0,
	}
	m.upgrade_pending = false
	m.upgrade_options.clear()
	m.rift = 0
	m.motes.clear()


## 已满级/已满层的强化不再进入卡池，避免三选一出废卡。
func available(u: Dictionary) -> bool:
	match String(u.get("id", "")):
		"hull":
			return float(m.upgrades["max_hull"]) < float(CFG.UPGRADE_MAX_HULL)
		"shield":
			return m.player_shields < CFG.MAX_SHIELDS
		"speed":
			return float(m.upgrades["speed"]) < CFG.UPGRADE_SPEED_MAX
	return true


## 当前已叠加层数，用于卡片 ×N 提示。
func stacks(id: String) -> int:
	match id:
		"damage":
			return int(roundf((float(m.upgrades["damage_mul"]) - 1.0) / CFG.UPGRADE_DAMAGE_STEP))
		"drone":
			return int(roundf((float(m.upgrades["drone_rate"]) - 1.0) / CFG.UPGRADE_DRONE_STEP))
		"hull":
			return int(m.upgrades["max_hull"]) - CFG.START_LIVES
		"nova":
			return int(roundf((float(m.upgrades["nova_gain"]) - 1.0) / CFG.UPGRADE_NOVA_STEP))
		"overdrive":
			return int(roundf(float(m.upgrades["overdrive_bonus"]) / CFG.UPGRADE_OVERDRIVE_STEP))
		"speed":
			return int(roundf((float(m.upgrades["speed"]) - 1.0) / CFG.UPGRADE_SPEED_STEP))
		"crate":
			return int(roundf((float(m.upgrades["crate_rate"]) - 1.0) / CFG.UPGRADE_CRATE_STEP))
		"break":
			return int(roundf((float(m.upgrades["break_mul"]) - 1.0) / CFG.UPGRADE_BREAK_STEP))
		"rift":
			return int(roundf((float(m.upgrades["rift_gain"]) - 1.0) / CFG.UPGRADE_RIFT_NOVA_STEP))
	return 0


func roll() -> void:
	m.upgrade_options.clear()
	var pool: Array = []
	for u in CFG.UPGRADE_POOL:
		if available(u):
			var copy: Dictionary = u.duplicate()
			copy["stacks"] = stacks(String(u.get("id", "")))
			pool.append(copy)
	if pool.is_empty():
		pool = CFG.UPGRADE_POOL.duplicate()
	for i in range(mini(CFG.UPGRADE_CARD_COUNT, pool.size())):
		var idx := randi() % pool.size()
		m.upgrade_options.append(pool[idx])
		pool.remove_at(idx)


func open_draft() -> void:
	roll()
	m.upgrade_pending = true
	m.player_invuln = maxf(m.player_invuln, 1.0)
	m._add_shake(8.0, 0.4)


func choose(index: int) -> void:
	if not m.upgrade_pending or index < 0 or index >= m.upgrade_options.size():
		return
	var u: Dictionary = m.upgrade_options[index]
	match String(u.get("id", "")):
		"damage":
			m.upgrades["damage_mul"] = float(m.upgrades["damage_mul"]) + CFG.UPGRADE_DAMAGE_STEP
		"drone":
			m.upgrades["drone_rate"] = float(m.upgrades["drone_rate"]) + CFG.UPGRADE_DRONE_STEP
		"hull":
			m.upgrades["max_hull"] = minf(CFG.UPGRADE_MAX_HULL,
				float(m.upgrades["max_hull"]) + 1.0)
			m.player_lives = mini(int(m.upgrades["max_hull"]), m.player_lives + 1)
		"shield":
			m.player_shields = mini(CFG.MAX_SHIELDS, m.player_shields + 1)
		"nova":
			m.upgrades["nova_gain"] = float(m.upgrades["nova_gain"]) + CFG.UPGRADE_NOVA_STEP
		"overdrive":
			m.upgrades["overdrive_bonus"] = float(m.upgrades["overdrive_bonus"]) + CFG.UPGRADE_OVERDRIVE_STEP
		"speed":
			m.upgrades["speed"] = minf(CFG.UPGRADE_SPEED_MAX,
				float(m.upgrades["speed"]) + CFG.UPGRADE_SPEED_STEP)
		"crate":
			m.upgrades["crate_rate"] = float(m.upgrades["crate_rate"]) + CFG.UPGRADE_CRATE_STEP
		"break":
			m.upgrades["break_mul"] = float(m.upgrades["break_mul"]) + CFG.UPGRADE_BREAK_STEP
		"rift":
			m.upgrades["rift_gain"] = float(m.upgrades["rift_gain"]) + CFG.UPGRADE_RIFT_NOVA_STEP
			m.upgrades["rift_score"] = float(m.upgrades["rift_score"]) + CFG.UPGRADE_RIFT_SCORE_STEP
	m.upgrade_pending = false
	m.upgrade_options.clear()
	m.zone = mini(10, m.zone + 1)
	m.waves.begin_zone()
	if m.music != null:
		m.music.play_zone(m.zone)
	m.boss_cleared = false
	m.boss_pending = false
	m.player_invuln = maxf(m.player_invuln, CFG.INVULN_ON_ZONE_CHANGE)
	m.crate_timer = minf(m.crate_timer, 4.0)
	m.sfx.play_pick()
	if m.fx != null:
		m.fx.float_text(m.player_pos + Vector2(0, -46),
			"星区突破 · %s" % String(u.get("name", "")), m._html_color("#FFD27A"), 18)
