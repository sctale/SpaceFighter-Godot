class_name GameConfig
extends RefCounted

# Values copied from space-fighter web/www/js (540x960 design space).
const WIDTH := 540.0
const HEIGHT := 960.0

# 运行时视口：540x960 只是设计基准。Main 会根据手机实际屏幕改成
# 例如 540x1200（长屏）或 720x960（平板），玩法边界与 HUD 全部跟随 VIEW。
static var VIEW := Vector2(WIDTH, HEIGHT)
static var SAFE_TOP := 0.0
static var SAFE_BOTTOM := 0.0
static var SAFE_LEFT := 0.0
static var SAFE_RIGHT := 0.0

static func set_view(size: Vector2) -> void:
	VIEW = size

static func set_safe(top: float, bottom: float, left: float, right: float) -> void:
	SAFE_TOP = top
	SAFE_BOTTOM = bottom
	SAFE_LEFT = left
	SAFE_RIGHT = right

const PLAYER_HIT_R := 4.6
const PLAYER_GRAZE_R := 28.0
const PLAYER_SPEED := 440.0
const PLAYER_MIN_Y_RATIO := 0.18
const PLAYER_BOTTOM_MARGIN := 104.0

const WEAPON_LINES := {
	"pulse": {
		"label": "脉冲", "tint": "#69f5dc", "deep": "#2bb3a2",
		"speed": 1250.0, "drain": 7.4, "recover": 15.5,
	},
	"prism": {
		"label": "棱镜", "tint": "#ff6f91", "deep": "#b8395c",
		"speed": 560.0, "drain": 10.5, "recover": 12.0,
	},
	"swarm": {
		"label": "蜂群", "tint": "#ffd27a", "deep": "#d28f36",
		"speed": 830.0, "drain": 8.6, "recover": 13.5,
	},
}

# Pulse fire interval by level; level 2 is the starting weapon.
const FIRE_INTERVALS := {
	"pulse": [0.120, 0.108, 0.098, 0.090, 0.082],
	"prism": [0.360, 0.330, 0.305, 0.280, 0.245],
	"swarm": [0.250, 0.210, 0.180, 0.160, 0.145],
}

const RESONANCE_MAX := 5
const RESONANCE_WINDOW := 7.0
const DETUNE_REARM_CHARGE := 100.0
const DETUNE_CLEAR_CHARGE := 55.0
const SWAP_RESONANCE_GAP := 1.2
const VENT_RATIO := 2.4

const DIFFICULTY := {
	"cruise": {
		"name": "巡航", "enemyRate": 1.22, "bulletSpeed": 0.9,
		"bossBullet": 0.86, "bossHp": 0.9, "nova": 1.2, "scoreMul": 0.8,
	},
	"standard": {
		"name": "标准", "enemyRate": 1.0, "bulletSpeed": 1.0,
		"bossBullet": 1.0, "bossHp": 1.0, "nova": 1.0, "scoreMul": 1.0,
	},
	"abyss": {
		"name": "深渊", "enemyRate": 0.8, "bulletSpeed": 1.1,
		"bossBullet": 1.12, "bossHp": 1.18, "nova": 0.85, "scoreMul": 1.35,
	},
}

