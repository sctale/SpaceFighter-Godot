class_name WeaponSystem
extends RefCounted

## 三条武器线 + 蓄能/失谐/共鸣经济（移植自归档 Unity v0.21.14 WeaponSystem.cs）。
## 口径：540 设计像素。蓄能"按枪扣"（每枪 drain×本枪间隔），不是按帧扣。

const CFG := preload("res://scripts/game_config.gd")


class LineState:
	var id: String
	var level := 1
	var unlocked := false
	var charge := 100.0
	var detuned := false

	func _init(p_id: String, p_level: int, p_unlocked: bool) -> void:
		id = p_id
		level = p_level
		unlocked = p_unlocked


var lines: Array = []
var active_id := "pulse"
var resonance := 0.0
var fire_cooldown := 0.0
var overdrive := false        # 由玩家超频状态注入
var swap_idle := 0.0          # 距上次换线的停留时间（玩家维护）
var _res_timer := 0.0

# func(pos:Vector2, vel:Vector2, props:Dictionary)
var spawn: Callable


func _init() -> void:
	lines = [
		LineState.new("pulse", CFG.START_PULSE_LEVEL, true),
		LineState.new("prism", 1, false),
		LineState.new("swarm", 1, false),
	]


func active() -> LineState:
	for l in lines:
		if l.id == active_id:
			return l
	return lines[0]


func line(id: String) -> LineState:
	for l in lines:
		if l.id == id:
			return l
	return lines[0]


func unlocked_count() -> int:
	var n := 0
	for l in lines:
		if l.unlocked:
			n += 1
	return n


func level() -> int:
	return active().level


# ---- 纯函数（门禁直接断言）----

static func interval(id: String, lvl: int, od: bool, detuned: bool) -> float:
	var def: Dictionary = CFG.WEAPON_LINES[id]
	var rates: Array = CFG.FIRE_INTERVALS[id]
	var base := float(rates[clampi(lvl, 1, 5) - 1])
	return base * (CFG.OVERDRIVE_FIRE_RATE_MUL if od else 1.0) * (CFG.DETUNED_INTERVAL_MUL if detuned else 1.0)


static func charge_cost(id: String, lvl: int, unlocked: int, od: bool, detuned: bool) -> float:
	var def: Dictionary = CFG.WEAPON_LINES[id]
	return float(def["drain"]) * interval(id, lvl, od, detuned) * (CFG.SOLO_DRAIN_MUL if unlocked < 2 else 1.0)


static func resonance_gain(well_timed: bool, target_charge: float, target_detuned: bool) -> bool:
	return well_timed and target_charge >= CFG.DETUNE_CLEAR_CHARGE and not target_detuned


func fire_interval() -> float:
	return interval(active_id, active().level, overdrive, active().detuned)


func damage_mul() -> float:
	var res := 1.0 + resonance * CFG.RESONANCE_PER_STACK_DAMAGE
	var det := CFG.DETUNED_DAMAGE_MUL if active().detuned else 1.0
	var od := CFG.OVERDRIVE_DAMAGE_MUL if overdrive else 1.0
	return res * det * od


func _calibrate(base_dmg: float) -> float:
	return maxf(1.0, roundf(base_dmg * damage_mul()))


func tick(dt: float) -> void:
	for l in lines:
		if not l.unlocked:
			continue
		var def: Dictionary = CFG.WEAPON_LINES[l.id]
		if l.id != active_id:
			l.charge = minf(100.0, l.charge + float(def["recover"]) * dt)
			if l.detuned and l.charge >= CFG.DETUNE_CLEAR_CHARGE:
				l.detuned = false
		elif l.detuned:
			l.charge = minf(CFG.DETUNE_REARM_CHARGE, l.charge + float(def["drain"]) * CFG.VENT_RATIO * dt)
			if l.charge >= CFG.DETUNE_REARM_CHARGE:
				l.detuned = false

	if _res_timer > 0.0:
		_res_timer -= dt
		if _res_timer <= 0.0:
			resonance = maxf(0.0, resonance - 1.0)
			if resonance > 0.0:
				_res_timer = CFG.RESONANCE_WINDOW
	fire_cooldown -= dt


func _spend_charge() -> void:
	var w := active()
	if w.detuned:
		return
	w.charge = maxf(0.0, w.charge - charge_cost(w.id, w.level, unlocked_count(), overdrive, false))
	if w.charge <= 0.5:
		w.detuned = true


func try_fire(origin: Vector2) -> bool:
	if fire_cooldown > 0.0:
		return false
	fire_cooldown = fire_interval()
	match active_id:
		"prism":
			_fire_prism(origin)
		"swarm":
			_fire_swarm(origin)
		_:
			_fire_pulse(origin)
	_spend_charge()
	return true


func _emit(origin: Vector2, dx: float, dy: float, vx: float, vy: float,
		dmg: float, radius: float, tint: Color, kind: String, life: float,
		pierce := 0, homing := false, boss_bonus := 1.0) -> void:
	if not spawn.is_valid():
		return
	var pos := origin + Vector2(dx, dy)
	var vel := Vector2(vx, vy)
	spawn.call(pos, vel, {
		"damage": dmg, "radius": radius, "tint": tint, "kind": kind, "life": life,
		"pierce": pierce, "homing": homing, "boss_bonus": boss_bonus,
	})


