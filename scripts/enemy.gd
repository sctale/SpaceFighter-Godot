class_name Enemy
extends RefCounted

## 完整敌机行为（移植自归档 Unity v0.21.14 EnemyShip.cs / web entities.js）。
## 坐标用 Godot 的 y 向下像素口径：敌机从顶部（小 y）往下（大 y）飞。
## 开火/召唤通过 Callable 回调主场景，避免与弹池耦合。

const CFG := preload("res://scripts/game_config.gd")

var kind: String
var def: Dictionary
var pos: Vector2
var anchor_x: float
var station_y: float
var age := 0.0
var phase := 0.0
var hp := 1.0
var max_hp := 1.0
var size := 16.0          # 美术外缘半径（全尺寸）
var hit_r := 12.0         # 判定半径 = size × 0.78
var tier := 0
var zone := 1
var elite := false
var affix := "none"       # none / armored / rapid / volatile
var fire_timer := 0.0
var charge := 0.0
var flash := 0.0
var turn := 0.0           # 视觉倾斜（弧度）
var spin := 0.0           # 陨石自转
var leaving := false
var dead := false
var dive_locked := false
var dive_vel := Vector2.ZERO
var dir_sign := 1.0
var summon_t := 0.0
var entry_delay := 0.0
var damage_taken_mul := 1.0
var fire_mul := 1.0
var score_value := 0
var drop_chance := 0.0
var volatile_fuse := -1.0 # 挥发机被击落后倒计时分裂

# 回调：func(pos:Vector2, vel:Vector2, color:Color, radius:float, kind:String, life:float)
var spawn_bullet: Callable
# func(kind:String, pos:Vector2)
var spawn_child: Callable
# func() -> Vector2
var player_pos_fn: Callable


func setup(p_kind: String, p_def: Dictionary, p_pos: Vector2, p_zone: int,
		p_tier: int, p_elite: bool, p_affix: String, p_hp_frac := 1.0) -> void:
	kind = p_kind
	def = p_def
	pos = p_pos
	anchor_x = p_pos.x
	zone = p_zone
	tier = p_tier
	elite = p_elite
	affix = p_affix
	phase = randf() * TAU
	dir_sign = 1.0 if randf() < 0.5 else -1.0
	station_y = CFG.HEIGHT * float(def.get("targetY", 0.25))
	summon_t = CFG.CARRIER_SUMMON_EVERY

	# 尺寸：精英 ×1.22，装甲 ×1.06，急速 ×0.92
	var size_mul := 1.0
	if elite:
		size_mul *= CFG.ELITE_SIZE_MUL
	if affix == "armored":
		size_mul *= CFG.ARMORED_SIZE_MUL
	elif affix == "rapid":
		size_mul *= CFG.RAPID_SIZE_MUL
	size = float(def.get("size", 16.0)) * size_mul
	hit_r = size * CFG.ENEMY_COLLISION_SIZE

	# 血量两步取整（先 base×星区×精英，再 ×词缀），与原版压线手感一致
	var hp_raw := float(def.get("hp", 1.0)) * CFG.enemy_hp_scale(zone) * (CFG.ELITE_HP_MUL if elite else 1.0)
	hp_raw = roundf(hp_raw)
	if affix == "armored":
		hp_raw = roundf(hp_raw * CFG.ARMORED_HP_MUL)
		damage_taken_mul = CFG.ARMORED_DAMAGE_TAKEN_MUL
	elif affix == "volatile":
		hp_raw = maxf(1.0, roundf(hp_raw * CFG.VOLATILE_HP_MUL))
	hp = maxf(1.0, roundf(hp_raw * p_hp_frac))
	max_hp = hp

	# 分数：精英 ×3.2，词缀 ×1.18
	var sc := float(def.get("score", 0))
	if elite:
		sc *= CFG.ELITE_SCORE_MUL
	if affix != "none":
		sc *= 1.18
	score_value = int(roundf(sc))
	drop_chance = float(def.get("drop", 0.0))

	# 开火节奏词缀：急速更勤 ×0.72，装甲更慢 ×1.12，精英 ×0.82
	fire_mul = 1.0
	if affix == "rapid":
		fire_mul = CFG.RAPID_FIRE_MUL
	elif affix == "armored":
		fire_mul = CFG.ARMORED_FIRE_MUL
	if elite:
		fire_mul *= CFG.ELITE_FIRE_MUL
	var cd: Array = def.get("fireCd", [1.6, 2.2])
	fire_timer = randf_range(float(cd[0]), float(cd[1])) * fire_mul


