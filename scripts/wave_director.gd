class_name WaveDirector
extends RefCounted

## 波次导演：星区配额 / 最短停留 / 队形生成 / 敌机工厂。
## 只持有“刷怪节奏”状态；玩家、Boss、UI 仍由 Main 持有。

const CFG := preload("res://scripts/game_config.gd")

var m  # Main（untyped 以便调用其私有方法，避免循环类型依赖）
var wave_timer := 2.0
var spawn_count := 0
var zone_kills := 0
var zone_time := 0.0


func _init(main_ref) -> void:
	m = main_ref


func reset() -> void:
	wave_timer = 2.0
	spawn_count = 0
	zone_kills = 0
	zone_time = 0.0


## 换区时清空击杀与计时，但保留当前波次节奏。
func begin_zone() -> void:
	zone_kills = 0
	zone_time = 0.0


func quota() -> int:
	return CFG.ZONE_QUOTA_BASE + int(m.zone) * CFG.ZONE_QUOTA_STEP


func progress() -> float:
	var kills_k := float(zone_kills) / maxf(1.0, float(quota()))
	var time_k := float(zone_time) / CFG.ZONE_MIN_TIME
	return clampf(minf(kills_k, time_k), 0.0, 1.0)


func density_tier() -> int:
	return mini(3, maxi(0, int(m.zone) - 1) / 5)


func tick(delta: float) -> void:
	# 打满本区配额且停留够最短时长才进 Boss；Boss 战期间停刷小怪
	if m.boss != null:
		return
	zone_time += delta
	if zone_kills >= quota() and zone_time >= CFG.ZONE_MIN_TIME:
		m._start_boss()
		return
	wave_timer -= delta
	if wave_timer > 0.0 or m.enemies.size() >= CFG.MAX_ENEMIES_ALIVE - 8:
		return
	var diff: Dictionary = CFG.DIFFICULTY[String(m.difficulty)]
	wave_timer = maxf(2.4, 4.4 - int(m.zone) * 0.18) * float(diff["enemyRate"])
	spawn_count += 1
	_spawn_wave(spawn_count)


func _roster_pool() -> Array:
	var pool := ["drifter", "wasp", "drifter", "lancer"]
	if m.zone >= 2:
		pool.append_array(["orbiter", "splitter"])
	if m.zone >= 3:
		pool.append_array(["rock", "sniper"])
	if m.zone >= 4:
		pool.append_array(["bulwark", "sidewinder"])
	if m.zone >= 5:
		pool.append_array(["minekeeper", "carrier"])
	return pool


## 队形：横排 / V 字 / 双列 / 集群 / 侧翼包抄，每 4 波夹一支精英小队。
func _spawn_wave(n: int) -> void:
	var pool := _roster_pool()
	var kind: String = pool[randi() % pool.size()]
	var elite_wave := n % 4 == 0
	var count := 3 + mini(4, int(m.zone) / 2)
	var affix := "none"
	if not elite_wave and randf() < CFG.AFFIX_BASE_CHANCE + minf(CFG.AFFIX_MAX_EXTRA, int(m.zone) * 0.02):
		affix = ["armored", "rapid", "volatile"][randi() % 3]
	var vw: float = m.view_size.x
	match n % 5:
		0:  # 横排
			for i in range(count):
				var x := 90.0 + i * (vw - 180.0) / maxf(1.0, count - 1.0)
				spawn_enemy(kind, Vector2(x, -40.0 - absf(i - (count - 1) * 0.5) * 18.0),
					elite_wave and i == count / 2, affix)
		1:  # V 字
			for i in range(count):
				var off := i - (count - 1) * 0.5
				spawn_enemy(kind, Vector2(vw * 0.5 + off * 62.0, -40.0 - absf(off) * 34.0),
					elite_wave and absf(off) < 0.6, affix)
		2:  # 双列
			for i in range(count):
				var side := -1.0 if i % 2 == 0 else 1.0
				var row := i / 2
				spawn_enemy(kind, Vector2(vw * 0.5 + side * 120.0, -40.0 - row * 52.0),
					elite_wave and i < 2, affix)
		3:  # 集群
			for i in range(count + 1):
				spawn_enemy(kind, Vector2(randf_range(70.0, vw - 70.0), -40.0 - i * 26.0),
					elite_wave and i == 0, affix)
		_:  # 侧翼包抄
			for i in range(count):
				var side := -1.0 if i < count * 0.5 else 1.0
				spawn_enemy(kind, Vector2(vw * 0.5 + side * (150.0 + i * 16.0), -40.0 - (i % 2) * 30.0),
					elite_wave and i == 0, affix)


func spawn_enemy(kind: String, pos: Vector2, elite := false, affix := "none",
		hp_frac := 1.0, entry_delay := 0.0) -> void:
	if not CFG.ENEMY_TYPES.has(kind):
		return
	var e := Enemy.new()
	e.setup(kind, CFG.ENEMY_TYPES[kind], pos, m.zone, density_tier(), elite, affix, hp_frac)
	e.entry_delay = entry_delay
	e.spawn_bullet = m._enemy_spawn_bullet
	e.spawn_child = spawn_child
	e.player_pos_fn = m._player_pos
	m.enemies.append(e)


func spawn_child(kind: String, pos: Vector2) -> void:
	if m.enemies.size() < 38:
		spawn_enemy(kind, pos, false, "none", 1.0, CFG.CARRIER_CHILD_ENTRY_DELAY)
