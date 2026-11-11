class_name Boss
extends RefCounted

## Boss 状态机（逐行对齐归档 Unity v0.21.14 BossController.cs）：
## 22 个具名招式、分时队列 At()/TickPending()、连续发射器 _emitter、
## 三台 Boss 各阶段固定序列（可背板）、0.5s 预告、66%/30% 阶段、12% 临界、
## 破防冻结与醒来补招、看门狗。坐标 y 向下（画布像素）。

const CFG := preload("res://scripts/game_config.gd")

const NAMES := ["阿刻戎", "薇尔", "赫利俄斯", "塔罗斯", "许德拉", "塞拉弗"]
const TITLES := ["守门人", "织星者", "新星核心", "铁壁", "噬星者", "裁决者"]
const BASE_HP := [400.0, 380.0, 440.0, 520.0, 470.0, 500.0]
const SIZES := [76.0, 80.0, 82.0, 88.0, 86.0, 84.0]
# 装饰环转速（Unity _ringSpeed，度/秒）：守门人 18 / 织星者 -32 / 新星核心 14
const RING_SPEED_DEG := [18.0, -32.0, 14.0]

# 22 招：名称与时长（BossMoves.cs）
const MOVE_LABELS := [
	"扇形齐射", "星旋回廊", "环状爆发", "追踪星群", "双生扫射", "十字光牢",
	"母舰召唤", "重弹压制", "双子光矛", "雷区播种", "相位闪现", "星网绞杀",
	"波动弹幕", "裂隙光幕", "星脉脉冲", "贯穿冲撞", "光牢旋扫", "陨星暴雨",
	"猎群连射", "逆向双旋", "环形雷阵", "新星爆发",
]
const MOVE_DURATIONS := [
	1.3, 2.0, 1.05, 1.0, 2.5, 2.0, 1.15, 1.9, 2.2, 2.0,
	2.2, 2.4, 2.0, 2.8, 2.2, 3.2, 2.9, 3.1, 2.7, 2.4,
	1.9, 2.6,
]
# 六台 Boss × 三阶段固定序列（前三台照抄 Unity，后三台沿用 Godot 扩展）
const SEQUENCES := [
	[[0, 13, 8, 9], [1, 13, 14, 0, 8, 4], [15, 16, 13, 17, 2, 1]],
	[[2, 3, 18, 5, 12], [19, 10, 18, 6, 5], [16, 11, 19, 18, 2, 12]],
	[[1, 7, 11, 9], [21, 6, 8, 1, 7], [21, 16, 17, 11, 20, 7]],
	# 塔罗斯（宽体重炮）：重弹、雷区、光幕压制
	[[7, 9, 4, 2], [6, 7, 15, 9, 10], [14, 17, 21, 16, 9, 7]],
	# 许德拉（蛇形）：追踪、闪现、雷阵
	[[3, 12, 10, 13], [11, 19, 3, 12, 20], [18, 15, 21, 19, 12, 10]],
	# 塞拉弗（四翼）：光束、光牢、新星
	[[5, 8, 0, 14], [16, 5, 1, 17, 8], [21, 16, 5, 17, 8, 1]],
]
const BEAM_MOVES := [4, 5, 8, 11, 16]
const MOVE_MOVES := [10, 15]
const ORDNANCE_MOVES := [6, 9, 20]

var index := 0
var name_zh := ""
var title_zh := ""
var pos := Vector2.ZERO
var anchor := Vector2.ZERO
var size := 76.0
var hp := 400.0
var max_hp := 400.0
var phase := 0
var tier := 0
var zone := 1
var diff: Dictionary = {}
var entered := false
var dying := false
var die_t := 0.0
var stun := 0.0
var break_gauge := 0.0
var break_max := 90.0
var telegraph := -1.0
var timer := 1.0
var casting := false
var move_t := 0.0
var move_dur := 0.0
var cast_label := ""
var tell_color := Color.WHITE
var spin := 0.0
var age := 0.0
var chain_count := 0
var move_index := 0
var seq_index := 0
var desperate := false
var flash := 0.0
var _mercy := 0.0
var _idle_t := 0.0
var _hover_t := 0.0
var _bob_phase := 0.0
var _lock_move := false
# 分时队列：{at: 触发时刻, t: 已走时间, act: Callable}
var _pending: Array = []
var _emitter: Callable
var _emit_acc := 0.0
var _emit_angle := 0.0
var _gap_cols: Array = []
var _charge_x0 := 0.0
var _charge_x1 := 0.0
var _charge_y0 := 0.0
var _charge_y1 := 0.0
var _charge_dived := false