func next_interval(diff: Dictionary) -> float:
	var cd: Array = def.get("fireCd", [1.6, 2.2])
	var base := randf_range(float(cd[0]), float(cd[1]))
	base *= (1.0 - tier * CFG.ENEMY_FIRE_PER_TIER)
	return maxf(CFG.ENEMY_FIRE_INTERVAL_FLOOR, base) * fire_mul


func tick(dt: float, diff: Dictionary) -> void:
	if dead:
		return
	age += dt
	flash = maxf(0.0, flash - dt)
	if entry_delay > 0.0:
		entry_delay -= dt
	_move(dt)
	_fire(dt, diff)


func _move(dt: float) -> void:
	var speed := float(def.get("speed", 50.0)) * (1.0 + tier * CFG.ENEMY_SPEED_PER_TIER)
	var amp := float(def.get("amp", 36.0))
	var pattern := String(def.get("pattern", "sine"))
	turn = 0.0

	if leaving:
		var leave := CFG.ORBIT_LEAVE_SPEED if pattern == "orbit" else CFG.HOVER_LEAVE_SPEED
		pos.y -= leave * dt
		if pos.y < -80.0:
			dead = true
		return

	match pattern:
		"sine":
			pos.y += speed * dt
			pos.x = anchor_x + sin(age * 1.5 + phase) * amp
			turn = -sin(age * 1.5 + phase) * deg_to_rad(11.5)
		"dive":
			if age > CFG.ENTRY_DELAY + entry_delay:
				if not dive_locked and player_pos_fn.is_valid():
					var t: Vector2 = player_pos_fn.call()
					dive_vel = (t - pos).normalized() * speed * CFG.DIVE_SPEED_MUL
					dive_locked = true
				pos += dive_vel * dt
				turn = dive_vel.angle() + PI / 2.0
			else:
				pos.y += CFG.DIVE_SLOW_SPEED * dt
		"hover":
			if age > CFG.ENEMY_LIFE_SECONDS:
				leaving = true
			elif pos.y < station_y:
				pos.y = minf(station_y, pos.y + speed * dt)
				pos.x = anchor_x + sin(age * 0.9 + phase) * CFG.APPROACH_WOBBLE
			else:
				var span := CFG.HOVER_BULWARK_SPAN if kind == "bulwark" else CFG.HOVER_SPAN
				pos.x = anchor_x + sin(age * 0.7 + phase) * span + sin(age * 0.23) * CFG.HOVER_SECOND_AMP
				pos.y = station_y + sin(age * 1.1 + phase) * CFG.HOVER_BOB
				turn = -cos(age * 0.7 + phase) * deg_to_rad(8.6)
		"orbit":
			if age > CFG.ENEMY_LIFE_SECONDS:
				leaving = true
			elif pos.y < station_y:
				pos.y = minf(station_y, pos.y + speed * dt)
				pos.x = anchor_x + sin(age * 0.9 + phase) * CFG.APPROACH_WOBBLE
			else:
				pos.x = anchor_x + cos(age * CFG.ORBIT_RATE + phase) * CFG.ORBIT_RADIUS
				pos.y = station_y + sin(age * CFG.ORBIT_RATE + phase) * CFG.ORBIT_RADIUS_Y
		"rock":
			pos.y += speed * dt
			pos.x += sin(age * 0.6 + phase) * CFG.ROCK_DRIFT * dt
			spin += deg_to_rad(40.0) * dt
		"strafe":
			if pos.y < station_y:
				pos.y = minf(station_y, pos.y + CFG.STRAFE_DROP_SPEED * dt)
			else:
				pos.y = station_y + sin(age * 1.8 + phase) * CFG.STRAFE_BOB
				pos.x += dir_sign * speed * dt
				turn = deg_to_rad(90.0) * dir_sign

	# 出屏回收（含横向，原版 entities.js:1382）
	if pos.y > CFG.HEIGHT + 70.0 or pos.x < -135.0 or pos.x > CFG.WIDTH + 135.0:
		dead = true