# Exact definitions from web/www/js/entities.js ENEMY_TYPES.
const ENEMY_TYPES := {
	"drifter": {
		"size": 17.0, "hp": 4.0, "score": 100, "color": "#ff6f91",
		"accent": "#ffd1dc", "glow": "#ff6f91", "pattern": "sine",
		"fire": "aimed", "fireCd": [1.6, 2.2], "speed": 78.0, "amp": 44.0, "drop": 0.1,
	},
	"wasp": {
		"size": 15.0, "hp": 3.0, "score": 150, "color": "#ff9ab4",
		"accent": "#ffffff", "glow": "#ff6f91", "pattern": "dive",
		"fire": null, "speed": 185.0, "drop": 0.06,
	},
	"lancer": {
		"size": 23.0, "hp": 15.0, "score": 280, "color": "#a597ff",
		"accent": "#ffd27a", "glow": "#9b8cff", "pattern": "hover",
		"fire": "fan", "fireCd": [1.6, 2.1], "speed": 55.0,
		"targetY": 0.23, "drop": 0.22,
	},
	"orbiter": {
		"size": 21.0, "hp": 19.0, "score": 340, "color": "#9b8cff",
		"accent": "#ffd27a", "glow": "#9b8cff", "pattern": "orbit",
		"fire": "ring", "fireCd": [2.0, 2.7], "speed": 50.0,
		"targetY": 0.27, "drop": 0.26,
	},
	"splitter": {
		"size": 20.0, "hp": 11.0, "score": 230, "color": "#ff6f91",
		"accent": "#ffd27a", "glow": "#ff6f91", "pattern": "sine",
		"fire": "spread", "fireCd": [1.8, 2.4], "speed": 64.0, "amp": 32.0, "drop": 0.2,
	},
	"bulwark": {
		"size": 30.0, "hp": 46.0, "score": 520, "color": "#c3cbe0",
		"accent": "#ffd27a", "glow": "#ffd27a", "pattern": "hover",
		"fire": "heavy", "fireCd": [1.8, 2.5], "speed": 36.0,
		"targetY": 0.2, "drop": 0.4,
	},
	"rock": {
		"size": 23.0, "hp": 14.0, "score": 70, "color": "#aab6cc",
		"accent": "#ffffff", "glow": "#9b8cff", "pattern": "rock",
		"fire": null, "speed": 48.0, "drop": 0.0,
	},
	"sniper": {
		"size": 22.0, "hp": 20.0, "score": 320, "color": "#69f5dc",
		"accent": "#ffffff", "glow": "#69f5dc", "pattern": "hover",
		"fire": "needle", "fireCd": [1.6, 2.1], "speed": 58.0,
		"targetY": 0.17, "charge": 0.55, "drop": 0.24,
	},
	"minekeeper": {
		"size": 24.0, "hp": 28.0, "score": 380, "color": "#ffd27a",
		"accent": "#ff6f91", "glow": "#ffd27a", "pattern": "hover",
		"fire": "mines", "fireCd": [2.4, 3.1], "speed": 42.0,
		"targetY": 0.25, "charge": 0.3, "drop": 0.3,
	},
	"sidewinder": {
		"size": 21.0, "hp": 17.0, "score": 310, "color": "#9b8cff",
		"accent": "#ff6f91", "glow": "#9b8cff", "pattern": "strafe",
		"fire": "wavefire", "fireCd": [1.25, 1.75], "speed": 135.0,
		"targetY": 0.33, "drop": 0.22,
	},
	"carrier": {
		"size": 34.0, "hp": 78.0, "score": 680, "color": "#8fa4c9",
		"accent": "#ffd27a", "glow": "#9b8cff", "pattern": "hover",
		"fire": "carrier", "fireCd": [2.0, 2.6], "speed": 32.0,
		"targetY": 0.13, "drop": 0.55,
	},
	"shardling": {
		"size": 13.0, "hp": 5.0, "score": 90, "color": "#ff9ab4",
		"accent": "#ffffff", "glow": "#ff6f91", "pattern": "dive",
		"fire": null, "speed": 215.0, "drop": 0.03,
	},
}

const PALETTE := {
	"white": "#f3f8ff",
	"teal": "#69f5dc",
	"tealDeep": "#2bb3a2",
	"violet": "#9b8cff",
	"violetDeep": "#5f52c7",
	"rose": "#ff6f91",
	"roseDeep": "#b8395c",
	"gold": "#ffd27a",
	"goldDeep": "#d28f36",
	"steel": "#8fa4c9",
	"ink": "#04060f",
}

static func color(key: String) -> Color:
	return Color.html(PALETTE.get(key, "#ffffff"))


# ============================================================================
# 完整玩法常量（移植自归档 Unity v0.21.14 GameConfig.cs，数值源头是 web/www/js）。
# Godot 直接用 540x960 设计像素，所以这里全部是"像素/秒"口径，不再乘 Px。
# ============================================================================

# ---- 玩家生存与开局（entities.js:375-385,704,753）----
const MAX_SHIELDS := 3
const START_LIVES := 3
const START_SHIELDS := 1
const START_DRONES := 0
const START_PULSE_LEVEL := 2
const START_UNLOCKED_LINES := 1
const BOUND_SIDE_INSET := 31.0
const BOUND_TOP_FRAC := 0.18
const BOUND_BOTTOM_INSET := 104.0
const RESPAWN_INSET := 120.0

# ---- 触屏驾驶（entities.js:721-734）----
const DRAG_FOLLOW_RATE := 30.0
const MOUSE_FOLLOW_RATE := 26.0
const DRAG_MAX_LATERAL := 162.0
const DRAG_LIFT := 140.0
const DRAG_DROP := 60.0