# func(pos, vel, color, radius, kind, life, extra:Dictionary)
var spawn_bullet: Callable
# func(kind, pos)
var spawn_child: Callable
var player_pos_fn: Callable
# func(angle, warn, active, width_px, sweep) — 光束（跟随本体）
var spawn_beam: Callable
# func(pos, color, size_px, life) — Unity Impact.Spawn 的放大淡出光斑
var fx_impact: Callable
# func(name) — "hit"/"boom"/"pick"（Godot Sfx 无 warn/switch，统一映射）
var sfx_fn: Callable
# func(amount_px, duration)
var shake_fn: Callable
# func(phase:int) — 阶段切换时通知 Main 给玩家无敌帧 + hitstop
var on_phase_change: Callable
# func() — 临界触发时通知 Main hitstop + 公告
var on_desperate: Callable

func setup(p_index: int, p_zone: int, p_tier: int, p_diff: Dictionary) -> void:
	index = clampi(p_index, 0, NAMES.size() - 1)
	name_zh = NAMES[index]
	title_zh = TITLES[index]
	tier = p_tier
	zone = p_zone
	diff = p_diff
	size = float(SIZES[index])
	max_hp = float(BASE_HP[index]) * CFG.boss_hp_scale(p_zone) * float(p_diff.get("bossHp", 1.0))
	hp = max_hp
	break_max = maxf(CFG.BOSS_BREAK_FLOOR, max_hp * CFG.BOSS_BREAK_FRAC_OF_MAX_HP)
	anchor = Vector2(CFG.VIEW.x * 0.5, CFG.boss_anchor_y(CFG.VIEW.y))
	pos = Vector2(anchor.x, CFG.BOSS_ENTRY_START_Y)
	timer = CFG.BOSS_INITIAL_CD
	telegraph = -1.0
	phase = 0
	entered = false
	dying = false
	desperate = false
	chain_count = 0
	seq_index = 0
	cast_label = ""
	_bob_phase = randf() * TAU
	_hover_t = 0.0
	_pending.clear()
	_emitter = Callable()

func hp_frac() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)

func hit_rx() -> float:
	return size * CFG.BOSS_HIT_RX

func hit_ry() -> float:
	return size * CFG.BOSS_HIT_RY

func contact_rx() -> float:
	return size * CFG.BOSS_CONTACT_RX + CFG.BOSS_CONTACT_PAD

func contact_ry() -> float:
	return size * CFG.BOSS_CONTACT_RY + CFG.BOSS_CONTACT_PAD

## Unity Update 顺序：视觉→mercy→入场→破防→TickPending→看门狗→阶段→临界→
## casting{Hover,TickMove}→telegraph→timer{IdleFire,Hover,选招}。
func tick(dt: float, _player_pos: Vector2) -> void:
	age += dt
	spin += dt * deg_to_rad(RING_SPEED_DEG[index % 3])
	flash = maxf(0.0, flash - dt)
	if dying:
		die_t += dt
		return
	if _mercy > 0.0:
		_mercy -= dt

	if not entered:
		if pos.y < anchor.y:
			pos.y = minf(anchor.y, pos.y + CFG.BOSS_ENTRY_SPEED * dt)
			return
		entered = true

	# 破防只做伤害窗口与表现，不冻结招式节拍/预告/出招计时
	if stun > 0.0:
		stun -= dt
		if stun <= 0.0:
			stun = 0.0
			timer = CFG.boss_resume_timer(timer)
	if stun < 0.0:
		stun = 0.0

	_tick_pending(dt)
	_watchdog()

	var frac := hp_frac()
	var want := 0 if frac > CFG.BOSS_PHASE_HIGH else (1 if frac > CFG.BOSS_PHASE_LOW else 2)
	var idle := not casting and telegraph <= 0.0 and _pending.is_empty()
	if want != phase and idle:
		_enter_phase(want)
		return

	# 临界：三阶段 + 血量 <12%，一次性触发，之后几乎不停顿
	if not desperate and phase == 2 and frac < CFG.BOSS_DESPERATE_FRAC and idle:
		desperate = true
		seq_index = 0
		timer = CFG.BOSS_DESPERATE_CD
		if on_desperate.is_valid():
			on_desperate.call()

	if casting:
		_hover(dt)
		_tick_move(dt)
		return

	if telegraph > 0.0:
		telegraph -= dt
		if telegraph <= 0.0:
			_begin_move()
		return

	timer -= dt
	_idle_fire(dt)
	_hover(dt)
	if timer <= 0.0:
		move_index = _next_move()
		chain_count += 1
		telegraph = CFG.BOSS_TELEGRAPH
		cast_label = MOVE_LABELS[move_index]
		tell_color = _tell(move_index)
		_sfx("hit")
		_impact(pos, tell_color, size * 2.6, 0.36)

