extends SceneTree

# Numeric contract gate for the Godot migration.
# Run: godot --headless --path . --script res://tools/verify_numbers.gd
const CFG := preload("res://scripts/game_config.gd")
const BOSS := preload("res://scripts/boss.gd")

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
	_eq(failures, "beh.bossCd.desperate", CFG.boss_spell_cd(2, 0, 1, true), 0.16)
	# 破防醒来补招封顶 0.55；NaN/Inf 不许卡死
	_eq(failures, "beh.bossResume.clamp", CFG.boss_resume_timer(5.0), 0.55)
	_eq(failures, "beh.bossResume.keep", CFG.boss_resume_timer(0.2), 0.2)
	_eq(failures, "beh.bossResume.nan", CFG.boss_resume_timer(NAN), 0.55)
	_eq(failures, "beh.bossResume.inf", CFG.boss_resume_timer(INF), 0.55)
	# Boss 弹速：阶段乘数（×不是÷）+ 难度系数
	_eq(failures, "beh.bossSpeed.p0", (CFG.BOSS_BULLET_SPEED_BASE + CFG.BOSS_BULLET_SPEED_PER_TIER * 0) * CFG.BOSS_BULLET_SPEED_DIV[0] * 1.0, 152.0)
	_eq(failures, "beh.bossSpeed.p2", (CFG.BOSS_BULLET_SPEED_BASE + CFG.BOSS_BULLET_SPEED_PER_TIER * 0) * CFG.BOSS_BULLET_SPEED_DIV[2] * 1.0, 152.0 * 1.18)
	_eq(failures, "beh.bossSpeed.abyss", (CFG.BOSS_BULLET_SPEED_BASE) * 1.0 * 1.12, 152.0 * 1.12)
	# 星爆经济常量
	_eq(failures, "beh.nova.detunedMul", CFG.DETUNED_NOVA_MUL, 0.45)
	_eq(failures, "beh.nova.hitEnemy", CFG.NOVA_ON_HIT_ENEMY, 0.06)
	_eq(failures, "beh.nova.hitBoss", CFG.NOVA_ON_HIT_BOSS, 0.12)
	_eq(failures, "beh.nova.bossFrac", CFG.NOVA_BOSS_DAMAGE_FRAC, 0.06)
	_eq(failures, "beh.nova.bossFlat", CFG.NOVA_BOSS_DAMAGE_FLAT, 30.0)
	# 超频击杀延长
	_eq(failures, "beh.od.killExtend", CFG.OVERDRIVE_KILL_EXTEND, 0.11)
	_eq(failures, "beh.od.eliteExtend", CFG.OVERDRIVE_ELITE_KILL_EXTEND, 0.26)
	_eq(failures, "beh.od.max", CFG.OVERDRIVE_MAX, 9.5)
	# 反射护盾
	_eq(failures, "beh.reflect.duration", CFG.REFLECT_DURATION, 8.0)
	_eq(failures, "beh.reflect.invuln", CFG.INVULN_AFTER_REFLECT, 1.5)
	_eq(failures, "beh.reflect.nova", CFG.NOVA_ON_REFLECT_SAVE, 4.0)
	# 僚机点防封顶
	_eq(failures, "beh.aegis.cap", CFG.AEGIS_PD_CLEAR_COUNT, 4)

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
	_eq(failures, "beh.boss.roster", Boss.NAMES.size(), 10)
	_eq(failures, "beh.boss.finalHp", Boss.BASE_HP[5], 500.0)

	# ---- 补给节奏（Unity Director：首箱 20s 之后 19s、中途补给 55%、保底 3）----
	_eq(failures, "beh.supply.first", CFG.SUPPLY_INTERVAL, 20.0)
	_eq(failures, "beh.supply.then", CFG.SUPPLY_INTERVAL_MIN, 19.0)
	_eq(failures, "beh.supply.midProgress", CFG.SUPPLY_MID_PROGRESS, 0.55)
	_eq(failures, "beh.supply.pity", CFG.PITY_THRESHOLD, 3)
	_eq(failures, "beh.supply.swapIdle", CFG.SWAP_IDLE_FOR_SWAP_CRATE, 10.0)
	_eq(failures, "beh.supply.swapChance", CFG.SWAP_CRATE_CHANCE, 0.62)

	# ---- 补给箱物理与经济（Unity SupplyCrate）----
	_eq(failures, "beh.crate.fallSpeed", CFG.CRATE_FALL_SPEED, 75.6)
	_eq(failures, "beh.crate.pickupR", CFG.CRATE_PICKUP_R, 30.0)
	_eq(failures, "beh.crate.spinDeg", CFG.CRATE_SPIN_DEG, 42.0)
	_eq(failures, "beh.crate.gemScore", CFG.CRATE_GEM_SCORE, 25)
	_eq(failures, "beh.crate.gemNova", CFG.NOVA_ON_GEM, 0.5)
	_eq(failures, "beh.crate.fullWeapon", CFG.CRATE_FULL_WEAPON_SCORE, 800)
	_eq(failures, "beh.crate.fullShield", CFG.CRATE_FULL_SHIELD_SCORE, 500)
	_eq(failures, "beh.crate.fullDrone", CFG.CRATE_FULL_DRONE_SCORE, 600)
	_eq(failures, "beh.crate.fullLine", CFG.CRATE_FULL_LINE_SCORE, 1200)
	_eq(failures, "beh.crate.fullLife", CFG.CRATE_FULL_LIFE_SCORE, 1000)
	_eq(failures, "beh.crate.kinds", Crate.KINDS.size(), 9)

	# ---- Boss 入场 / 预告 / 几何（Unity BossController + Director）----
	_eq(failures, "beh.bossFlow.warn", CFG.BOSS_WARN_SECONDS, 3.0)
	_eq(failures, "beh.bossFlow.clearHold", CFG.SECTOR_CLEAR_SECONDS, 4.4)
	_eq(failures, "beh.bossFlow.entrySpeed", CFG.BOSS_ENTRY_SPEED, 118.8)
	_eq(failures, "beh.bossFlow.entryY", CFG.BOSS_ENTRY_START_Y, -81.0)
	_eq(failures, "beh.bossFlow.anchor960", CFG.boss_anchor_y(960.0), 259.2)
	_eq(failures, "beh.bossFlow.anchorSmall", CFG.boss_anchor_y(800.0), 252.0)
	_eq(failures, "beh.bossFlow.muzzleFrac", CFG.BOSS_MUZZLE_FRAC, 0.35)
	_eq(failures, "beh.bossFlow.bulletLife", CFG.BOSS_BULLET_LIFE, 10.0)
	_eq(failures, "beh.bossFlow.mineLife", CFG.BOSS_MINE_LIFE, 8.0)
	_eq(failures, "beh.bossFlow.seekerHoming", CFG.BOSS_SEEKER_HOMING, 2.6)
	_eq(failures, "beh.bossFlow.seekerTurn", CFG.BOSS_SEEKER_TURN, 1.9)
	_eq(failures, "beh.bossFlow.seekerSpeedMul", CFG.BOSS_SEEKER_SPEED_MUL, 0.58)
	_eq(failures, "beh.bossFlow.wallCols", CFG.wall_gap_cols(540.0), 14)
	_eq(failures, "beh.bossFlow.wallGap.p2t0", CFG.wall_gap_width(2, 0), 3)
	_eq(failures, "beh.bossFlow.wallGap.p0t1", CFG.wall_gap_width(0, 1), 3)
	_eq(failures, "beh.bossFlow.chargeTarget", CFG.charge_target_y(259.2, 960.0), 662.4)

	# ---- 弹体行为常量（Unity Projectile：水雷/波动/等离子/挥发型）----
	_eq(failures, "beh.bullet.mineDrag", CFG.MINE_DRAG, 3.8)
	_eq(failures, "beh.bullet.mineArmedFlash", CFG.MINE_ARMED_FLASH, 0.9)
	_eq(failures, "beh.bullet.mineCount", CFG.MINE_BURST_COUNT, 10)
	_eq(failures, "beh.bullet.mineSpeed.z1", CFG.mine_burst_speed(1), 130.0)
	_eq(failures, "beh.bullet.mineSpeed.z10", CFG.mine_burst_speed(10), 148.0)
	_eq(failures, "beh.bullet.mineShardLife", CFG.MINE_SHARD_LIFE, 7.0)
	_eq(failures, "beh.bullet.wavePhaseRate", CFG.WAVE_PHASE_RATE, 7.2)
	_eq(failures, "beh.bullet.plasmaCount", CFG.PLASMA_BURST_COUNT, 6)
	_eq(failures, "beh.bullet.plasmaSpeed", CFG.PLASMA_BURST_SPEED, 105.0)
	_eq(failures, "beh.bullet.plasmaShardLife", CFG.PLASMA_SHARD_LIFE, 7.0)
	_eq(failures, "beh.bullet.volatileFuse", CFG.VOLATILE_FUSE, 0.5)
	_eq(failures, "beh.bullet.volatileSplit", CFG.VOLATILE_SPLIT, 6)
	_eq(failures, "beh.beam.lengthMul", CFG.BEAM_LENGTH_MUL, 2.0)
	_eq(failures, "beh.beam.tail", CFG.BEAM_TAIL, 0.12)
	_eq(failures, "beh.bullet.cap", CFG.MAX_ENEMY_BULLETS, 420)

	# ---- 僚机挂点 / 射速（Unity DroneShip）----
	_eq(failures, "beh.drone.slots3", CFG.DRONE_SLOTS_3[2], Vector2(44, 62))
	# 三机编队不得遮挡尾焰/子弹中列：第三槽 |x| 需大于机体半宽 + 僚机半宽，
	# y 需落在机体下缘之下且仍在玩家最低点（view-104）的可视范围内
	_eq(failures, "beh.drone.clearFlame", absf(CFG.DRONE_SLOTS_3[2].x) >= 42.0, true)
	_eq(failures, "beh.drone.onScreen", CFG.DRONE_SLOTS_3[2].y + 18.0 <= 104.0, true)
	_eq(failures, "beh.drone.cd.aegis", CFG.drone_fire_cd("aegis", "pulse"), 0.5)
	_eq(failures, "beh.drone.cd.swarmGunner", CFG.drone_fire_cd("gunner", "swarm"), 0.86)
	_eq(failures, "beh.drone.cd.prismLance", CFG.drone_fire_cd("lance", "prism"), 0.82)
	_eq(failures, "beh.drone.cd.pulseGunner", CFG.drone_fire_cd("gunner", "pulse"), 0.34)

	# ---- 几何 / 加权抽取纯函数 ----
	_eq(failures, "beh.ray.perp", CFG.point_ray_distance(Vector2(100, 30), Vector2.ZERO, 0.0, 200.0), 30.0)
	_eq(failures, "beh.ray.behind", CFG.point_ray_distance(Vector2(-10, 0), Vector2.ZERO, 0.0, 200.0), 10.0)
	_eq(failures, "beh.ray.pastEnd", CFG.point_ray_distance(Vector2(250, 0), Vector2.ZERO, 0.0, 200.0), 50.0)
	_eq(failures, "beh.weighted.first", CFG.weighted_pick([38, 17, 13, 6, 6, 5, 4, 11], 0.0), 0)
	_eq(failures, "beh.weighted.last", CFG.weighted_pick([38, 17, 13, 6, 6, 5, 4, 11], 0.999999), 7)
	_eq(failures, "beh.weighted.mid", CFG.weighted_pick([1, 1], 0.75), 1)

	# ---- 武器线升级 / 换线行为（Unity GrantLevel / GrantLine / SwapToBest）----
	var ws := WeaponSystem.new()
	_eq(failures, "beh.ws.startLevel", ws.active().level, CFG.START_PULSE_LEVEL)
	_eq(failures, "beh.ws.grantLevel", ws.grant_level(), true)
	ws.grant_level()
	ws.grant_level()
	_eq(failures, "beh.ws.maxLevel", ws.active().level, 5)
	_eq(failures, "beh.ws.grantUnlocksPrism", ws.grant_level(), true)
	_eq(failures, "beh.ws.prismActive", ws.active_id, "prism")
	_eq(failures, "beh.ws.prismCharge", ws.line("prism").charge, 100.0)
	_eq(failures, "beh.ws.grantLineSwarm", ws.grant_line("swarm"), true)
	_eq(failures, "beh.ws.swarmActive", ws.active_id, "swarm")
	ws.line("pulse").charge = 90.0
	ws.line("prism").charge = 40.0
	_eq(failures, "beh.ws.swapPicksBest", ws.swap_to_best(30.0), true)
	_eq(failures, "beh.ws.swapToPulse", ws.active_id, "pulse")
	_eq(failures, "beh.ws.swapTopUpCap", ws.line("pulse").charge, 100.0)
	var ws2 := WeaponSystem.new()
	ws2.active().charge = 10.0
	_eq(failures, "beh.ws.swapSoloFalse", ws2.swap_to_best(30.0), false)
	_eq(failures, "beh.ws.swapSoloRecharge", ws2.active().charge, 55.0)

	# ---- v1.7.0：动态天候轮换 + 三星评级阈值（参考《像素飞机大战》）----
	_eq(failures, "beh.weather.z1", CFG.weather_for_zone(1), "clear")
	_eq(failures, "beh.weather.z3", CFG.weather_for_zone(3), "rain")
	_eq(failures, "beh.weather.z4", CFG.weather_for_zone(4), "storm")
	_eq(failures, "beh.weather.z5", CFG.weather_for_zone(5), "clear")
	_eq(failures, "beh.weather.z22Cycle", CFG.weather_for_zone(22), "clear")
	_eq(failures, "beh.stars.survive", CFG.run_stars(1, 3, 10, 0, 100), 1)
	_eq(failures, "beh.stars.kills", CFG.run_stars(1, 3, 120, 0, 100), 2)
	_eq(failures, "beh.stars.graze", CFG.run_stars(1, 3, 0, 40, 100), 2)
	_eq(failures, "beh.stars.fullHull", CFG.run_stars(3, 3, 120, 40, 20000), 3)
	_eq(failures, "beh.stars.lowHull", CFG.run_stars(2, 3, 120, 40, 20000), 2)
	_eq(failures, "beh.stars.lowScore", CFG.run_stars(3, 3, 120, 40, 19999), 2)

	# ---- v1.9.0：10 台专属 Boss / 无尽深度 / 护盾环绕 ----
	_eq(failures, "beh.boss.count", BOSS.NAMES.size(), 10)
	_eq(failures, "beh.boss.namesUnique", _unique_count(BOSS.NAMES), 10)
	_eq(failures, "beh.boss.seqCount", BOSS.SEQUENCES.size(), 10)
	_eq(failures, "beh.boss.seqPhases", BOSS.SEQUENCES[9].size(), 3)
	_eq(failures, "beh.boss.zone1", CFG.boss_index_for(1, "campaign"), 0)
	_eq(failures, "beh.boss.zone10", CFG.boss_index_for(10, "campaign"), 9)
	_eq(failures, "beh.boss.zone11Endless", CFG.boss_index_for(11, "endless"), 0)
	_eq(failures, "beh.boss.zone20Endless", CFG.boss_index_for(20, "endless"), 9)
	_eq(failures, "beh.endless.z10", CFG.endless_scale(10), 1.0)
	_eq(failures, "beh.endless.z11", CFG.endless_scale(11), 1.2)
	_eq(failures, "beh.endless.z20", CFG.endless_scale(20), 1.2)
	_eq(failures, "beh.endless.z21", CFG.endless_scale(21), 1.44)
	_eq(failures, "beh.endless.z31", CFG.endless_scale(31), 1.728)
	_eq(failures, "beh.endless.bulletSpeed", CFG.enemy_bullet_speed(0, 1.0, 11),
		CFG.enemy_bullet_speed(0, 1.0, 10) * 1.2)
	_eq(failures, "beh.shield.radius", CFG.SHIELD_ORBIT_RADIUS, 44.0)
	_eq(failures, "beh.shield.speed", CFG.SHIELD_ORBIT_SPEED, 1.6)

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


func _unique_count(arr: Array) -> int:
	var seen := {}
	for v in arr:
		seen[v] = true
	return seen.size()