# ---- 冲刺与相位（entities.js:641-662,742）----
const DASH_TIME := 0.17
const DASH_COOLDOWN := 1.7
const DASH_SPEED := 1250.0
const DASH_INVULN := 0.36
const PHASE_RADIUS := 34.0
const PHASE_NOVA_PER_BULLET := 0.55
const PHASE_SCORE_PER_BULLET := 6

# ---- 无敌帧分级（entities.js:388,668；game.js:1198+）----
const INVULN_ON_SPAWN := 1.6
const INVULN_AFTER_HULL_HIT := 2.8
const INVULN_AFTER_SHIELD := 1.3
const INVULN_AFTER_REFLECT := 1.5
const INVULN_AFTER_NOVA := 0.9
const INVULN_ON_ZONE_CHANGE := 1.5
const INVULN_ON_BOSS_PHASE := 0.75
const SPAWN_GRACE := 1.2

# ---- 星爆 nova（entities.js:694-696；game.js:846+）----
const NOVA_REGEN_PER_SECOND := 1.8
const NOVA_ON_KILL := 2.5
const NOVA_ON_ELITE_KILL := 7.0
const NOVA_ON_GRAZE := 0.9
const NOVA_ON_HIT_ENEMY := 0.06
const NOVA_ON_HIT_BOSS := 0.12
const NOVA_ON_GEM := 0.5
const NOVA_ON_POINT_DEFENSE := 0.6
const NOVA_ON_HULL_HIT := 25.0
const NOVA_ON_SHIELD_BREAK := 8.0
const NOVA_ON_REFLECT_SAVE := 4.0
const DETUNED_NOVA_MUL := 0.45
const OVERDRIVE_TIME := 7.0
const OVERDRIVE_MAX := 9.5
const OVERDRIVE_KILL_EXTEND := 0.11
const OVERDRIVE_ELITE_KILL_EXTEND := 0.26
const OVERDRIVE_DAMAGE_MUL := 1.8
const OVERDRIVE_FIRE_RATE_MUL := 0.74
const NOVA_ENEMY_DAMAGE := 32.0
const NOVA_BOSS_DAMAGE_FRAC := 0.06
const NOVA_BOSS_DAMAGE_FLAT := 30.0
const NOVA_SCORE_PER_CLEARED_BULLET := 10
const CLEAR_SCORE_PER_BULLET := 4

# ---- 裂隙碎片（v1.2.0 擦弹风险回报）----
const MOTE_SCORE := 12
const MOTE_NOVA := 3.0
const MOTE_LIFE := 4.2
const MOTE_MAX := 30
const MOTE_MAGNET_RADIUS := 118.0
const MOTE_MAGNET_SPEED := 210.0
const MOTE_COLLECT_RADIUS := 22.0
const MOTE_COMBO_EXTEND := 0.65

# ---- 星区突破三选一（v1.2.0 局内 build）----
const UPGRADE_CARD_COUNT := 3
const UPGRADE_MAX_HULL := 4
const UPGRADE_DAMAGE_STEP := 0.12
const UPGRADE_DRONE_STEP := 0.25
const UPGRADE_NOVA_STEP := 0.25
const UPGRADE_OVERDRIVE_STEP := 1.5
const UPGRADE_SPEED_STEP := 0.08
const UPGRADE_SPEED_MAX := 1.30
const UPGRADE_CRATE_STEP := 0.25
const UPGRADE_BREAK_STEP := 0.25
const UPGRADE_RIFT_NOVA_STEP := 0.5
const UPGRADE_RIFT_SCORE_STEP := 0.3
const UPGRADE_POOL := [
	{"id": "damage", "name": "火力校准", "desc": "所有武器伤害 +12%",
	 "tint": "#FF8FB1", "icon": "burst"},
	{"id": "drone", "name": "僚机扩编", "desc": "僚机射速 +25%",
	 "tint": "#57E6D8", "icon": "ship"},
	{"id": "hull", "name": "船体强化", "desc": "最大船体 +1，并修复 1 格",
	 "tint": "#FFC554", "icon": "heart"},
	{"id": "shield", "name": "护盾矩阵", "desc": "立即获得 1 层护盾",
	 "tint": "#6FA8FF", "icon": "shield"},
	{"id": "nova", "name": "星爆核心", "desc": "星爆充能 +25%",
	 "tint": "#FFC554", "icon": "burst"},
	{"id": "overdrive", "name": "超频延长", "desc": "星爆超频 +1.5 秒",
	 "tint": "#A78BFA", "icon": "star"},
	{"id": "speed", "name": "流星推进", "desc": "移动速度 +8%",
	 "tint": "#57E6D8", "icon": "chevron"},
	{"id": "crate", "name": "战利品雷达", "desc": "补给箱出现 +25%",
	 "tint": "#FF8FB1", "icon": "star"},
	{"id": "break", "name": "破防弹头", "desc": "Boss 伤害 +25%",
	 "tint": "#FF6B7A", "icon": "burst"},
	{"id": "rift", "name": "裂隙共振", "desc": "裂隙碎片充能 +50%，得分 +30%",
	 "tint": "#A78BFA", "icon": "burst4"},
]