func _fire(dt: float, diff: Dictionary) -> void:
	var fire_mode = def.get("fire", null)
	# 母舰召唤（上半屏 45% 带内）
	if kind == "carrier" and not leaving and pos.y < CFG.HEIGHT * CFG.CARRIER_BAND_TOP_FRAC and pos.y > 20.0:
		summon_t -= dt
		if summon_t <= 0.0:
			summon_t = CFG.CARRIER_SUMMON_EVERY
			if spawn_child.is_valid():
				var shard := randf() < CFG.CARRIER_SHARDLING_CHANCE
				var px := clampf(pos.x + randf_range(-size, size), 30.0, CFG.WIDTH - 30.0)
				spawn_child.call("shardling" if shard else "wasp", Vector2(px, pos.y + size * 0.6))

	if fire_mode == null or leaving:
		return
	# 开火带：y∈(20, H×0.8)
	if pos.y < 20.0 or pos.y > CFG.HEIGHT * 0.8:
		return
	if not player_pos_fn.is_valid():
		return

	var charge_def := float(def.get("charge", 0.0))
	if charge > 0.0:
		charge -= dt
		if charge <= 0.0:
			_do_fire(diff)
			fire_timer = next_interval(diff)
		return

	fire_timer -= dt
	if fire_timer > 0.0:
		return
	if charge_def > 0.0:
		charge = charge_def * (CFG.ENEMY_CHARGE_ELITE_MUL if elite else 1.0)
		return
	_do_fire(diff)
	fire_timer = next_interval(diff)


func _do_fire(diff: Dictionary) -> void:
	if not spawn_bullet.is_valid() or not player_pos_fn.is_valid():
		return
	var fire_mode = def.get("fire", "aimed")
	var sp := CFG.enemy_bullet_speed(tier, float(diff["bulletSpeed"]))
	var from := pos + Vector2(0, size * 0.4)
	var target: Vector2 = player_pos_fn.call()
	var aim := (target - pos).angle()
	var tint := Color.html(String(def.get("glow", "#ff6f91")))

	# 内部 helpers：按角度/速度生成一颗敌弹
	var add := func(deg: float, speed: float, bkind: String, r: float) -> void:
		var a := deg
		spawn_bullet.call(from, Vector2(cos(a), sin(a)) * speed, _bullet_tint(bkind, tint), r, bkind, 9.0)
	var fan := func(n: int, spread_deg: float, speed: float, bkind: String, r: float) -> void:
		for i in range(n):
			add.call(aim + (i - (n - 1) * 0.5) * deg_to_rad(spread_deg), speed, bkind, r)

	match String(fire_mode):
		"aimed":
			add.call(aim, sp, "orb", 6.0)
			if elite:
				fan.call(3, 11.5, sp * 0.95, "shard", 6.0)
		"fan":
			fan.call(5 if elite else 3, 10.3, sp * 0.95, "shard", 6.0)
		"ring":
			var n := 14 if elite else 10
			var off := age * 0.5
			for i in range(n):
				add.call(off + i * TAU / n, sp * 0.72, "orb", 6.0)
		"spread":
			add.call(aim - deg_to_rad(18.3), sp * 0.8, "orb", 6.0)
			add.call(aim + deg_to_rad(18.3), sp * 0.8, "orb", 6.0)
		"heavy":
			if elite:
				add.call(aim - deg_to_rad(12.6), sp * 0.42, "plasma", 13.0)
				add.call(aim + deg_to_rad(12.6), sp * 0.42, "plasma", 13.0)
			fan.call(3, 14.9, sp * 0.55, "heavy", 10.0)
		"needle":
			fan.call(5 if elite else 3, 4.3, 330.0, "needle", 5.0)
		"mines":
			var n := 4 if elite else 3
			for i in range(n):
				var a := aim + (i - (n - 1) * 0.5) * deg_to_rad(31.5)
				spawn_bullet.call(from, Vector2(cos(a), sin(a)) * 105.0, _bullet_tint("mine", tint), 9.0, "mine", 8.0)
		"wavefire":
			add.call(aim - deg_to_rad(20.6), sp * 0.82, "wave", 7.0)
			add.call(aim + deg_to_rad(20.6), sp * 0.82, "wave", 7.0)
			add.call(aim, sp * 1.1, "needle", 5.0)
		"carrier":
			add.call(aim - deg_to_rad(9.2), sp * 0.6, "orb", 7.0)
			add.call(aim + deg_to_rad(9.2), sp * 0.6, "orb", 7.0)
		_:
			add.call(aim, sp, "orb", 6.0)


static func _bullet_tint(bkind: String, fallback: Color) -> Color:
	match bkind:
		"needle":
			return Color(0.55, 0.98, 0.95)
		"mine":
			return Color(1.0, 0.85, 0.35)
		"heavy", "plasma":
			return Color(1.0, 0.86, 0.55)
		_:
			return fallback