func _next_move() -> int:
	var seq: Array = SEQUENCES[index][clampi(phase, 0, 2)]
	var mv := int(seq[seq_index % seq.size()])
	seq_index += 1
	return mv

func _tell(mv: int) -> Color:
	if BEAM_MOVES.has(mv):
		return Color.html("#ff5c8a")
	if MOVE_MOVES.has(mv):
		return Color.html("#9b8cff")
	if ORDNANCE_MOVES.has(mv):
		return Color.html("#ffc24b")
	return Color.html("#35e0c8")

func _enter_phase(want: int) -> void:
	phase = want
	seq_index = 0
	chain_count = 0
	break_gauge = 0.0
	stun = 0.0
	_mercy = CFG.BOSS_MERCY_WINDOW
	timer = CFG.BOSS_MERCY_WINDOW
	telegraph = -1.0
	cast_label = ""
	_impact(pos, Color(1.0, 0.7, 0.4, 0.7), size * 3.0, 0.4)
	if on_phase_change.is_valid():
		on_phase_change.call(phase)

## 悬停：直接赋值正弦轨迹（Unity Hover），位移类招式期间由招式接管。
func _hover(dt: float) -> void:
	if _lock_move:
		return
	_hover_t += dt
	var sway: float = CFG.BOSS_HOVER_SWAY[clampi(phase, 0, 2)]
	var rate := CFG.BOSS_HOVER_RATE_BASE + phase * CFG.BOSS_HOVER_RATE_STEP
	pos.x = CFG.VIEW.x * 0.5 + sin(_hover_t * rate + _bob_phase) * CFG.VIEW.x * sway
	pos.y = anchor.y + sin(_hover_t * 1.1 + _bob_phase) * (12.0 if phase >= 2 else 7.0)

## 待机小弹：phase≥1，mercy 期间抑制；±0.22rad 夹射、弹速×0.92、针弹 r5。
func _idle_fire(dt: float) -> void:
	if _mercy > 0.0 or phase < 1:
		return
	_idle_t -= dt
	if _idle_t > 0.0:
		return
	var n := 2 if phase >= 2 else 1
	var a := _aim_now()
	var spd := _boss_speed() * 0.92
	for i in range(n):
		_bullet(_muzzle(), a + (i - (n - 1) * 0.5) * CFG.BOSS_IDLE_SPREAD, spd, "needle", 5.0)
	_idle_t = CFG.BOSS_IDLE_FIRE_PHASE2 if phase >= 2 else CFG.BOSS_IDLE_FIRE_PHASE1

func _begin_move() -> void:
	casting = true
	move_t = 0.0
	move_dur = float(MOVE_DURATIONS[move_index])
	_lock_move = MOVE_MOVES.has(move_index)
	cast_label = MOVE_LABELS[move_index]
	_emit_acc = 0.0
	_emit_angle = randf() * TAU
	_charge_dived = false
	_gap_cols.clear()
	_emitter = Callable()
	_impact(pos, tell_color, size * 1.6, 0.3)
	if move_index == 15:
		# 贯穿冲撞：出招瞬间锁定玩家 x，俯冲目标 y 按实时视口算
		_charge_x0 = pos.x
		_charge_x1 = _player_now().x
		_charge_y0 = anchor.y - 30.0
		_charge_y1 = CFG.charge_target_y(anchor.y, CFG.VIEW.y)
	_build_beats()

func _tick_move(dt: float) -> void:
	move_t += dt
	if _emitter.is_valid():
		_emitter.call(dt)
	if move_index == 15:
		_tick_charge_body(dt)
	if move_t >= move_dur:
		_end_move()

func _end_move() -> void:
	casting = false
	_emitter = Callable()
	_lock_move = false
	cast_label = ""
	if move_index == 10:
		_impact(pos, _tint(), size * 2.4, 0.34)
	# 三阶段收招后概率白送一圈瞄准环弹（Unity EndMove）
	if phase == 2 and randf() < _free_ring_chance():
		var n := CFG.BOSS_FREE_RING_DESPERATE if desperate else CFG.BOSS_FREE_RING_NORMAL
		_ring_at(_aim_now(), n, _boss_speed() * CFG.BOSS_FREE_RING_SPEED_MUL, "orb", 6.0)
	timer = CFG.boss_spell_cd(phase, tier, chain_count, desperate)

func _free_ring_chance() -> float:
	if desperate:
		return CFG.BOSS_DESPERATE_RING_HARD if tier == 0 else CFG.BOSS_DESPERATE_RING_HARDEST
	return CFG.BOSS_DESPERATE_RING_NORMAL if tier == 0 else CFG.BOSS_DESPERATE_RING_OTHER_TIER