# ---- 武器市场经济（entities.js:336-362,863-931）----
const RESONANCE_PER_STACK_DAMAGE := 0.08
const RESONANCE_PER_STACK_CHARGE := 0.06
const DETUNED_DAMAGE_MUL := 0.55
const DETUNED_INTERVAL_MUL := 1.45
const SOLO_DRAIN_MUL := 0.55
const HIT_CHARGE_PENALTY := 45.0
const PRISM_DAMAGE := [4.0, 4.0, 5.0, 6.0, 6.0]
const PRISM_PIERCE := [1, 1, 2, 2, 3]
const PRISM_BOSS_BONUS := 1.18
const SWARM_COUNT := [2, 3, 4, 4, 4]
const SWARM_DAMAGE := [2.0, 2.0, 2.0, 3.0, 3.0]
const SWARM_HOMING := 1.45
const SWARM_TURN_RATE := 4.6
const SWARM_LOCK_DELAY := 0.11
const LINE_ALIASES := [
	["脉冲炮", "双联脉冲", "三叉星流", "四象阵列", "星瀑"],
	["棱镜", "双棱", "棱镜矩阵", "裂光", "终焉棱镜"],
	["蜂群", "双子蜂", "三蜂", "五蜂", "蜂后"],
]

# ---- 弹幕（game.js:763-779,1289）----
const BULLET_LIFETIME := 4.0
const MAX_ENEMIES_ALIVE := 42
const MAX_ENEMY_BULLETS := 420

# ---- 星区节奏（v1.3.0：把单区时长从约 20 秒拉到约 45 秒）----
const ZONE_QUOTA_BASE := 28
const ZONE_QUOTA_STEP := 4
const ZONE_MIN_TIME := 40.0
const MINE_DRAG := 3.8
const MINE_BURST_SPEED := 128.0
const WAVE_PHASE_RATE := 7.2
const PLASMA_BURST_SPEED := 105.0

# ---- 敌机缩放与精英（entities.js:1210-1233,1481-1493）----
const ENEMY_HP_PER_SECTOR := 0.16
const ENEMY_SPEED_PER_TIER := 0.14
const ENEMY_FIRE_PER_TIER := 0.10
const ENEMY_FIRE_INTERVAL_FLOOR := 0.7
const AFFIX_BASE_CHANCE := 0.16
const AFFIX_MAX_EXTRA := 0.14
const ELITE_SIZE_MUL := 1.22
const ELITE_HP_MUL := 2.4
const ELITE_SCORE_MUL := 3.2
const ELITE_FIRE_MUL := 0.82
const ARMORED_HP_MUL := 1.45
const ARMORED_DAMAGE_TAKEN_MUL := 0.72
const RAPID_SIZE_MUL := 0.92
const RAPID_FIRE_MUL := 0.72
const VOLATILE_HP_MUL := 0.9
const VOLATILE_FUSE := 0.5
const VOLATILE_SPLIT := 6
const ENTRY_DELAY := 0.35
const ENTRY_GRACE := 0.18
const ENTRY_TOP_INSET := 10.0
const ENTRY_BOTTOM_FRAC := 0.94
const ENEMY_COLLISION_SIZE := 0.78   # 判定半径 = size × 0.78（美术仍按 size）
const ENEMY_CHARGE_ELITE_MUL := 0.8
const ARMORED_SIZE_MUL := 1.06
const ARMORED_FIRE_MUL := 1.12
const ENEMY_LIFE_SECONDS := 16.0
const HOVER_LEAVE_SPEED := 170.0
const ORBIT_LEAVE_SPEED := 160.0
const STRAFE_DROP_SPEED := 120.0
const DIVE_SLOW_SPEED := 40.0
const DIVE_SPEED_MUL := 1.5
const HOVER_SPAN := 88.0
const HOVER_BULWARK_SPAN := 55.0
const HOVER_SECOND_AMP := 20.0
const HOVER_BOB := 8.0
const APPROACH_WOBBLE := 12.0
const ORBIT_RADIUS := 62.0
const ORBIT_RADIUS_Y := 24.0
const ORBIT_RATE := 1.15
const STRAFE_BOB := 16.0
const ROCK_DRIFT := 12.0
const CARRIER_SUMMON_EVERY := 3.6
const CARRIER_SHARDLING_CHANCE := 0.55
const CARRIER_BAND_TOP_FRAC := 0.45
const CARRIER_CHILD_ENTRY_DELAY := 0.15
const SPLITTER_CHILD_HP_FRAC := 0.5
const RANDOM_ELITE_CHANCE := 0.18

