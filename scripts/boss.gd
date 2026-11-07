class_name Boss
extends RefCounted

## Boss 状态机（数值与招式表照抄归档 Unity v0.21.14 BossController/BossMoves）：
## 22 个原版具名招式、三台 Boss 各阶段固定序列（可背板）、0.5s 预告、
## 66%/30% 阶段、12% 临界、破防冻结与醒来补招。坐标 y 向下。

const CFG := preload("res://scripts/game_config.gd")

const NAMES := ["阿刻戎", "薇尔", "赫利俄斯"]
const TITLES := ["守门人", "织星者", "新星核心"]
const BASE_HP := [400.0, 380.0, 440.0]
const SIZES := [76.0, 80.0, 82.0]

# 22 招：名称与时长（entities.js:1724-1778）
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
# 三台 Boss × 三阶段固定序列
const SEQUENCES := [
	[[0, 13, 8, 9], [1, 13, 14, 0, 8, 4], [15, 16, 13, 17, 2, 1]],
	[[2, 3, 18, 5, 12], [19, 10, 18, 6, 5], [16, 11, 19, 18, 2, 12]],
	[[1, 7, 11, 9], [21, 6, 8, 1, 7], [21, 16, 17, 11, 20, 7]],
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
var diff: Dictionary = {}
var entered := false
var dying := false
var die_t := 0.0
var stun := 0.0
var break_gauge := 0.0
var break_max := 90.0
var telegraph := 0.0
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
var _volley := 0
var _emit_t := 0.0
var _charge_dir := Vector2.ZERO

# func(pos, vel, color, radius, kind, life)
var spawn_bullet: Callable
# func(kind, pos)
var spawn_child: Callable
var player_pos_fn: Callable


func setup(p_index: int, zone: int, p_tier: int, p_diff: Dictionary) -> void:
	index = clampi(p_index, 0, 2)
	name_zh = NAMES[index]
	title_zh = TITLES[index]
	tier = p_tier
	diff = p_diff
	size = float(SIZES[index])
	max_hp = float(BASE_HP[index]) * CFG.boss_hp_scale(zone) * float(p_diff.get("bossHp", 1.0))
	hp = max_hp
	break_max = maxf(CFG.BOSS_BREAK_FLOOR, max_hp * CFG.BOSS_BREAK_FRAC_OF_MAX_HP)
	anchor = Vector2(CFG.VIEW.x * 0.5, CFG.VIEW.y * 0.27)
	pos = Vector2(CFG.VIEW.x * 0.5, -size)
	timer = CFG.BOSS_INITIAL_CD
	phase = 0
	entered = false
	dying = false
	desperate = false


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


func tick(dt: float, player_pos: Vector2) -> void:
	age += dt
	spin += dt * 0.6
	flash = maxf(0.0, flash - dt)
	if dying:
		die_t += dt
		return

	if not entered:
		pos.y = minf(anchor.y, pos.y + 150.0 * dt)
		if pos.y >= anchor.y - 0.5:
			entered = true
		return

	if _mercy > 0.0:
		_mercy -= dt

	if stun > 0.0:
		stun -= dt
		if stun <= 0.0:
			stun = 0.0
			if casting and move_t >= move_dur:
				casting = false
			if not casting and telegraph <= 0.0:
				cast_label = ""
			timer = CFG.boss_resume_timer(timer)
		return

	# 悬停（贯穿冲撞/相位闪现期间由招式接管位置）
	if not casting or (move_index != 15 and move_index != 10):
		var drift := sin(age * 0.55) * 46.0
		pos.x = lerpf(pos.x, anchor.x + drift, 1.0 - exp(-2.2 * dt))
		pos.y = lerpf(pos.y, anchor.y + sin(age * 0.9) * 7.0, 1.0 - exp(-2.2 * dt))

	var frac := hp_frac()
	var want := 0 if frac > CFG.BOSS_PHASE_HIGH else (1 if frac > CFG.BOSS_PHASE_LOW else 2)
	if want > phase:
		phase = want
		seq_index = 0
		timer = minf(timer, 0.35)
		cast_label = "阶段 %d" % (phase + 1)
		telegraph = CFG.BOSS_TELEGRAPH
	desperate = frac <= CFG.BOSS_DESPERATE_FRAC

	if telegraph > 0.0:
		telegraph -= dt
		if telegraph <= 0.0:
			casting = true
			move_t = 0.0
			_volley = 0
			_emit_t = 0.0
			move_index = _next_move()
			move_dur = float(MOVE_DURATIONS[move_index])
			cast_label = MOVE_LABELS[move_index]
			tell_color = _tell(move_index)
			_cast_begin(player_pos)
		return

	if casting:
		move_t += dt
		_cast_tick(dt, player_pos)
		if move_t >= move_dur:
			casting = false
			cast_label = ""
			chain_count += 1
			timer = _next_timer()
		return

	timer -= dt
	if timer <= 0.0:
		telegraph = CFG.BOSS_TELEGRAPH
		return

	# 待机小弹
	_emit_t -= dt
	if _emit_t <= 0.0:
		_emit_t = CFG.BOSS_IDLE_FIRE_PHASE2 if phase >= 1 else CFG.BOSS_IDLE_FIRE_PHASE1
		_aim_shot(player_pos, _boss_speed() * 0.55, 6.0, _tint())


func _next_move() -> int:
	var seq: Array = SEQUENCES[index][clampi(phase, 0, 2)]
	var m := int(seq[seq_index % seq.size()])
	seq_index += 1
	return m


func _tell(m: int) -> Color:
	if BEAM_MOVES.has(m):
		return Color.html("#ff5c8a")
	if MOVE_MOVES.has(m):
		return Color.html("#9b8cff")
	if ORDNANCE_MOVES.has(m):
		return Color.html("#ffc24b")
	return Color.html("#35e0c8")


func _next_timer() -> float:
	return CFG.boss_spell_cd(phase, tier, chain_count, desperate)


func _boss_speed() -> float:
	return (CFG.BOSS_BULLET_SPEED_BASE + CFG.BOSS_BULLET_SPEED_PER_TIER * tier) / float(CFG.BOSS_BULLET_SPEED_DIV[clampi(phase, 0, 2)])


func _tint() -> Color:
	match index:
		1:
			return Color(0.61, 0.55, 1.0)
		2:
			return Color(1.0, 0.55, 0.35)
		_:
			return Color(1.0, 0.45, 0.6)


func _cast_begin(p: Vector2) -> void:
	# 位移类招式在这里决定去向
	match move_index:
		10:  # 相位闪现：闪到玩家一侧上方
			pos = Vector2(clampf(p.x, 110.0, CFG.VIEW.x - 110.0), CFG.VIEW.y * 0.28)
			_ring(18, _boss_speed() * 0.7, 5.0, _tint(), age)
		15:  # 贯穿冲撞：朝玩家冲
			_charge_dir = (p - pos).normalized()
		2, 21:
			pass


func _cast_tick(dt: float, p: Vector2) -> void:
	var sp := _boss_speed()
	var col := _tint()
	match move_index:
		0:  # 扇形齐射
			if _emit_t <= 0.0:
				_emit_t = 0.3
				var n := 7 if phase >= 1 else 5
				for i in range(n):
					var a := (p - pos).angle() + (i - (n - 1) * 0.5) * deg_to_rad(9.0)
					_shot(pos, a, sp * 0.95, 6.0, col)
		1:  # 星旋回廊
			if _emit_t <= 0.0:
				_emit_t = 0.05
				for k in range(3 if phase >= 1 else 2):
					_shot(pos, spin * 2.2 + _volley * 0.42 + k * TAU / (3.0 if phase >= 1 else 2.0),
						sp * 0.72, 5.0, col)
				_volley += 1
		2:  # 环状爆发
			if _emit_t <= 0.0:
				_emit_t = 0.62
				_ring(14 if phase >= 1 else 10, sp * 0.8, 6.0, col, age * 0.9)
		3:  # 追踪星群
			if _emit_t <= 0.0:
				_emit_t = 0.26
				for i in range(3):
					var a := (p - pos).angle() + (i - 1) * deg_to_rad(6.0)
					_shot(pos, a, sp * 1.05, 7.0, col)
		4:  # 双生扫射
			if _emit_t <= 0.0:
				_emit_t = 0.07
				var sweep := -0.7 + _volley * 0.06
				_shot(pos, PI * 0.5 + sweep, sp * 1.0, 5.0, Color.html("#ff5c8a"))
				_shot(pos, PI * 0.5 - sweep, sp * 1.0, 5.0, Color.html("#ff5c8a"))
				_volley += 1
		5:  # 十字光牢
			if _emit_t <= 0.0 and _volley < 3:
				_emit_t = 0.7
				_volley += 1
				for k in range(4):
					var base := spin + k * TAU / 4.0
					for i in range(5):
						_shot(pos, base, sp * (0.6 + i * 0.12), 6.0, Color.html("#ff5c8a"))
		6:  # 母舰召唤
			if _volley < 1:
				_volley = 1
				if spawn_child.is_valid():
					for i in range(3):
						spawn_child.call("wasp" if i % 2 == 0 else "shardling",
							pos + Vector2((i - 1) * 60.0, 30.0))
		7:  # 重弹压制
			if _emit_t <= 0.0:
				_emit_t = 0.42
				for i in range(2):
					_shot(pos, (p - pos).angle() + (i - 0.5) * 0.12, sp * 0.5, 10.0, Color(1.0, 0.86, 0.55))
		8:  # 双子光矛
			if _emit_t <= 0.0:
				_emit_t = 0.05
				_shot(pos + Vector2(-34, 0), PI * 0.5, sp * 1.3, 5.0, Color.html("#ff5c8a"))
				_shot(pos + Vector2(34, 0), PI * 0.5, sp * 1.3, 5.0, Color.html("#ff5c8a"))
		9:  # 雷区播种
			if _emit_t <= 0.0 and _volley < 8:
				_emit_t = 0.18
				var a := (p - pos).angle() + randf_range(-0.6, 0.6)
				_spawn_mine(pos, Vector2(cos(a), sin(a)) * 110.0)
				_volley += 1
		10:  # 相位闪现（位移已在 _cast_begin 做，这里补弹幕）
			if _emit_t <= 0.0 and _volley < 2:
				_emit_t = 0.5
				_volley += 1
				_ring(12, sp * 0.75, 5.0, Color.html("#9b8cff"), randf() * TAU)
		11:  # 星网绞杀
			if _emit_t <= 0.0:
				_emit_t = 0.06
				for k in range(6):
					_shot(pos, spin * 1.4 + k * TAU / 6.0, sp * 1.1, 5.0, Color.html("#ff5c8a"))
				spin += 0.02
		12:  # 波动弹幕
			if _emit_t <= 0.0:
				_emit_t = 0.22
				for i in range(3):
					var a := (p - pos).angle() + (i - 1) * 0.5
					_spawn_wave(pos, Vector2(cos(a), sin(a)) * sp * 0.8, 7.0, col)
		13:  # 裂隙光幕：整排子弹留一个移动缺口
			if _emit_t <= 0.0 and _volley < 3:
				_emit_t = 0.75
				_volley += 1
				var gap := randi() % 9
				for i in range(9):
					if i == gap or i == gap + 1:
						continue
					var x := 40.0 + i * (CFG.VIEW.x - 80.0) / 8.0
					spawn_bullet.call(Vector2(x, pos.y + 20), Vector2(0, sp * 0.7), col, 6.0, "orb", 9.0)
		14:  # 星脉脉冲
			if _emit_t <= 0.0 and _volley < 4:
				_emit_t = 0.5
				_volley += 1
				_ring(10 + _volley * 2, sp * (0.5 + _volley * 0.1), 5.0, col, 0.0)
		15:  # 贯穿冲撞
			var target := p
			pos += _charge_dir * CFG.BOSS_BULLET_SPEED_BASE * 2.2 * dt
			pos.x = clampf(pos.x, 70.0, CFG.VIEW.x - 70.0)
			pos.y = clampf(pos.y, anchor.y, CFG.VIEW.y * 0.55)
			if _emit_t <= 0.0:
				_emit_t = 0.06
				_shot(pos, _charge_dir.angle() + randf_range(-0.4, 0.4), sp * 0.6, 5.0, Color.html("#9b8cff"))
			_charge_dir = (target - pos).normalized()
		16:  # 光牢旋扫
			if _emit_t <= 0.0:
				_emit_t = 0.06
				for k in range(4):
					_shot(pos, spin * 1.5 + k * TAU / 4.0, sp * 0.95, 5.0, Color.html("#ff5c8a"))
		17:  # 陨星暴雨
			if _emit_t <= 0.0:
				_emit_t = 0.07
				spawn_bullet.call(Vector2(randf_range(30.0, CFG.VIEW.x - 30.0), -20),
					Vector2(0, sp * randf_range(0.8, 1.3)), col, 5.0, "orb", 9.0)
		18:  # 猎群连射
			if _emit_t <= 0.0 and _volley < 5:
				_emit_t = 0.42
				_volley += 1
				for i in range(4):
					var a := (p - pos).angle() + (i - 1.5) * 0.06
					_shot(pos, a, sp * 1.15, 5.0, col)
		19:  # 逆向双旋
			if _emit_t <= 0.0:
				_emit_t = 0.06
				for k in range(2):
					_shot(pos, _volley * 0.33 * (1.0 if k == 0 else -1.0), sp * 0.72, 5.0, col)
				_volley += 1
		20:  # 环形雷阵
			if _volley < 1:
				_volley = 1
				for i in range(10):
					var a := TAU * i / 10.0
					_spawn_mine(pos, Vector2(cos(a), sin(a)) * 120.0)
		21:  # 新星爆发
			if _volley < 1:
				_volley = 1
				flash = 0.2
				_ring(24, sp * 0.85, 5.0, col, 0.0)
				_ring(12, sp * 1.15, 6.0, col, TAU / 24.0)
				_aim_shot(p, sp * 1.0, 8.0, col)


func _ring(n: int, speed: float, radius: float, col: Color, offset: float) -> void:
	for i in range(n):
		var a := offset + TAU * float(i) / float(n)
		_shot(pos, a, speed, radius, col)


func _aim_shot(target: Vector2, speed: float, radius: float, col: Color) -> void:
	_shot(pos, (target - pos).angle(), speed, radius, col)


func _shot(from: Vector2, angle: float, speed: float, radius: float, col: Color) -> void:
	if spawn_bullet.is_valid():
		spawn_bullet.call(from, Vector2(cos(angle), sin(angle)) * speed, col, radius, "orb", 9.0)


func _spawn_mine(from: Vector2, vel: Vector2) -> void:
	if spawn_bullet.is_valid():
		spawn_bullet.call(from, vel, Color(1.0, 0.85, 0.35), 9.0, "mine", 8.0)


func _spawn_wave(from: Vector2, vel: Vector2, radius: float, col: Color) -> void:
	if spawn_bullet.is_valid():
		spawn_bullet.call(from, vel, col, radius, "wave", 9.0)


## 返回 true 表示这一击造成了破防。
func take_damage(dmg: float) -> bool:
	if dying or not entered or _mercy > 0.0:
		return false
	var real := dmg * (CFG.BOSS_BREAK_DAMAGE_MUL if stun > 0.0 else 1.0)
	hp -= real
	flash = 0.06
	if hp <= 0.0:
		hp = 0.0
		dying = true
		die_t = 0.0
		casting = false
		telegraph = 0.0
		cast_label = ""
		return false
	if stun > 0.0:
		return false
	break_gauge += dmg
	if break_gauge >= break_max:
		break_gauge = 0.0
		stun = CFG.BOSS_BREAK_STUN
		timer = CFG.boss_resume_timer(timer)
		telegraph = 0.0
		return true
	return false


func damage_flash() -> void:
	flash = 0.08