func _fire_pulse(o: Vector2) -> void:
	var lv := clampi(active().level, 1, 5)
	var tint := Color.html(CFG.WEAPON_LINES["pulse"]["tint"])
	var sp := float(CFG.WEAPON_LINES["pulse"]["speed"])
	var d := _calibrate(1.0)
	# 向上为 -y；侧翼 vx 是原版像素/秒
	match lv:
		1:
			_emit(o, 0, 0, 0, -sp, d, 5.0, tint, "bolt", 2.2)
		2:
			_emit(o, -7, 0, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 7, 0, 0, -sp, d, 5.0, tint, "bolt", 2.2)
		3:
			_emit(o, 0, -4, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, -9, 4, -45, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 9, 4, 45, -sp, d, 5.0, tint, "bolt", 2.2)
		4:
			_emit(o, -6, -2, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 6, -2, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, -15, 5, -85, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 15, 5, 85, -sp, d, 5.0, tint, "bolt", 2.2)
		_:
			_emit(o, 0, -6, 0, -sp, _calibrate(2.0), 6.0, tint, "bolt", 2.2)
			_emit(o, -8, 2, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 8, 2, 0, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, -17, 7, -105, -sp, d, 5.0, tint, "bolt", 2.2)
			_emit(o, 17, 7, 105, -sp, d, 5.0, tint, "bolt", 2.2)
	if overdrive:
		_emit(o, -24, 10, -160, -sp, d, 5.0, tint, "bolt", 2.2)
		_emit(o, 24, 10, 160, -sp, d, 5.0, tint, "bolt", 2.2)


func _fire_prism(o: Vector2) -> void:
	var lv := clampi(active().level, 1, 5)
	var tint := Color.html(CFG.WEAPON_LINES["prism"]["tint"])
	var sp := float(CFG.WEAPON_LINES["prism"]["speed"])
	var b := float(CFG.PRISM_DAMAGE[lv - 1])
	var pierce := int(CFG.PRISM_PIERCE[lv - 1])
	_emit(o, 0, 4, 0, -sp, _calibrate(b), 8.0, tint, "lance", 3.0, pierce, false, CFG.PRISM_BOSS_BONUS)
	if lv >= 2:
		_emit(o, -10, -2, 0, -sp * 0.97, _calibrate(maxf(2.0, b - 1.0)), 6.0, tint, "lance", 3.0, pierce, false, CFG.PRISM_BOSS_BONUS)
		_emit(o, 10, -2, 0, -sp * 0.97, _calibrate(maxf(2.0, b - 1.0)), 6.0, tint, "lance", 3.0, pierce, false, CFG.PRISM_BOSS_BONUS)
	if lv >= 4:
		_emit(o, -20, -6, -95, -sp * 0.94, _calibrate(maxf(2.0, b - 2.0)), 5.0, tint, "lance", 3.0, 1, false, CFG.PRISM_BOSS_BONUS)
		_emit(o, 20, -6, 95, -sp * 0.94, _calibrate(maxf(2.0, b - 2.0)), 5.0, tint, "lance", 3.0, 1, false, CFG.PRISM_BOSS_BONUS)


func _fire_swarm(o: Vector2) -> void:
	var lv := clampi(active().level, 1, 5)
	var tint := Color.html(CFG.WEAPON_LINES["swarm"]["tint"])
	var sp := float(CFG.WEAPON_LINES["swarm"]["speed"])
	var count := int(CFG.SWARM_COUNT[lv - 1])
	var base_dmg := float(CFG.SWARM_DAMAGE[lv - 1])
	for i in range(count):
		var off := i - (count - 1) * 0.5
		_emit(o, off * 6.0, 6.0, off * 120.0, -sp, _calibrate(base_dmg), 4.0, tint, "micro", 2.2, 0, true)


# ---- 换线与升级 ----

func select_weapon(id: String) -> bool:
	var target := line(id)
	if not target.unlocked or id == active_id:
		return false
	var well_timed := swap_idle >= CFG.SWAP_RESONANCE_GAP
	swap_idle = 0.0
	active_id = id
	fire_cooldown = minf(fire_cooldown, 0.07)
	if resonance_gain(well_timed, target.charge, target.detuned):
		resonance = minf(float(CFG.RESONANCE_MAX), resonance + 1.0)
		_res_timer = CFG.RESONANCE_WINDOW
	else:
		resonance = 0.0
		_res_timer = 0.0
	return true


func cycle_weapon() -> bool:
	var unlocked: Array = []
	for l in lines:
		if l.unlocked:
			unlocked.append(l.id)
	if unlocked.size() < 2:
		return false
	var idx := unlocked.find(active_id)
	return select_weapon(unlocked[(idx + 1) % unlocked.size()])


func grant_level() -> bool:
	var w := active()
	if w.level < 5:
		w.level += 1
		return true
	# 满级则解锁/升级下一条未解锁的线
	for l in lines:
		if not l.unlocked:
			l.unlocked = true
			return true
	for l in lines:
		if l.level < 5:
			l.level += 1
			return true
	return false


func unlock_line(id: String) -> void:
	line(id).unlocked = true