# ---- 连锁与计分（game.js:74-76,977-1021）----
const COMBO_WINDOW := 2.8
const COMBO_MAX_MULT := 8
const COMBO_STEP := 5

# ---- 打击停顿与慢镜（game.js:1015+）----
const FREEZE_KILL := 0.025
const FREEZE_HIT := 0.05
const FREEZE_PHASE := 0.06
const FREEZE_DESPERATE := 0.08
const FREEZE_NOVA := 0.1
const FREEZE_BOSS_DIE := 0.12
const SLOW_HIT_DUR := 0.3
const SLOW_HIT_SCALE := 0.5
const SLOW_NOVA_DUR := 0.4
const SLOW_NOVA_SCALE := 0.45
const SLOW_DEATH_DUR := 1.2
const SLOW_DEATH_SCALE := 0.28
const SLOW_BOSS_DIE_DUR := 1.4
const SLOW_BOSS_DIE_SCALE := 0.35

# ---- Boss（entities.js:1727-2040）----
const BOSS_HP_SECTOR_GROWTH := 0.70
const BOSS_HP_GROWTH_CAP := 3.4
const BOSS_PHASE_HIGH := 0.66
const BOSS_PHASE_LOW := 0.30
const BOSS_CRITICAL_FRAC := 0.12
const BOSS_MERCY_WINDOW := 1.15
const BOSS_BREAK_FLOOR := 90.0
const BOSS_BREAK_FRAC_OF_MAX_HP := 0.30
const BOSS_BREAK_STUN := 1.2
const BOSS_BREAK_DAMAGE_MUL := 1.35
const BOSS_TELEGRAPH := 0.5
const BOSS_IDLE_FIRE_PHASE1 := 0.95
const BOSS_IDLE_FIRE_PHASE2 := 0.66
const BOSS_BULLET_SPEED_BASE := 152.0
const BOSS_BULLET_SPEED_PER_TIER := 46.0
const BOSS_BULLET_SPEED_DIV := [1.0, 1.06, 1.18]
const BOSS_SPELL_CD := [0.85, 0.62, 0.42]
const BOSS_SPELL_CD_FLOOR := 0.3
const BOSS_CHAIN_CD := 0.16
const BOSS_CHAIN_EVERY_TIER0 := 4
const BOSS_CHAIN_EVERY_OTHER_TIER := 3
const BOSS_INITIAL_CD := 1.15
const BOSS_POST_BREAK_CD := 0.55
const BOSS_DESPERATE_CD := 0.45
const BOSS_DESPERATE_FRAC := 0.12
const BOSS_DESPERATE_RING_NORMAL := 0.45
const BOSS_DESPERATE_RING_OTHER_TIER := 0.65
const BOSS_DESPERATE_RING_HARD := 0.7
const BOSS_DESPERATE_RING_HARDEST := 0.9
const BOSS_FREE_RING_NORMAL := 16
const BOSS_FREE_RING_DESPERATE := 22
const BOSS_FREE_RING_SPEED_MUL := 0.75
const BOSS_CONTACT_RX := 0.85
const BOSS_CONTACT_RY := 0.70
const BOSS_CONTACT_PAD := 8.0
const BOSS_HIT_RX := 1.02
const BOSS_HIT_RY := 0.82
const BOSS_WARN_SECONDS := 3.0
const SECTOR_CLEAR_SECONDS := 4.4