func _watchdog() -> void:
	if is_nan(timer) or is_inf(timer):
		timer = CFG.BOSS_POST_BREAK_CD
	if is_nan(telegraph) or is_inf(telegraph) or telegraph < -1.0:
		telegraph = -1.0
	if is_nan(stun) or stun < 0.0:
		stun = 0.0
	if casting and (is_nan(move_t) or is_nan(move_dur) or move_t > move_dur + 0.75):
		_end_move()

# ---------------------------------------------------------------- 分时队列

func _at(at: float, act: Callable) -> void:
	_pending.append({"at": at, "t": 0.0, "act": act})

func _tick_pending(dt: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var e: Dictionary = _pending[i]
		e["t"] = float(e["t"]) + dt
		if float(e["t"]) >= float(e["at"]):
			_pending.remove_at(i)
			var act: Callable = e["act"]
			if act.is_valid():
				act.call()

# ---------------------------------------------------------------- 发射原语

func _player_now() -> Vector2:
	if player_pos_fn.is_valid():
		return player_pos_fn.call()
	return pos + Vector2(0, 200)

func _aim_now() -> float:
	return (_player_now() - pos).angle()

func _muzzle() -> Vector2:
	return pos + Vector2(0, size * CFG.BOSS_MUZZLE_FRAC)

func _boss_speed() -> float:
	return (CFG.BOSS_BULLET_SPEED_BASE + CFG.BOSS_BULLET_SPEED_PER_TIER * tier) \
		* float(CFG.BOSS_BULLET_SPEED_DIV[clampi(phase, 0, 2)]) \
		* float(diff.get("bossBullet", 1.0))

## 机体主色（Unity _accent）：守门人玫红 / 织星者紫 / 新星核心金，后三台循环。
func _tint() -> Color:
	match index % 3:
		1:
			return Color.html("#a597ff")
		2:
			return Color.html("#ffd27a")
		_:
			return Color.html("#ff6f91")

## 弹体配色（Unity BulletColor）：针弹青 / 水雷金 / 等离子橙 / 重弹暖橙 / 追踪与波动紫。
func _bullet_color(kind: String) -> Color:
	match kind:
		"needle":
			return Color(0.55, 0.98, 0.95)
		"mine":
			return Color(1.0, 0.85, 0.35)
		"plasma":
			return Color(1.0, 0.6, 0.3)
		"heavy":
			return Color(1.0, 0.86, 0.55)
		"homing":
			return Color.html("#9b8cff")
		"wave":
			return Color(0.61, 0.55, 1.0)
		_:
			return _tint()

func _bullet(from: Vector2, angle: float, speed: float, kind: String, r: float,
		life := CFG.BOSS_BULLET_LIFE, extra: Dictionary = {}) -> void:
	if spawn_bullet.is_valid():
		spawn_bullet.call(from, Vector2(cos(angle), sin(angle)) * speed,
			_bullet_color(kind), r, kind, life, extra)

func _fan_at(center: float, n: int, spread: float, speed: float,
		kind := "orb", r := 6.0) -> void:
	for i in range(n):
		_bullet(_muzzle(), center + (i - (n - 1) * 0.5) * spread, speed, kind, r)

func _ring_at(offset: float, n: int, speed: float, kind := "orb", r := 6.0) -> void:
	for i in range(n):
		_bullet(_muzzle(), offset + TAU * float(i) / float(n), speed, kind, r)

## 追踪星群：aim±0.42 展开、速度×0.58、r7、追踪 2.6s、转速 1.9。
func _seekers(n: int) -> void:
	var a := _aim_now()
	var spd := _boss_speed() * CFG.BOSS_SEEKER_SPEED_MUL
	for i in range(n):
		_bullet(_muzzle(), a + (i - (n - 1) * 0.5) * CFG.BOSS_SEEKER_SPREAD, spd,
			"homing", CFG.BOSS_SEEKER_RADIUS, CFG.BOSS_BULLET_LIFE,
			{"homing": true, "homing_time": CFG.BOSS_SEEKER_HOMING,
			"turn_rate": CFG.BOSS_SEEKER_TURN, "homing_delay": 0.0})
	_impact(pos, _tint(), size * 1.8, 0.3)

func _mine_at(ang: float, speed_px: float, r: float, fuse: float, split: int) -> void:
	_bullet(_muzzle(), ang, speed_px, "mine", r, CFG.BOSS_MINE_LIFE,
		{"fuse": fuse, "split": split})

func _beam(ang: float, warn: float, active: float, width_px: float, sweep: float) -> void:
	if spawn_beam.is_valid():
		spawn_beam.call(ang, warn, active, width_px, sweep)
	_sfx("hit")

## 相位闪现：夹在 x∈[size×1.25, W-size×1.25]、y∈[size×1.2, 0.4H]，落地朝玩家放环。
func _warp(x_px: float, y_px: float, ring_n: int) -> void:
	var q := Vector2(
		clampf(x_px, size * 1.25, CFG.VIEW.x - size * 1.25),
		clampf(y_px, size * 1.2, CFG.VIEW.y * 0.4))
	_impact(q, _tint(), size * 2.2, 0.3)
	pos = q
	_sfx("hit")
	_ring_at(_aim_now(), ring_n, _boss_speed() * 0.78)

func _impact(p: Vector2, col: Color, size_px: float, life := 0.3) -> void:
	if fx_impact.is_valid():
		fx_impact.call(p, col, size_px, life)

func _shake(amount_px: float, dur: float) -> void:
	if shake_fn.is_valid():
		shake_fn.call(amount_px, dur)

func _sfx(sname: String) -> void:
	if sfx_fn.is_valid():
		sfx_fn.call(sname)

static func _damp(a: float, b: float, k: float, dt: float) -> float:
	return b + (a - b) * exp(-k * dt)

# ---------------------------------------------------------------- 22 招节拍表
# 逐招对照 Unity BuildBeats：p = phase+1；sp/aim 在发射时刻实时重算。

func _build_beats() -> void:
	var p := phase + 1
	match move_index:
		0:  # 扇形齐射
			var n0 := 9 if p == 3 else (7 if p == 2 else 5)
			_at(0.10, func(): _fan_at(_aim_now(), n0, 0.17, _boss_speed()))
			_at(0.50, func(): _fan_at(_aim_now(), n0, 0.12, _boss_speed()))
			_at(0.90, func(): _fan_at(_aim_now(), n0 + 2, 0.20, _boss_speed()))
			_at(1.18, func(): _ring_at(_aim_now(), 12 if p >= 2 else 8, _boss_speed() * 0.58))
		1:  # 星旋回廊（连续发射器）
			var iv1 := 0.052 if p == 3 else (0.062 if p == 2 else 0.082)
			var arms1 := 5 if p == 3 else (4 if p == 2 else 3)
			_emitter = func(d: float):
				_emit_acc += d
				while _emit_acc >= iv1:
					_emit_acc -= iv1
					var spd := _boss_speed() * 0.72
					for i in range(arms1):
						_bullet(_muzzle(), _emit_angle + i * TAU / arms1, spd, "orb", 6.0)
					_emit_angle += 0.24
		2:  # 环状爆发
			var off2 := randf() * TAU
			_at(0.12, func(): _ring_at(off2, 28 if p >= 2 else 22, _boss_speed() * 0.8))
			_at(0.55, func(): _ring_at(0.22, 30 if p >= 3 else 24, _boss_speed() * 0.58))
			_at(0.86, func(): _fan_at(_aim_now(), 5 if p >= 2 else 3, 0.26, _boss_speed() * 1.12))
		3:  # 追踪星群
			_at(0.15, func(): _seekers(5 if p >= 2 else 3))
			if p >= 2:
				_at(0.70, func(): _seekers(3))
		4:  # 双生扫射（光束）
			_at(0.10, func(): _beam(_aim_now() - 0.55, 0.9, 0.9, 16.0, 0.9))
			_at(1.25, func(): _beam(_aim_now() + 0.55, 0.8, 0.85, 14.0, -0.95))
			_at(2.15, func(): _fan_at(_aim_now(), 5 if p >= 2 else 3, 0.24, _boss_speed()))
		5:  # 十字光牢
			var base5 := randf() * 0.6
			_at(0.15, func():
				for i in range(4):
					_beam(base5 + i * PI * 0.5, 0.95, 0.62, 12.0, 0.0))
			_at(1.05, func(): _ring_at(_aim_now(), 14 if p >= 2 else 10, _boss_speed() * 0.7))
		6:  # 母舰召唤
			_at(0.20, func():
				var n6 := 4 if p == 3 else (3 if p == 2 else 2)
				var roster: Array = ["sniper", "sidewinder", "shardling"] if zone >= 4 \
					else (["shardling", "wasp"] if zone >= 2 else ["wasp"])
				if spawn_child.is_valid():
					for i in range(n6):
						var sx := pos.x + (i - (n6 - 1) * 0.5) * size * 1.5
						spawn_child.call(String(roster[i % roster.size()]),
							Vector2(sx, pos.y + size * 0.8))
				_sfx("pick"))
		7:  # 重弹压制
			_at(0.12, func():
				var a := _aim_now()
				var spd := _boss_speed()
				for i in range(5):
					_bullet(_muzzle(), a + (i - 2) * 0.23, spd * 0.62, "heavy", 10.0)
				if p >= 2:
					_bullet(_muzzle(), a - 0.34, spd * 0.4, "plasma", 13.0, 3.4, {"split": 7})
					_bullet(_muzzle(), a + 0.34, spd * 0.4, "plasma", 13.0, 3.4, {"split": 7}))
			_at(0.70, func():
				var spd := _boss_speed()
				for i in range(12):
					_bullet(_muzzle(), i * TAU / 12.0 + 0.3, spd * 0.72, "shard", 6.0))
			_at(1.20, func(): _fan_at(_aim_now(), 5, 0.20, _boss_speed()))
			_at(1.68, func(): _ring_at(_aim_now(), 18 if p >= 2 else 12, _boss_speed() * 0.9))
		8:  # 双子光矛
			_at(0.12, func():
				var a := _aim_now()
				_beam(a - 0.65, 0.95, 0.9, 14.0, -0.6)
				_beam(a + 0.65, 0.95, 0.9, 14.0, 0.6))
			_at(1.10, func():
				var a := _aim_now()
				var spd := _boss_speed()
				var n := 5 if p >= 2 else 3
				for i in range(n):
					_bullet(_muzzle(), a + (i - (n - 1) * 0.5) * 0.18, spd * 1.05, "needle", 5.0))
			_at(1.75, func(): _ring_at(_emit_angle, 16 if p == 3 else 10, _boss_speed() * 0.66))
		9:  # 雷区播种
			_at(0.10, func():
				var a := _aim_now()
				for i in range(5):
					_mine_at(a + (i - 2) * 0.26, 98.0, 9.0, 1.7, 9)
				_sfx("hit"))
			_at(0.85, func():
				var n := 7 if p >= 2 else 5
				for i in range(n):
					_mine_at(PI * 0.5 + (i - (n - 1) * 0.5) * 0.30, 82.0, 8.0, 2.1, 8)
				_impact(pos, Color.html("#ffc24b"), 150.0, 0.3))
			if p >= 2:
				_at(1.50, func(): _fan_at(_aim_now(), 3, 0.42, _boss_speed() * 1.05))
		10:  # 相位闪现（位移 + 落地环）
			_at(0.15, func(): _warp(CFG.VIEW.x * 0.24, anchor.y - 18.0, 12))
			_at(0.82, func(): _warp(CFG.VIEW.x * 0.74, anchor.y + 26.0, 14))
			_at(1.50, func(): _warp(CFG.VIEW.x * 0.50, anchor.y - 8.0, 18))
		11:  # 星网绞杀
			_at(0.12, func():
				var base11 := _aim_now() - 0.6
				for i in range(4):
					_beam(base11 + i * PI * 0.5, 0.85, 0.7, 11.0, -0.6 if i % 2 == 1 else 0.6))
			_at(1.05, func():
				var a := _aim_now()
				_beam(a - 0.5, 0.7, 0.6, 10.0, 0.0)
				_beam(a + 0.5, 0.7, 0.6, 10.0, 0.0)
				_impact(pos, Color.html("#ff5c8a"), 130.0, 0.28))
			_at(1.85, func(): _ring_at(_emit_angle, 16 if p >= 2 else 10, _boss_speed() * 0.82))
		12:  # 波动弹幕
			_at(0.10, func():
				var a := _aim_now()
				var spd := _boss_speed()
				for i in range(9):
					_bullet(_muzzle(), a + (i - 4) * 0.17, spd * 0.72, "wave", 7.0,
						CFG.BOSS_BULLET_LIFE, {"wave": 2.1}))
			_at(0.95, func():
				var a := _aim_now()
				var spd := _boss_speed()
				for i in range(7):
					_bullet(_muzzle(), a + (i - 3) * 0.20, spd * 0.62, "wave", 6.0,
						CFG.BOSS_BULLET_LIFE, {"wave": -2.4}))
			if p >= 2:
				_at(1.62, func():
					var a := _aim_now()
					var spd := _boss_speed()
					for i in range(5):
						_bullet(_muzzle(), a + (i - 2) * 0.24, spd * 0.9, "wave", 6.0,
							CFG.BOSS_BULLET_LIFE, {"wave": 1.6}))
		13:  # 裂隙光幕（整排针弹留缺口，青环标出口）
			var cols13 := CFG.wall_gap_cols(CFG.VIEW.x)
			var gap13 := CFG.wall_gap_width(phase, tier)
			var step13 := CFG.VIEW.x / cols13
			var plan13 := func():
				var gap_idx := randi() % (cols13 - gap13 + 1)
				_gap_cols.clear()
				for i in range(gap13):
					_gap_cols.append(gap_idx + i)
				var gx := (gap_idx + gap13 * 0.5) * step13
				for i in range(4):
					_impact(Vector2(gx, pos.y + (30.0 * i + 40.0)),
						Color.html("#35e0c8"), 26.0, 0.45)
				_sfx("hit")
			var fire13 := func():
				var spd := _boss_speed() * 0.55
				var fy := pos.y + size * 0.5
				for c in range(cols13):
					if _gap_cols.has(c):
						continue
					var fx := pos.x + clampf((c + 0.5) * step13, 10.0, CFG.VIEW.x - 10.0) - CFG.VIEW.x * 0.5
					_bullet(Vector2(fx, fy), PI * 0.5, spd, "needle", 5.0)
			_at(0.10, plan13)
			_at(0.62, func():
				fire13.call()
				_fan_at(_aim_now(), 3, 0.5, _boss_speed() * 0.9))
			_at(1.40, plan13)
			if p >= 2:
				_at(2.30, plan13)
			_at(2.70, func():
				fire13.call()
				_ring_at(_aim_now(), 14 if p == 3 else 8, _boss_speed() * 0.85))
		14:  # 星脉脉冲（三层不同速环互相超越）
			_at(0.12, func():
				_ring_at(_emit_angle, 18 if p >= 2 else 14, _boss_speed() * 1.12, "shard", 6.0)
				_impact(pos, _tint(), size * 2.2, 0.3))
			_at(0.70, func():
				_ring_at(_emit_angle + 0.16, 24 if p >= 2 else 18, _boss_speed() * 0.60, "orb", 6.0)
				_impact(pos, _tint(), size * 2.8, 0.32))
			_at(1.28, func():
				_ring_at(_emit_angle + 0.30, 30 if p == 3 else 24, _boss_speed() * 0.86, "shard", 6.0)
				_impact(pos, _tint(), CFG.VIEW.x * 0.8, 0.36))
			_at(1.80, func(): _fan_at(_aim_now(), 5 if p >= 2 else 3, 0.30, _boss_speed() * 1.18))
		15:  # 贯穿冲撞（机体四段运动在 _tick_charge_body）
			_at(0.90, func(): _fan_at(_aim_now(), 3, 0.5, _boss_speed() * 0.85))
			_at(1.50, func():
				_ring_at(_emit_angle, 20 if p >= 2 else 14, _boss_speed() * 0.78)
				_fan_at(_aim_now(), 5, 0.24, _boss_speed() * 0.95)
				_shake(11.88, 0.3)
				_impact(pos, Color.html("#ff5c8a"), CFG.VIEW.x, 0.4)
				_sfx("boom"))
		16:  # 光牢旋扫
			_at(0.15, func():
				var a := _aim_now()
				for i in range(4):
					_beam(a + i * PI * 0.5, 1.0, 1.35, 13.0, (-1.0 if i % 2 == 1 else 1.0) * 0.72))
			_at(1.00, func(): _ring_at(_emit_angle, 16 if p >= 2 else 12, _boss_speed() * 0.62))
			_at(1.62, func():
				var a2 := _aim_now() + PI * 0.25
				for i in range(4):
					_beam(a2 + i * PI * 0.5, 0.72, 1.05, 11.0, (1.0 if i % 2 == 1 else -1.0) * 0.85))
			_at(2.40, func(): _fan_at(_aim_now(), 7 if p == 3 else 5, 0.22, _boss_speed() * 1.05))
		17:  # 陨星暴雨（7 列留一条安全道，三层弹速穿插）
			var iv17 := 0.095 if p == 3 else (0.105 if p == 2 else 0.120)
			var skip17 := randi() % 7
			var extra17 := 1 if p == 3 else 0
			_at(0.20, func(): _sfx("hit"))
			_at(1.50, func():
				_ring_at(_aim_now(), 14 if p >= 2 else 10, _boss_speed() * 0.52)
				_fan_at(_aim_now(), 3, 0.42, _boss_speed() * 1.1))
			_emitter = func(d: float):
				_emit_acc += d
				while _emit_acc >= iv17:
					_emit_acc -= iv17
					var sp2 := _boss_speed()
					var step_px := CFG.VIEW.x / 7.0
					for col in range(7):
						if col == skip17 or (extra17 == 1 and col == (skip17 + 1) % 7):
							continue
						var x_px := (col + 0.5) * step_px + randf_range(-9.0, 9.0)
						var ang := PI * 0.5 + randf_range(-0.1, 0.1)
						var spd := sp2 * (0.6 + (col % 3) * 0.17)
						_bullet(Vector2(x_px, -22.0), ang, spd, "shard", 5.0)
		18:  # 猎群连射
			_at(0.15, func(): _seekers(3))
			_at(0.95, func(): _seekers(3))
			_at(1.75, func(): _seekers(4 if p >= 2 else 3))
			if p == 3:
				_at(2.40, func(): _seekers(3))
		19:  # 逆向双旋
			var iv19 := 0.075 if p >= 2 else 0.090
			_emitter = func(d: float):
				_emit_acc += d
				while _emit_acc >= iv19:
					_emit_acc -= iv19
					var spd := _boss_speed()
					for i in range(2):
						_bullet(_muzzle(), _emit_angle + i * PI, spd * 0.66, "orb", 6.0)
						_bullet(_muzzle(), -_emit_angle + i * PI, spd * 0.82, "shard", 6.0)
					_emit_angle += 0.2
			_at(1.25, func(): _fan_at(_aim_now(), 5 if p >= 2 else 3, 0.30, _boss_speed() * 1.05))
		20:  # 环形雷阵
			_at(0.15, func():
				var n := 12 if p >= 2 else 9
				for i in range(n):
					_mine_at(i * TAU / n + _emit_angle, 122.0, 8.0, 1.5, 7)
				_impact(pos, Color.html("#ffc24b"), size * 2.4, 0.34))
			_at(1.05, func():
				var n := 8 if p >= 2 else 6
				for i in range(n):
					_mine_at(i * TAU / n + _emit_angle + 0.4, 70.0, 8.0, 1.1, 6)
				_fan_at(_aim_now(), 3, 0.42, _boss_speed()))
		21:  # 新星爆发
			_at(0.90, func():
				_ring_at(_emit_angle, 22 if p >= 2 else 18, _boss_speed() * 1.15, "shard", 6.0)
				_shake(16.2, 0.42)
				_impact(pos, Color(1.0, 0.86, 0.55), CFG.VIEW.x * 0.9, 0.5)
				_sfx("boom"))
			_at(1.45, func():
				_ring_at(_emit_angle + 0.12, 26 if p == 3 else 22, _boss_speed() * 0.72, "orb", 6.0)
				_impact(pos, Color.html("#ffc24b"), CFG.VIEW.x, 0.45))
			_at(2.05, func():
				_ring_at(_emit_angle + 0.25, 18 if p >= 2 else 12, _boss_speed() * 0.95, "shard", 6.0)
				_fan_at(_aim_now(), 7 if p == 3 else 5, 0.20, _boss_speed() * 1.1))

## 贯穿冲撞的四段机体运动（Unity TickChargeBody）。
func _tick_charge_body(dt: float) -> void:
	var x1 := clampf(_charge_x1, size * 1.1, CFG.VIEW.x - size * 1.1)
	if move_t < 0.9:
		pos.y = _damp(pos.y, _charge_y0, 4.0, dt)
		pos.x = _damp(pos.x, x1, 1.3, dt)
	elif move_t < 1.5:
		var k := 1.0 - pow(1.0 - (move_t - 0.9) / 0.6, 3.0)
		pos.x = lerpf(_charge_x0, x1, k)
		pos.y = lerpf(_charge_y0, _charge_y1, k)
		if not _charge_dived:
			_charge_dived = true
			_impact(pos, _tint(), size * 3.0, 0.4)
	elif move_t < 2.2:
		pos.y = _damp(pos.y, _charge_y1 - 6.0, 5.0, dt)
		pos.x = _damp(pos.x, x1, 2.0, dt)
	else:
		var k2 := clampf((move_t - 2.2) / 0.95, 0.0, 1.0)
		pos.y = lerpf(pos.y, anchor.y, k2)
		pos.x = _damp(pos.x, CFG.VIEW.x * 0.5, 2.2, dt)

# ---------------------------------------------------------------- 伤害结算

## 返回 true 表示这一击造成了破防。入场/崩解期间无敌；mercy 不挡伤害（Unity）。
func take_damage(dmg: float) -> bool:
	if dying or not entered:
		return false
	flash = 0.07
	var real := dmg * (CFG.BOSS_BREAK_DAMAGE_MUL if stun > 0.0 else 1.0)
	hp -= real
	var broke := false
	# 破防窗口内不攒槽，否则持续输出能把 Boss 永久锁住（Unity BreakGaugeAccrues）
	if stun <= 0.0:
		break_gauge = minf(break_max, break_gauge + dmg)
		if break_gauge >= break_max:
			break_gauge = 0.0
			stun = CFG.BOSS_BREAK_STUN
			broke = true
	if hp <= 0.0:
		hp = 0.0
		dying = true
		die_t = 0.0
		casting = false
		telegraph = 0.0
		cast_label = ""
		_pending.clear()
		_emitter = Callable()
		return false
	return broke

func damage_flash() -> void:
	flash = 0.08