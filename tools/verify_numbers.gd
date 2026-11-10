extends SceneTree

# Numeric contract gate for the Godot migration.
# Run: godot --headless --path . --script res://tools/verify_numbers.gd
const CFG := preload("res://scripts/game_config.gd")

var checks := 0


func _initialize() -> void:
	var failures: Array = []

	_eq(failures, "WIDTH", CFG.WIDTH, 540.0)
	_eq(failures, "HEIGHT", CFG.HEIGHT, 960.0)
	_eq(failures, "PLAYER_HIT_R", CFG.PLAYER_HIT_R, 4.6)
	_eq(failures, "PLAYER_GRAZE_R", CFG.PLAYER_GRAZE_R, 28.0)
	_eq(failures, "PLAYER_SPEED", CFG.PLAYER_SPEED, 440.0)
	_eq(failures, "RESONANCE_MAX", CFG.RESONANCE_MAX, 5)
	_eq(failures, "MOTE_SCORE", CFG.MOTE_SCORE, 12)
	_eq(failures, "MOTE_NOVA", CFG.MOTE_NOVA, 3.0)
	_eq(failures, "UPGRADE_CARD_COUNT", CFG.UPGRADE_CARD_COUNT, 3)
	_eq(failures, "UPGRADE_MAX_HULL", CFG.UPGRADE_MAX_HULL, 4)
	_eq(failures, "UPGRADE_POOL", CFG.UPGRADE_POOL.size(), 10)
	_eq(failures, "UPGRADE_SPEED_MAX", CFG.UPGRADE_SPEED_MAX, 1.30)
	_eq(failures, "ZONE_QUOTA_BASE", CFG.ZONE_QUOTA_BASE, 26)
	_eq(failures, "ZONE_QUOTA_STEP", CFG.ZONE_QUOTA_STEP, 4)
	_eq(failures, "ZONE_MIN_TIME", CFG.ZONE_MIN_TIME, 30.0)
	# 每星区一段 BGM：缺任一文件即视为资源不完整
	var music_ok := 0
	for i in range(1, 11):
		if ResourceLoader.exists("res://assets/music/zone_%02d.ogg" % i):
			music_ok += 1
	_eq(failures, "music.zone_tracks", music_ok, 10)

	_eq(failures, "pulse.speed", CFG.WEAPON_LINES["pulse"]["speed"], 1250.0)
	_eq(failures, "prism.speed", CFG.WEAPON_LINES["prism"]["speed"], 560.0)
	_eq(failures, "swarm.speed", CFG.WEAPON_LINES["swarm"]["speed"], 830.0)
	_eq(failures, "pulse.drain", CFG.WEAPON_LINES["pulse"]["drain"], 7.4)
	_eq(failures, "prism.drain", CFG.WEAPON_LINES["prism"]["drain"], 10.5)
	_eq(failures, "swarm.drain", CFG.WEAPON_LINES["swarm"]["drain"], 8.6)
	_eq(failures, "pulse.recover", CFG.WEAPON_LINES["pulse"]["recover"], 15.5)
	_eq(failures, "prism.recover", CFG.WEAPON_LINES["prism"]["recover"], 12.0)
	_eq(failures, "swarm.recover", CFG.WEAPON_LINES["swarm"]["recover"], 13.5)
	_eq(failures, "pulse.lv2.interval", CFG.FIRE_INTERVALS["pulse"][1], 0.108)

	_eq(failures, "enemy.count", CFG.ENEMY_TYPES.size(), 12)
	_eq(failures, "drifter.hp", CFG.ENEMY_TYPES["drifter"]["hp"], 4.0)
	_eq(failures, "drifter.size", CFG.ENEMY_TYPES["drifter"]["size"], 17.0)
	_eq(failures, "wasp.speed", CFG.ENEMY_TYPES["wasp"]["speed"], 185.0)
	_eq(failures, "lancer.hp", CFG.ENEMY_TYPES["lancer"]["hp"], 15.0)
	_eq(failures, "orbiter.hp", CFG.ENEMY_TYPES["orbiter"]["hp"], 19.0)
	_eq(failures, "carrier.hp", CFG.ENEMY_TYPES["carrier"]["hp"], 78.0)
	_eq(failures, "shardling.speed", CFG.ENEMY_TYPES["shardling"]["speed"], 215.0)

	_eq(failures, "standard.enemyRate", CFG.DIFFICULTY["standard"]["enemyRate"], 1.0)
	_eq(failures, "abyss.scoreMul", CFG.DIFFICULTY["abyss"]["scoreMul"], 1.35)
	_eq(failures, "cruise.bulletSpeed", CFG.DIFFICULTY["cruise"]["bulletSpeed"], 0.9)
	_eq(failures, "palette.teal", CFG.PALETTE["teal"], "#69f5dc")

	# ---- 行为断言（移植自 Unity VerifyNumbers 的关键组）----
	# 敌机判定半径 = size × 0.78（美术仍按全尺寸）
	_eq(failures, "beh.enemyHitR.drifter", CFG.enemy_hit_radius(17.0), 13.26)
	_eq(failures, "beh.enemyHitR.bulwark", CFG.enemy_hit_radius(30.0), 23.4)
	# 敌弹速度随 tier 升档并封顶 300（entities.js:1393）
	_eq(failures, "beh.enemyBullet.t0", CFG.enemy_bullet_speed(0, 1.0), 150.0)
	_eq(failures, "beh.enemyBullet.t5", CFG.enemy_bullet_speed(5, 1.0), 255.0)
	_eq(failures, "beh.enemyBullet.cap", CFG.enemy_bullet_speed(10, 1.0), 300.0)
	_eq(failures, "beh.enemyBullet.cruise", CFG.enemy_bullet_speed(0, 0.9), 135.0)
	# 星区/难度血量曲线
	_eq(failures, "beh.enemyHp.s1", CFG.enemy_hp_scale(1), 1.0)
	_eq(failures, "beh.enemyHp.s6", CFG.enemy_hp_scale(6), 1.8)
	_eq(failures, "beh.bossHp.z1", CFG.boss_hp_scale(1), 1.0)
	_eq(failures, "beh.bossHp.z5", CFG.boss_hp_scale(5), 3.8)
	_eq(failures, "beh.bossHp.cap", CFG.boss_hp_scale(6), 4.4)
	# 武器别名：满级要有满级的叫法
	_eq(failures, "beh.alias.pulse1", CFG.weapon_name("pulse", 1), "脉冲炮")
	_eq(failures, "beh.alias.pulse5", CFG.weapon_name("pulse", 5), "星瀑")
	_eq(failures, "beh.alias.prism5", CFG.weapon_name("prism", 5), "终焉棱镜")
	_eq(failures, "beh.alias.swarm5", CFG.weapon_name("swarm", 5), "蜂后")
	_eq(failures, "beh.alias.clamp", CFG.weapon_name("swarm", 99), "蜂后")
	# 僚机种类优先补未拥有的（三个挂点凑三种）
	_eq(failures, "beh.drone.first", CFG.pick_drone_kind([], 0), "gunner")
	_eq(failures, "beh.drone.second", CFG.pick_drone_kind(["gunner"], 0), "lance")
	_eq(failures, "beh.drone.allUsed", CFG.DRONE_KINDS.has(CFG.pick_drone_kind(["gunner", "lance", "aegis", "swarm"], 7)), true)
	# Boss 出招节奏
	_eq(failures, "beh.bossCd.p1", CFG.boss_spell_cd(0, 0, 1, false), 0.85)
	_eq(failures, "beh.bossCd.p2", CFG.boss_spell_cd(1, 0, 1, false), 0.62)
	_eq(failures, "beh.bossCd.p3", CFG.boss_spell_cd(2, 1, 1, false), 0.42)
	_eq(failures, "beh.bossCd.chain", CFG.boss_spell_cd(2, 0, 4, false), 0.16)
	_eq(failures, "beh.bossCd.desperate", CFG.boss_spell_cd(2, 0, 1, true), 0.45)
	# 破防醒来补招封顶 0.55；NaN/Inf 不许卡死
	_eq(failures, "beh.bossResume.clamp", CFG.boss_resume_timer(5.0), 0.55)
	_eq(failures, "beh.bossResume.keep", CFG.boss_resume_timer(0.2), 0.2)
	_eq(failures, "beh.bossResume.nan", CFG.boss_resume_timer(NAN), 0.55)
	_eq(failures, "beh.bossResume.inf", CFG.boss_resume_timer(INF), 0.55)

	# ---- 武器经济纯函数（WeaponSystem）----
	_eq(failures, "beh.weapon.interval.pulse2", WeaponSystem.interval("pulse", 2, false, false), 0.108)
	_eq(failures, "beh.weapon.interval.detuned", WeaponSystem.interval("pulse", 2, false, true), 0.108 * 1.45)
	_eq(failures, "beh.weapon.interval.overdrive", WeaponSystem.interval("pulse", 2, true, false), 0.108 * 0.74)
	_eq(failures, "beh.weapon.cost.solo", WeaponSystem.charge_cost("pulse", 2, 1, false, false), 7.4 * 0.108 * 0.55)
	_eq(failures, "beh.weapon.cost.multi", WeaponSystem.charge_cost("pulse", 2, 2, false, false), 7.4 * 0.108)
	_eq(failures, "beh.weapon.resonance.needsDwell", WeaponSystem.resonance_gain(false, 100.0, false), false)
	_eq(failures, "beh.weapon.resonance.needsCharge", WeaponSystem.resonance_gain(true, 54.9, false), false)
	_eq(failures, "beh.weapon.resonance.needsRearm", WeaponSystem.resonance_gain(true, 100.0, true), false)
	_eq(failures, "beh.weapon.resonance.ok", WeaponSystem.resonance_gain(true, 55.0, false), true)

	# ---- Boss 22 招表 ----
	_eq(failures, "beh.bossMoves.count", Boss.MOVE_LABELS.size(), 22)
	_eq(failures, "beh.bossMoves.durations", Boss.MOVE_DURATIONS.size(), 22)
	_eq(failures, "beh.bossMoves.seqLen.gatekeeperP0", Boss.SEQUENCES[0][0].size(), 4)
	_eq(failures, "beh.bossMoves.seqLen.gatekeeperP1", Boss.SEQUENCES[0][1].size(), 6)
	_eq(failures, "beh.bossMoves.seqLen.weaverP0", Boss.SEQUENCES[1][0].size(), 5)
	_eq(failures, "beh.bossMoves.seqLen.heliosP2", Boss.SEQUENCES[2][2].size(), 6)
	_eq(failures, "beh.bossMoves.fanDur", Boss.MOVE_DURATIONS[0], 1.3)
	_eq(failures, "beh.bossMoves.chargeDur", Boss.MOVE_DURATIONS[15], 3.2)
	_eq(failures, "beh.bossMoves.label0", Boss.MOVE_LABELS[0], "扇形齐射")
	_eq(failures, "beh.bossMoves.label21", Boss.MOVE_LABELS[21], "新星爆发")

	# ---- 星区节奏 / 终局 ----
	_eq(failures, "beh.zone.minTime1", CFG.zone_min_time(1), 30.0)
	_eq(failures, "beh.zone.minTime10", CFG.zone_min_time(10), 40.8)
	_eq(failures, "beh.zone.quotaBase", CFG.ZONE_QUOTA_BASE, 26)
	_eq(failures, "beh.zone.quotaStep", CFG.ZONE_QUOTA_STEP, 4)
	_eq(failures, "beh.zone.finalNo", CFG.is_final_zone(9), false)
	_eq(failures, "beh.zone.finalYes", CFG.is_final_zone(10), true)
	_eq(failures, "beh.boss.roster", Boss.NAMES.size(), 6)
	_eq(failures, "beh.boss.finalHp", Boss.BASE_HP[5], 500.0)

	if failures.is_empty():
		print("VERIFY_OK checks=%d" % checks)
		quit(0)
	else:
		for f in failures:
			print("VERIFY_FAIL " + str(f))
		quit(1)


func _eq(failures: Array, label: String, actual, expected) -> void:
	checks += 1
	if actual is float and expected is float:
		if not is_equal_approx(actual, expected):
			failures.append("%s expected %s got %s" % [label, str(expected), str(actual)])
	elif actual != expected:
		failures.append("%s expected %s got %s" % [label, str(expected), str(actual)])