# ---- 击破结算（game.js:1395-1400）----
const CLEAR_TIME_BONUS_BASE := 90.0
const CLEAR_TIME_BONUS_PER_SECOND := 40.0
const CLEAR_NO_HIT_BASE := 1200.0
const CLEAR_NO_HIT_PER_SECTOR := 200.0
const CLEAR_GRAZE_PER_HIT := 20.0
const CLEAR_BASE_SCORE := 4000.0
const CLEAR_BASE_PER_SECTOR := 900.0
const SECTOR_COMPENSATION_PER_ZONE := 500.0

# ---- 评级（ui.js:555-557）----
const GRADE_S := 120000
const GRADE_A := 60000
const GRADE_B := 22000
const GRADE_SECTOR_S := 8
const GRADE_SECTOR_A := 5
const GRADE_SECTOR_B := 3

# ---- 僚机（entities.js:612-633）----
const MAX_DRONES := 3
const DRONE_KINDS := ["gunner", "lance", "aegis", "swarm"]
const DRONE_SLOTS_1 := [Vector2(-64, 8)]
const DRONE_SLOTS_2 := [Vector2(-64, 8), Vector2(64, 8)]
const DRONE_SLOTS_3 := [Vector2(-68, 2), Vector2(68, 2), Vector2(0, 48)]
const AEGIS_PD_INTERVAL := 0.5
const AEGIS_PD_RADIUS := 38.0
const AEGIS_PD_CLEAR_COUNT := 4

# ---- 补给箱（game.js:1061-1086；director.js:230-303）----
const SUPPLY_INTERVAL := 20.0
const SUPPLY_INTERVAL_MIN := 19.0
const SUPPLY_MID_PROGRESS := 0.55
const PITY_THRESHOLD := 3
const SWAP_IDLE_FOR_SWAP_CRATE := 10.0
const SWAP_CRATE_CHANCE := 0.62
const REFLECT_DURATION := 8.0


# ============================================================================
# 纯函数（门禁直接断言）
# ============================================================================

static func weapon_name(id: String, level: int) -> String:
	var row := 1 if id == "prism" else (2 if id == "swarm" else 0)
	return LINE_ALIASES[row][clampi(level, 1, 5) - 1]


static func boss_hp_scale(zone: int) -> float:
	return 1.0 + minf(BOSS_HP_GROWTH_CAP, maxf(0, zone - 1) * BOSS_HP_SECTOR_GROWTH)


static func enemy_hp_scale(sector: int) -> float:
	return 1.0 + maxf(0, sector - 1) * ENEMY_HP_PER_SECTOR


static func pick_drone_kind(in_use: Array, roll: int) -> String:
	for k in DRONE_KINDS:
		if not in_use.has(k):
			return k
	return DRONE_KINDS[absi(roll) % DRONE_KINDS.size()]


## 敌机判定半径 = size × 0.78（美术外缘仍按 size，见 main.gd 的 ART_EXTENT）。
static func enemy_hit_radius(size_px: float) -> float:
	return size_px * ENEMY_COLLISION_SIZE


## 敌弹速度：min(300, 150×(1+tier×0.14)) × 难度 bulletSpeed（entities.js:1393）。
static func enemy_bullet_speed(tier: int, bullet_speed_mul: float) -> float:
	return minf(300.0, 150.0 * (1.0 + tier * 0.14)) * bullet_speed_mul


## Boss 出招间隔：阶段基础间隔，链招/临界压到地板（entities.js:1945-1967）。
static func boss_spell_cd(phase: int, tier: int, chain_count: int, desperate: bool) -> float:
	if desperate:
		return BOSS_DESPERATE_CD
	var chain_every := BOSS_CHAIN_EVERY_TIER0 if tier == 0 else BOSS_CHAIN_EVERY_OTHER_TIER
	if phase >= 2 and chain_count > 0 and chain_count % chain_every == 0:
		return BOSS_CHAIN_CD
	return maxf(BOSS_SPELL_CD_FLOOR, BOSS_SPELL_CD[clampi(phase, 0, 2)])


## 破防醒来补招计时封顶 0.55s；NaN/Inf 不许卡死状态机。
static func boss_resume_timer(timer: float) -> float:
	if is_nan(timer) or is_inf(timer):
		return BOSS_POST_BREAK_CD
	return minf(timer, BOSS_POST_BREAK_CD)
