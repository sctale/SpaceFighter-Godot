extends Node2D

const CFG := preload("res://scripts/game_config.gd")

const STAR_COUNT := 120
const PLAYER_FIRE_LEVEL := 2
const PLAYER_BULLET_RADIUS := 5.0
const ENEMY_BULLET_RADIUS := 6.0
const GAME_OVER_TAP_DELAY := 0.6

# 美术契约（与归档 Unity 版 ShipArt.cs 一致）：PNG 画布的最大半径 = 0.46 × 边长，
# 所以"视觉外缘 = 判定半径"时，画布边长 = radius / 0.46。
# 玩家机在 Unity 里画布世界高 1.08，换算到 540 设计像素 = 1.08 / (10/540) = 58.32，
# 视觉半径 = 0.46 × 58.32 ≈ 26.83px。敌机精灵已按"机头朝下"渲染，无需旋转。
const ART_EXTENT := 0.46
const PLAYER_ART_RADIUS := 26.83

class Bullet:
	var pos: Vector2
	var prev: Vector2
	var vel: Vector2
	var radius: float
	var damage: float
	var life: float
	var friendly: bool
	var tint: Color
	var grazed := false
	var kind := "orb"        # orb/shard/heavy/plasma/needle/mine/wave/bolt...
	var fuse := -1.0         # 水雷引信
	var split_on_expire := 0 # 水雷爆炸破片数
	var wave := 0.0          # 波动弹横向振幅
	var base_vel := Vector2.ZERO
	var age := 0.0
	var pierce_left := 0     # 棱镜贯穿剩余次数
	var homing := false      # 蜂群追踪
	var homing_time := 0.0
	var homing_delay := 0.0
	var boss_bonus := 1.0
	var hit_enemies: Array = []  # 贯穿弹已 hit 过的敌机，避免一帧多次扣血

	func _init(p_pos: Vector2, p_vel: Vector2, p_radius: float, p_damage: float,
			p_life: float, p_friendly: bool, p_tint: Color, p_kind := "orb") -> void:
		pos = p_pos
		prev = p_pos
		vel = p_vel
		base_vel = p_vel
		radius = p_radius
		damage = p_damage
		life = p_life
		friendly = p_friendly
		tint = p_tint
		kind = p_kind


var player_pos := Vector2(CFG.WIDTH * 0.5, CFG.HEIGHT - 130.0)
var player_lives := 3
var player_invuln := 0.0
var player_bank := 0.0
var player_last_dir := 0.0
var fire_timer := 0.0
var focus := false

# 武器与玩家生存/技能（迁移C）
var weapons := WeaponSystem.new()
var player_shields := 1
var nova := 0.0            # 星爆充能 0..100
var overdrive := 0.0       # 超频剩余时间
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var swap_idle := 0.0
var combo := 0
var combo_timer := 0.0
var multiplier := 1

# 界面状态 / 存档 / 音效
var in_menu := true
var best_score := 0
var sfx: Sfx
var ui_font: Font

# Boss / 补给 / 僚机
var boss: Boss = null
var boss_pending := false
var boss_cleared := false
var crates: Array = []
var crate_timer := 16.0
var drones: Array = []

var score := 0
var graze := 0
var game_over := false
var paused := false
var game_over_time := 0.0
var difficulty := "standard"

var player_bullets: Array = []
var enemy_bullets: Array = []
var enemies: Array = []
var stars: Array = []

var pointer_active := false
var pointer_pos := Vector2.ZERO
var drag_offset := Vector2.ZERO
var spawn_timer := 1.0
var wave_timer := 2.0
var spawn_count := 0
var zone := 1
var zone_kills := 0
var total_kills := 0
var _tex_cache: Dictionary = {}


func _ready() -> void:
	randomize()
	_init_stars()
	weapons.spawn = _player_spawn_bullet
	sfx = Sfx.new()
	add_child(sfx)
	_load_font()
	_load_best()
	# 调试：`godot --path . -- -boss` 直接进 Boss 战（截图/验证用）
	if OS.get_cmdline_user_args().has("-boss") or OS.get_cmdline_args().has("-boss"):
		in_menu = false
		_reset_game()
		_start_boss()


func _load_font() -> void:
	# 随包带 Noto Sans CJK 子集（tools/gen_font_subset.py 生成），
	# 不依赖系统字体回退——Unity 版就是在这里踩过"安卓中文整段空白"的坑。
	var path := "res://assets/fonts/AuroraCJK.ttf"
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font:
			ui_font = f
	if ui_font == null:
		ui_font = ThemeDB.fallback_font


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://save.cfg") == OK:
		best_score = int(cfg.get_value("score", "best", 0))


func _save_best() -> void:
	if score <= best_score:
		return
	best_score = score
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best_score)
	cfg.save("user://save.cfg")


func _player_spawn_bullet(pos: Vector2, vel: Vector2, props: Dictionary) -> void:
	var b := Bullet.new(pos, vel, float(props["radius"]), float(props["damage"]),
		float(props["life"]), true, props["tint"], String(props["kind"]))
	b.pierce_left = int(props.get("pierce", 0))
	b.homing = bool(props.get("homing", false))
	b.homing_time = CFG.SWARM_HOMING
	b.homing_delay = CFG.SWARM_LOCK_DELAY
	b.boss_bonus = float(props.get("boss_bonus", 1.0))
	player_bullets.append(b)


func _nearest_enemy(pos: Vector2) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e: Enemy in enemies:
		var d := pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best


func _init_stars() -> void:
	stars.clear()
	for i in range(STAR_COUNT):
		stars.append({
			"pos": Vector2(randf_range(0.0, CFG.WIDTH), randf_range(0.0, CFG.HEIGHT)),
			"speed": randf_range(18.0, 95.0),
			"size": randf_range(0.6, 2.1),
			"alpha": randf_range(0.18, 0.8),
		})


func _process(delta: float) -> void:
	if in_menu:
		_update_stars(delta * 0.35)
		queue_redraw()
		return
	if paused:
		queue_redraw()
		return
	if game_over:
		game_over_time += delta
		_update_stars(delta)
		queue_redraw()
		return

	focus = Input.is_key_pressed(KEY_SHIFT)
	player_invuln = maxf(0.0, player_invuln - delta)
	_update_skills(delta)
	_update_economy(delta)
	_update_stars(delta)
	_update_player(delta)
	_update_player_fire(delta)
	_update_enemies(delta)
	_update_boss(delta)
	_update_drones(delta)
	_update_crates(delta)
	_update_bullets(delta)
	_update_spawner(delta)
	_resolve_collisions()
	queue_redraw()


func _update_stars(delta: float) -> void:
	for s in stars:
		var p: Vector2 = s["pos"]
		p.y += float(s["speed"]) * delta
		if p.y > CFG.HEIGHT + 4.0:
			p.y = -4.0
			p.x = randf_range(0.0, CFG.WIDTH)
		s["pos"] = p


func _update_player(delta: float) -> void:
	if dash_t > 0.0:
		# 冲刺：短促高速位移，期间无敌（CFG.DASH_INVULN）
		player_pos += dash_dir * CFG.DASH_SPEED * delta
	else:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1.0

		if dir.length_squared() > 0.0:
			dir = dir.normalized()
			var speed := CFG.FOCUS_SPEED if focus else CFG.PLAYER_SPEED
			player_pos += dir * speed * delta
			pointer_active = false
			player_last_dir = dir.x
		elif pointer_active:
			var target := pointer_pos + drag_offset
			var k := 1.0 - exp(-CFG.DRAG_FOLLOW_RATE * delta)
			player_pos = player_pos.lerp(target, k)
			player_last_dir = clampf((target.x - player_pos.x) * 0.02, -1.0, 1.0)

	var min_y := CFG.HEIGHT * CFG.BOUND_TOP_FRAC
	player_pos.x = clampf(player_pos.x, CFG.BOUND_SIDE_INSET, CFG.WIDTH - CFG.BOUND_SIDE_INSET)
	player_pos.y = clampf(player_pos.y, min_y, CFG.HEIGHT - CFG.BOUND_BOTTOM_INSET)
	player_bank = lerpf(player_bank, player_last_dir * 0.22, 1.0 - exp(-12.0 * delta))


func _update_player_fire(delta: float) -> void:
	weapons.precision = focus
	weapons.overdrive = overdrive > 0.0
	weapons.swap_idle = swap_idle
	weapons.tick(delta)
	if weapons.try_fire(player_pos + Vector2(0.0, -26.0)):
		sfx.play_shot()


func _update_skills(delta: float) -> void:
	dash_t = maxf(0.0, dash_t - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	overdrive = maxf(0.0, overdrive - delta)
	swap_idle += delta
	# 星爆自然回充
	nova = minf(100.0, nova + CFG.NOVA_REGEN_PER_SECOND * delta)


func _update_economy(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			multiplier = 1


func _add_combo() -> void:
	combo += 1
	combo_timer = CFG.COMBO_WINDOW
	multiplier = mini(CFG.COMBO_MAX_MULT, 1 + combo / CFG.COMBO_STEP)


func _trigger_dash() -> void:
	if dash_cd > 0.0:
		return
	dash_cd = CFG.DASH_COOLDOWN
	dash_t = CFG.DASH_TIME
	player_invuln = maxf(player_invuln, CFG.DASH_INVULN)
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	dash_dir = dir.normalized() if dir.length_squared() > 0.0 else Vector2(0, -1)


func _trigger_nova() -> void:
	if nova < 100.0:
		return
	nova = 0.0
	overdrive = CFG.OVERDRIVE_TIME
	player_invuln = maxf(player_invuln, CFG.INVULN_AFTER_NOVA)
	sfx.play_nova()
	# 清屏敌弹并造成伤害
	var cleared := enemy_bullets.size()
	score += cleared * CFG.NOVA_SCORE_PER_CLEARED_BULLET
	enemy_bullets.clear()
	for i in range(enemies.size() - 1, -1, -1):
		var e: Enemy = enemies[i]
		e.hp -= CFG.NOVA_ENEMY_DAMAGE
		e.flash = 0.12
		if e.hp <= 0.0:
			_kill_enemy(i, CFG.DIFFICULTY[difficulty])


func _density_tier() -> int:
	return mini(3, maxi(0, zone - 1) / 5)


func _zone_quota() -> int:
	return 12 + zone * 4


func _roster_pool() -> Array:
	var pool := ["drifter", "wasp", "drifter", "lancer"]
	if zone >= 2:
		pool.append_array(["orbiter", "splitter"])
	if zone >= 3:
		pool.append_array(["rock", "sniper"])
	if zone >= 4:
		pool.append_array(["bulwark", "sidewinder"])
	if zone >= 5:
		pool.append_array(["minekeeper", "carrier"])
	return pool


func _update_spawner(delta: float) -> void:
	# 打满本区配额就进 Boss 战；Boss 战期间停刷小怪
	if boss != null:
		return
	if zone_kills >= _zone_quota():
		_start_boss()
		return
	# 波次导演：每波一种队形，队形与机体随星区升级（替掉纯随机单刷）
	wave_timer -= delta
	if wave_timer > 0.0 or enemies.size() >= CFG.MAX_ENEMIES_ALIVE - 8:
		return
	var diff: Dictionary = CFG.DIFFICULTY[difficulty]
	wave_timer = maxf(2.4, 4.4 - zone * 0.18) * float(diff["enemyRate"])
	spawn_count += 1
	_spawn_wave(spawn_count)


## 队形：横排 / V 字 / 双列 / 集群 / 侧翼包抄，每 4 波夹一支精英小队。
func _spawn_wave(n: int) -> void:
	var pool := _roster_pool()
	var kind: String = pool[randi() % pool.size()]
	var elite_wave := n % 4 == 0
	var count := 3 + mini(4, zone / 2)
	var affix := "none"
	if not elite_wave and randf() < CFG.AFFIX_BASE_CHANCE + minf(CFG.AFFIX_MAX_EXTRA, zone * 0.02):
		affix = ["armored", "rapid", "volatile"][randi() % 3]
	match n % 5:
		0:  # 横排
			for i in range(count):
				var x := 90.0 + i * (CFG.WIDTH - 180.0) / maxf(1.0, count - 1.0)
				_spawn_enemy(kind, Vector2(x, -40.0 - absf(i - (count - 1) * 0.5) * 18.0),
					elite_wave and i == count / 2, affix)
		1:  # V 字
			for i in range(count):
				var off := i - (count - 1) * 0.5
				_spawn_enemy(kind, Vector2(CFG.WIDTH * 0.5 + off * 62.0, -40.0 - absf(off) * 34.0),
					elite_wave and absf(off) < 0.6, affix)
		2:  # 双列
			for i in range(count):
				var side := -1.0 if i % 2 == 0 else 1.0
				var row := i / 2
				_spawn_enemy(kind, Vector2(CFG.WIDTH * 0.5 + side * 120.0, -40.0 - row * 52.0),
					elite_wave and i < 2, affix)
		3:  # 集群
			for i in range(count + 1):
				_spawn_enemy(kind, Vector2(randf_range(70.0, CFG.WIDTH - 70.0), -40.0 - i * 26.0),
					elite_wave and i == 0, affix)
		_:  # 侧翼包抄
			for i in range(count):
				var side := -1.0 if i < count * 0.5 else 1.0
				_spawn_enemy(kind, Vector2(CFG.WIDTH * 0.5 + side * (150.0 + i * 16.0), -40.0 - (i % 2) * 30.0),
					elite_wave and i == 0, affix)


func _spawn_enemy(kind: String, pos: Vector2, elite := false, affix := "none",
		hp_frac := 1.0, entry_delay := 0.0) -> void:
	if not CFG.ENEMY_TYPES.has(kind):
		return
	var e := Enemy.new()
	e.setup(kind, CFG.ENEMY_TYPES[kind], pos, zone, _density_tier(), elite, affix, hp_frac)
	e.entry_delay = entry_delay
	e.spawn_bullet = _enemy_spawn_bullet
	e.spawn_child = _spawn_child
	e.player_pos_fn = _player_pos
	enemies.append(e)


func _spawn_child(kind: String, pos: Vector2) -> void:
	if enemies.size() < 38:
		_spawn_enemy(kind, pos, false, "none", 1.0, CFG.CARRIER_CHILD_ENTRY_DELAY)


func _player_pos() -> Vector2:
	return player_pos


func _enemy_spawn_bullet(pos: Vector2, vel: Vector2, color: Color, radius: float,
		kind: String, life: float) -> void:
	if enemy_bullets.size() >= CFG.MAX_ENEMY_BULLETS:
		return
	var b := Bullet.new(pos, vel, radius, 1.0, life, false, color, kind)
	if kind == "mine":
		b.fuse = randf_range(1.8, 2.4)
		b.split_on_expire = 10
	elif kind == "wave":
		b.wave = 2.6
	enemy_bullets.append(b)


func _update_enemies(delta: float) -> void:
	var diff: Dictionary = CFG.DIFFICULTY[difficulty]
	for i in range(enemies.size() - 1, -1, -1):
		var e: Enemy = enemies[i]
		e.tick(delta, diff)
		if e.dead:
			enemies.remove_at(i)


# ---------------------------------------------------------------- Boss

func _start_boss() -> void:
	boss = Boss.new()
	# 原版按 (星区-1)%3 轮换三台 Boss
	boss.setup((zone - 1) % 3, zone, _density_tier(), CFG.DIFFICULTY[difficulty])
	boss.spawn_bullet = _enemy_spawn_bullet
	boss.spawn_child = _spawn_child
	boss.player_pos_fn = _player_pos
	boss_pending = true


func _update_boss(delta: float) -> void:
	if boss == null:
		return
	boss.tick(delta, player_pos)
	if boss.entered:
		boss_pending = false
	if not boss.dying and player_invuln <= 0.0:
		var dx := (player_pos.x - boss.pos.x) / boss.contact_rx()
		var dy := (player_pos.y - boss.pos.y) / boss.contact_ry()
		if dx * dx + dy * dy <= 1.0:
			_player_hit()
	if boss.dying and boss.die_t > 1.2:
		score += int(roundf(3000.0 * float(CFG.DIFFICULTY[difficulty]["scoreMul"]) * multiplier))
		sfx.play_boom()
		boss = null
		boss_cleared = true
		zone = mini(10, zone + 1)
		zone_kills = 0
		player_invuln = maxf(player_invuln, CFG.INVULN_ON_ZONE_CHANGE)
		crate_timer = minf(crate_timer, 4.0)


# ---------------------------------------------------------------- 僚机

func _add_drone() -> void:
	if drones.size() >= CFG.MAX_DRONES:
		return
	var in_use: Array = []
	for d in drones:
		in_use.append(d["kind"])
	drones.append({"kind": CFG.pick_drone_kind(in_use, randi()), "timer": randf_range(0.2, 0.6)})


func _drone_slots() -> Array:
	match drones.size():
		1:
			return CFG.DRONE_SLOTS_1
		2:
			return CFG.DRONE_SLOTS_2
		3:
			return CFG.DRONE_SLOTS_3
	return []


func _update_drones(delta: float) -> void:
	var slots := _drone_slots()
	for i in range(drones.size()):
		var d: Dictionary = drones[i]
		d["timer"] = float(d["timer"]) - delta
		if float(d["timer"]) > 0.0:
			continue
		var slot: Vector2 = slots[i] if i < slots.size() else Vector2.ZERO
		var dpos := player_pos + slot
		match String(d["kind"]):
			"gunner":
				d["timer"] = 0.24
				player_bullets.append(Bullet.new(dpos + Vector2(0, -14), Vector2(0, -900),
					4.0, 1.0, 2.0, true, Color.html("#69f5dc"), "bolt"))
			"lance":
				d["timer"] = 0.7
				var lb := Bullet.new(dpos + Vector2(0, -14), Vector2(0, -820),
					5.0, 2.0, 2.4, true, Color.html("#ff6f91"), "lance")
				lb.pierce_left = 1
				player_bullets.append(lb)
			"swarm":
				d["timer"] = 0.5
				var sb := Bullet.new(dpos + Vector2(0, -10), Vector2(randf_range(-40, 40), -700),
					4.0, 2.0, 2.2, true, Color.html("#ffd27a"), "micro")
				sb.homing = true
				sb.homing_time = 1.2
				sb.homing_delay = 0.1
				player_bullets.append(sb)
			"aegis":
				d["timer"] = CFG.AEGIS_PD_INTERVAL
				for j in range(enemy_bullets.size() - 1, -1, -1):
					var eb: Bullet = enemy_bullets[j]
					if eb.pos.distance_to(dpos) < CFG.AEGIS_PD_RADIUS + eb.radius:
						enemy_bullets.remove_at(j)
						nova = minf(100.0, nova + CFG.NOVA_ON_POINT_DEFENSE)


# ---------------------------------------------------------------- 补给箱

func _update_crates(delta: float) -> void:
	crate_timer -= delta
	if crate_timer <= 0.0 and boss == null:
		crate_timer = randf_range(CFG.SUPPLY_INTERVAL_MIN, CFG.SUPPLY_INTERVAL)
		_spawn_crate()
	for i in range(crates.size() - 1, -1, -1):
		var c: Crate = crates[i]
		c.tick(delta, player_pos)
		if not c.dead and c.pos.distance_to(player_pos) < 28.0:
			_apply_crate(c.kind)
			c.dead = true
		if c.dead:
			crates.remove_at(i)


func _spawn_crate() -> void:
	var kinds := ["weapon", "drone", "life", "shield", "charge", "nova", "gem", "swap", "reflect", "prism"]
	var c := Crate.new()
	c.setup(Vector2(randf_range(60.0, CFG.WIDTH - 60.0), -30.0), kinds[randi() % kinds.size()])
	crates.append(c)


func _apply_crate(kind: String) -> void:
	sfx.play_pick()
	match kind:
		"weapon":
			weapons.grant_level()
		"drone":
			_add_drone()
		"life":
			player_lives = mini(CFG.START_LIVES, player_lives + 1)
		"shield":
			player_shields = mini(CFG.MAX_SHIELDS, player_shields + 1)
		"charge":
			for l in weapons.lines:
				l.charge = 100.0
				l.detuned = false
		"nova":
			nova = 100.0
		"gem":
			score += 500 * multiplier
		"swap":
			for l in weapons.lines:
				if not l.unlocked:
					l.unlocked = true
					break
		"reflect":
			player_invuln = maxf(player_invuln, CFG.REFLECT_DURATION)
		"prism":
			weapons.unlock_line("prism")


func _update_bullets(delta: float) -> void:
	for arr in [player_bullets, enemy_bullets]:
		for i in range(arr.size() - 1, -1, -1):
			var b: Bullet = arr[i]
			b.prev = b.pos
			b.age += delta
			# 水雷：速度按 exp(-3.8dt) 衰减到停住，引信到期炸 10 颗破片
			if b.kind == "mine":
				b.vel *= exp(-CFG.MINE_DRAG * delta)
				if b.fuse > 0.0:
					b.fuse -= delta
					if b.fuse <= 0.0:
						_burst_mine(b)
						arr.remove_at(i)
						continue
			# 蜂群追踪：锁定最近敌机 1.45 秒后转直线
			if b.homing and b.age > b.homing_delay and b.homing_time > 0.0:
				var tgt := _nearest_enemy(b.pos)
				if tgt != null:
					var spd := b.vel.length()
					var want := (tgt.pos - b.pos).normalized() * spd
					b.vel = b.vel.lerp(want, clampf(CFG.SWARM_TURN_RATE * delta, 0.0, 1.0))
					b.vel = b.vel.normalized() * spd
				b.homing_time -= delta
			# 波动弹：沿垂直方向叠一层正弦横摆
			if b.wave > 0.0:
				var perp := b.base_vel.normalized().orthogonal()
				b.pos += b.vel * delta + perp * sin(b.age * CFG.WAVE_PHASE_RATE) * b.wave
			else:
				b.pos += b.vel * delta
			b.life -= delta
			if b.life <= 0.0 or b.pos.y < -40.0 or b.pos.y > CFG.HEIGHT + 40.0 \
					or b.pos.x < -40.0 or b.pos.x > CFG.WIDTH + 40.0:
				arr.remove_at(i)


func _burst_mine(b: Bullet) -> void:
	var n := b.split_on_expire
	for i in range(n):
		var a := TAU * float(i) / n
		var speed := CFG.MINE_BURST_SPEED + zone * 2.0
		enemy_bullets.append(Bullet.new(b.pos, Vector2(cos(a), sin(a)) * speed,
			5.0, 1.0, 4.0, false, b.tint, "shard"))


func _resolve_collisions() -> void:
	var diff: Dictionary = CFG.DIFFICULTY[difficulty]

	for bi in range(player_bullets.size() - 1, -1, -1):
		var b: Bullet = player_bullets[bi]
		var consumed := false
		# Boss 判定：椭圆（size×1.02 / ×0.82），棱镜对巨构 +18%
		if boss != null and boss.entered and not boss.dying:
			var bdx := (b.pos.x - boss.pos.x) / (boss.hit_rx() + b.radius)
			var bdy := (b.pos.y - boss.pos.y) / (boss.hit_ry() + b.radius)
			if bdx * bdx + bdy * bdy <= 1.0:
				var bdmg := b.damage * (CFG.PRISM_BOSS_BONUS if b.kind == "lance" else 1.0)
				if boss.take_damage(bdmg):
					sfx.play_hit()
				boss.damage_flash()
				score += int(roundf(10.0 * float(diff["scoreMul"])))
				if b.pierce_left > 0:
					b.pierce_left -= 1
				else:
					player_bullets.remove_at(bi)
					continue
		for ei in range(enemies.size() - 1, -1, -1):
			var e: Enemy = enemies[ei]
			if b.hit_enemies.has(e):
				continue
			var rr := e.hit_r + b.radius
			if _seg_point_d2(b.prev, b.pos, e.pos) <= rr * rr:
				e.hp -= b.damage * e.damage_taken_mul
				e.flash = 0.08
				b.hit_enemies.append(e)
				if e.hp <= 0.0:
					_kill_enemy(ei, diff)
				if b.pierce_left > 0:
					b.pierce_left -= 1
				else:
					consumed = true
					break
		if consumed:
			player_bullets.remove_at(bi)


func _kill_enemy(index: int, diff: Dictionary) -> void:
	var e: Enemy = enemies[index]
	score += int(roundf(e.score_value * float(diff["scoreMul"]) * multiplier))
	nova = minf(100.0, nova + (CFG.NOVA_ON_ELITE_KILL if e.elite else CFG.NOVA_ON_KILL))
	_add_combo()
	total_kills += 1
	zone_kills += 1
	var at := e.pos
	var was_volatile := e.affix == "volatile"
	var was_splitter := e.kind == "splitter"
	enemies.remove_at(index)
	# 分裂体留下半血幼体；挥发机炸出一圈幼体
	if was_splitter:
		for s in [-1.0, 1.0]:
			_spawn_enemy("shardling", at + Vector2(s * 14.0, 0.0), false, "none", CFG.SPLITTER_CHILD_HP_FRAC)
	elif was_volatile:
		for i in range(CFG.VOLATILE_SPLIT):
			var a := TAU * float(i) / CFG.VOLATILE_SPLIT
			_spawn_enemy("shardling", at + Vector2(cos(a), sin(a)) * 18.0)
	if e.elite:
		sfx.play_boom()

	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b: Bullet = enemy_bullets[i]
		var d2 := _seg_point_d2(b.prev, b.pos, player_pos)
		var hit_r := CFG.PLAYER_HIT_R + b.radius
		var graze_r := CFG.PLAYER_GRAZE_R + b.radius
		if d2 <= graze_r * graze_r and not b.grazed:
			b.grazed = true
			graze += 1
			nova = minf(100.0, nova + CFG.NOVA_ON_GRAZE)
		if player_invuln <= 0.0 and d2 <= hit_r * hit_r:
			enemy_bullets.remove_at(i)
			_player_hit()
			break

	if player_invuln <= 0.0:
		for en in enemies:
			var rr: float = CFG.PLAYER_HIT_R + en.hit_r
			if player_pos.distance_squared_to(en.pos) <= rr * rr:
				_player_hit()
				break


func _player_hit() -> void:
	sfx.play_hit()
	# 护盾优先，掉了只丢一层；护盾耗尽才吃船体
	if player_shields > 0:
		player_shields -= 1
		player_invuln = CFG.INVULN_AFTER_SHIELD
		nova = minf(100.0, nova + CFG.NOVA_ON_SHIELD_BREAK)
	else:
		player_lives -= 1
		player_invuln = CFG.INVULN_AFTER_HULL_HIT
		nova = minf(100.0, nova + CFG.NOVA_ON_HULL_HIT)
		combo = 0
		multiplier = 1
		combo_timer = 0.0
	enemy_bullets.clear()
	weapons.active().charge = maxf(0.0, weapons.active().charge - CFG.HIT_CHARGE_PENALTY)
	if player_lives <= 0:
		game_over = true
		game_over_time = 0.0
		_save_best()
		sfx.play_boom()


func _seg_point_d2(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var q := a + ab * t
	return p.distance_squared_to(q)


func _unhandled_input(event: InputEvent) -> void:
	if in_menu:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_start_run()
		elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			_menu_press(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_reset_game()
			KEY_ESCAPE, KEY_P:
				paused = not paused
			KEY_1:
				difficulty = "cruise"
			KEY_2:
				difficulty = "standard"
			KEY_3:
				difficulty = "abyss"
			KEY_SPACE:
				_trigger_dash()
			KEY_X:
				_trigger_nova()
			KEY_TAB, KEY_E:
				if weapons.cycle_weapon():
					swap_idle = 0.0
			KEY_F11:
				var w: int = DisplayServer.window_get_mode()
				DisplayServer.window_set_mode(
					DisplayServer.WINDOW_MODE_WINDOWED if w == DisplayServer.WINDOW_MODE_FULLSCREEN
					else DisplayServer.WINDOW_MODE_FULLSCREEN)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if game_over and game_over_time > GAME_OVER_TAP_DELAY:
			_reset_game()
			return
		if event.pressed and _press_control(event.position):
			return
		pointer_active = event.pressed
		if event.pressed:
			pointer_pos = event.position
			_start_drag()
	elif event is InputEventMouseMotion and pointer_active:
		pointer_pos = event.position
	elif event is InputEventScreenTouch:
		if game_over and event.pressed and game_over_time > GAME_OVER_TAP_DELAY:
			_reset_game()
			return
		if event.pressed and _press_control(event.position):
			return
		pointer_active = event.pressed
		if event.pressed:
			pointer_pos = event.position
			_start_drag()
	elif event is InputEventScreenDrag:
		pointer_pos = event.position


## 触屏控件热区（540x960）：x,y,w,h。绘制与判定共用这一份。
func _controls() -> Dictionary:
	return {
		"pause": Vector4(CFG.WIDTH - 62.0, 12.0, 44.0, 44.0),
		"nova": Vector4(CFG.WIDTH - 100.0, CFG.HEIGHT - 112.0, 72.0, 72.0),
		"dash": Vector4(CFG.WIDTH - 182.0, CFG.HEIGHT - 96.0, 58.0, 58.0),
		"weapon": Vector4(CFG.WIDTH - 168.0, CFG.HEIGHT - 190.0, 58.0, 58.0),
	}


func _press_control(p: Vector2) -> bool:
	var ctrls := _controls()
	for k in ctrls:
		var r: Vector4 = ctrls[k]
		if Rect2(r.x, r.y, r.z, r.w).has_point(p):
			match String(k):
				"pause":
					paused = not paused
				"dash":
					_trigger_dash()
				"nova":
					_trigger_nova()
				"weapon":
					if weapons.cycle_weapon():
						swap_idle = 0.0
			return true
	return false


func _start_drag() -> void:
	drag_offset.x = clampf(player_pos.x - pointer_pos.x, -CFG.WIDTH * 0.3, CFG.WIDTH * 0.3)
	drag_offset.y = clampf(player_pos.y - pointer_pos.y, -140.0, 60.0)


func _start_run() -> void:
	in_menu = false
	_reset_game()


func _menu_press(p: Vector2) -> void:
	var keys := ["cruise", "standard", "abyss"]
	for i in range(3):
		var r := Rect2(CFG.WIDTH * 0.5 - 168.0 + i * 114.0, 400.0, 104.0, 40.0)
		if r.has_point(p):
			difficulty = keys[i]
			return
	if Rect2(CFG.WIDTH * 0.5 - 140.0, 500.0, 280.0, 64.0).has_point(p):
		_start_run()


func _reset_game() -> void:
	player_pos = Vector2(CFG.WIDTH * 0.5, CFG.HEIGHT - CFG.RESPAWN_INSET)
	player_lives = CFG.START_LIVES
	player_invuln = CFG.INVULN_ON_SPAWN
	player_bank = 0.0
	fire_timer = 0.0
	score = 0
	graze = 0
	game_over = false
	paused = false
	game_over_time = 0.0
	player_bullets.clear()
	enemy_bullets.clear()
	enemies.clear()
	spawn_timer = 1.0
	wave_timer = 2.0
	spawn_count = 0
	zone = 1
	zone_kills = 0
	total_kills = 0
	pointer_active = false
	weapons = WeaponSystem.new()
	weapons.spawn = _player_spawn_bullet
	player_shields = CFG.START_SHIELDS
	nova = 0.0
	overdrive = 0.0
	dash_t = 0.0
	dash_cd = 0.0
	swap_idle = 0.0
	combo = 0
	combo_timer = 0.0
	multiplier = 1
	boss = null
	boss_pending = false
	boss_cleared = false
	crates.clear()
	crate_timer = 16.0
	drones.clear()


func _ship_tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := "res://assets/ships/%s.png" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[name] = tex
	return tex


## 按"视觉外缘 = radius"画一张机体精灵；缺图时返回 false，调用方回退到几何块。
func _draw_ship(name: String, center: Vector2, radius: float, angle: float, modulate: Color) -> bool:
	var tex := _ship_tex(name)
	if tex == null:
		return false
	var side := radius / ART_EXTENT
	draw_set_transform(center, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-side * 0.5, -side * 0.5, side, side), false, modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _draw() -> void:
	_draw_sky()
	_draw_stars()
	if in_menu:
		_draw_menu()
		return
	_draw_crates()
	_draw_bullets()
	_draw_enemies()
	if boss != null:
		_draw_boss()
	if not game_over:
		_draw_player()
		_draw_drones()
	_draw_hud()
	_draw_controls()
	if paused:
		_draw_overlay("已暂停", "点右上角继续，或按 P")
	if game_over:
		_draw_game_over()


## 每个星区一套天空渐变 + 两层星云（对标 web 的 10 套 zone sky）。
const ZONE_SKIES := [
	["#050817", "#0b1430"], ["#0a0618", "#1a0f33"], ["#04140f", "#0b2a25"],
	["#140a06", "#2a170c"], ["#0a0a1a", "#1c2340"], ["#100616", "#2a1030"],
	["#041018", "#0a2436"], ["#140610", "#2c0d1f"], ["#06120a", "#12301c"],
	["#0c0414", "#241040"],
]


func _draw_sky() -> void:
	var pair: Array = ZONE_SKIES[clampi(zone - 1, 0, 9)]
	var top := Color.html(String(pair[0]))
	var bot := Color.html(String(pair[1]))
	var bands := 24
	for i in range(bands):
		var k := float(i) / float(bands - 1)
		var y := CFG.HEIGHT * float(i) / float(bands)
		draw_rect(Rect2(0, y, CFG.WIDTH, CFG.HEIGHT / bands + 1.0), top.lerp(bot, k))
	# 星云
	var t := Time.get_ticks_msec() * 0.00002
	# 星云：用同心圆近似软边（单个 draw_circle 会有硬边圆盘）
	_blob(Vector2(CFG.WIDTH * 0.25 + sin(t * 3.0) * 30.0, CFG.HEIGHT * 0.3), 250.0,
		Color(bot.r, bot.g, bot.b, 0.30))
	_blob(Vector2(CFG.WIDTH * 0.78, CFG.HEIGHT * 0.62 + cos(t * 2.0) * 26.0), 210.0,
		Color(top.r, top.g, top.b, 0.32))


func _blob(center: Vector2, radius: float, col: Color, layers := 7) -> void:
	for i in range(layers, 0, -1):
		var k := float(i) / float(layers)
		draw_circle(center, radius * k, Color(col.r, col.g, col.b, col.a / float(layers)))


func _draw_menu() -> void:
	var font := ui_font
	draw_rect(Rect2(0, 0, CFG.WIDTH, CFG.HEIGHT), Color(0.01, 0.02, 0.05, 0.62))
	draw_string(font, Vector2(0, 250), "裂隙巡航", HORIZONTAL_ALIGNMENT_CENTER, CFG.WIDTH, 56,
		Color.html("#f3f8ff"))
	draw_string(font, Vector2(0, 292), "A U R O R A   R I F T", HORIZONTAL_ALIGNMENT_CENTER,
		CFG.WIDTH, 14, Color.html("#69f5dc"))
	draw_string(font, Vector2(0, 350), "最高分  %d" % best_score, HORIZONTAL_ALIGNMENT_CENTER,
		CFG.WIDTH, 18, Color.html("#ffd27a"))
	# 难度胶囊
	var names := ["巡航", "标准", "深渊"]
	var keys := ["cruise", "standard", "abyss"]
	for i in range(3):
		var r := Rect2(CFG.WIDTH * 0.5 - 168.0 + i * 114.0, 400.0, 104.0, 40.0)
		var on: bool = keys[i] == difficulty
		draw_rect(r, Color(0.41, 0.96, 0.86, 0.16) if on else Color(0.03, 0.05, 0.12, 0.6))
		draw_rect(r, Color(0.41, 0.96, 0.86, 0.5) if on else Color(0.63, 0.71, 1.0, 0.16), false, 1.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 27), names[i],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 17, Color.html("#f3f8ff") if on else Color.html("#8d9bbd"))
	# 开始按钮
	var btn := Rect2(CFG.WIDTH * 0.5 - 140.0, 500.0, 280.0, 64.0)
	draw_rect(btn, Color(0.41, 0.96, 0.86, 0.9))
	draw_string(font, Vector2(btn.position.x, btn.position.y + 40), "开始巡航",
		HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, 24, Color(0.02, 0.08, 0.12))
	draw_string(font, Vector2(0, 640), "拖动 / WASD 移动   ·   Shift 精准   ·   Tab 换线",
		HORIZONTAL_ALIGNMENT_CENTER, CFG.WIDTH, 13, Color.html("#8d9bbd"))
	draw_string(font, Vector2(0, 664), "空格 冲刺   ·   X 星爆   ·   P 暂停", HORIZONTAL_ALIGNMENT_CENTER,
		CFG.WIDTH, 13, Color.html("#8d9bbd"))
	var ver := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var vi := Engine.get_version_info()
	draw_string(font, Vector2(0, CFG.HEIGHT - 42), "v%s  ·  Godot %d.%d 移植版" % [ver, vi["major"], vi["minor"]],
		HORIZONTAL_ALIGNMENT_CENTER,
		CFG.WIDTH, 12, Color.html("#5e6b8c"))


func _draw_boss() -> void:
	var font := ui_font
	var art: String = ["boss_gatekeeper", "boss_weaver", "boss_helios"][boss.index]
	var ring: String = ["boss_gatekeeper_ring", "boss_weaver_ring", "boss_helios_ring"][boss.index]
	_draw_ship(art, boss.pos, boss.size, 0.0, Color.WHITE)
	# 环层反向旋转
	_draw_ship(ring, boss.pos, boss.size * 1.08, -boss.spin * 0.8,
		Color(1, 1, 1, 0.55 if boss.phase >= 1 else 0.35))
	if boss.flash > 0.0:
		_draw_ship(art + "_mask", boss.pos, boss.size, 0.0,
			Color(1, 1, 1, clampf(boss.flash / 0.08, 0.0, 1.0) * 0.8))
	# 血条 + 名称 + 预告
	var w := CFG.WIDTH - 96.0
	var x := 48.0
	draw_rect(Rect2(x, 104, w, 10), Color(0.1, 0.05, 0.1, 0.85))
	draw_rect(Rect2(x, 104, w * boss.hp_frac(), 10), Color.html("#ff6f91"))
	draw_rect(Rect2(x, 104, w, 10), Color(1, 0.4, 0.55, 0.35), false, 1.0)
	draw_string(font, Vector2(x, 98), "%s · %s  P%d" % [boss.title_zh, boss.name_zh, boss.phase + 1],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.html("#ffd1dc"))
	if boss.stun > 0.0:
		draw_string(font, Vector2(x, 132), "破防！伤害 +35%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color.html("#ffd27a"))
	elif boss.cast_label != "":
		draw_string(font, Vector2(x, 120), ("预告 · " if boss.telegraph > 0.0 else "") + boss.cast_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.html("#ff9ab4"))
	if boss.desperate:
		draw_string(font, Vector2(CFG.WIDTH - 120, 132), "临界", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color.html("#ffd27a"))


func _draw_crates() -> void:
	for c in crates:
		var tex := _ship_tex("crate_" + (c.kind if c.kind != "nova" else "gem"))
		if tex != null:
			var side := 34.0 + sin(c.spin) * 2.0
			draw_set_transform(c.pos, c.spin * 0.15, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-side * 0.5, -side * 0.5, side, side), false, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(Rect2(c.pos - Vector2(12, 12), Vector2(24, 24)), Color(0.41, 0.96, 0.86, 0.8))


func _draw_drones() -> void:
	var slots := _drone_slots()
	var art := {"gunner": "drone_cannon", "lance": "drone_seeker", "aegis": "drone_support", "swarm": "drone_swarm"}
	for i in range(drones.size()):
		var slot: Vector2 = slots[i] if i < slots.size() else Vector2.ZERO
		_draw_ship(String(art[drones[i]["kind"]]), player_pos + slot, 13.0, 0.0, Color(1, 1, 1, 0.95))


## 触屏动作环：星爆 / 冲刺 / 换线 + 右上暂停。热区见 _controls()。
func _draw_controls() -> void:
	var font := ui_font
	var ctrls := _controls()
	# 暂停
	var pr: Vector4 = ctrls["pause"]
	var pc := Vector2(pr.x + pr.z * 0.5, pr.y + pr.w * 0.5)
	draw_circle(pc, 18.0, Color(0.039, 0.067, 0.14, 0.75))
	draw_line(pc + Vector2(-7, -8), pc + Vector2(-7, 8), Color(0.55, 0.6, 0.73), 3.0)
	draw_line(pc + Vector2(3, -8), pc + Vector2(3, 8), Color(0.55, 0.6, 0.73), 3.0)
	# 星爆
	var nr: Vector4 = ctrls["nova"]
	var nc := Vector2(nr.x + nr.z * 0.5, nr.y + nr.w * 0.5)
	var ready := nova >= 100.0
	draw_circle(nc, 32.0, Color(1.0, 0.82, 0.35, 0.16) if ready else Color(0.039, 0.067, 0.14, 0.8))
	draw_arc(nc, 30.0, 0, TAU, 40, Color(1.0, 0.82, 0.35, 0.9) if ready else Color(0.4, 0.43, 0.55, 0.6), 3.0, true)
	draw_arc(nc, 30.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(nova / 100.0, 0.0, 1.0), 40,
		Color(1.0, 0.82, 0.35, 0.95), 3.0, true)
	draw_string(font, nc + Vector2(-16, 5), "星爆", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1.0, 0.82, 0.35) if ready else Color(0.6, 0.63, 0.75))
	# 冲刺
	var dr: Vector4 = ctrls["dash"]
	var dc := Vector2(dr.x + dr.z * 0.5, dr.y + dr.w * 0.5)
	draw_circle(dc, 26.0, Color(0.039, 0.067, 0.14, 0.8))
	draw_arc(dc, 24.0, 0, TAU, 32, Color(0.41, 0.96, 0.86, 0.85), 2.5, true)
	if dash_cd > 0.0:
		draw_arc(dc, 24.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - dash_cd / CFG.DASH_COOLDOWN), 32,
			Color(0.41, 0.96, 0.86, 0.25), 2.5, true)
	draw_string(font, dc + Vector2(-13, 5), "冲刺", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.41, 0.96, 0.86))
	# 换线
	var wr: Vector4 = ctrls["weapon"]
	var wc := Vector2(wr.x + wr.z * 0.5, wr.y + wr.w * 0.5)
	var wtint := Color.html(String(CFG.WEAPON_LINES[weapons.active_id]["tint"]))
	draw_circle(wc, 26.0, Color(0.039, 0.067, 0.14, 0.8))
	draw_arc(wc, 24.0, 0, TAU, 32, Color(wtint.r, wtint.g, wtint.b, 0.85), 2.5, true)
	draw_string(font, wc + Vector2(-13, -2), "换线", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, wtint)
	draw_string(font, wc + Vector2(-13, 12), "L%d" % weapons.active().level,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.6, 0.73))


func _draw_stars() -> void:
	for s in stars:
		var c := Color(0.85, 0.93, 1.0, float(s["alpha"]))
		draw_circle(s["pos"], float(s["size"]), c)


func _draw_bullets() -> void:
	for b in player_bullets:
		# 拖尾只画 8px：高速弹每帧跨 20px，画满 prev→pos 会连成一条激光
		var tail: Vector2 = b.pos - b.vel.normalized() * minf(8.0, b.pos.distance_to(b.prev))
		draw_line(tail, b.pos, Color(b.tint.r, b.tint.g, b.tint.b, 0.5), 2.0, true)
		draw_circle(b.pos, b.radius, b.tint)
	for b in enemy_bullets:
		draw_circle(b.pos, b.radius + 2.0, Color(b.tint.r, b.tint.g, b.tint.b, 0.16))
		draw_circle(b.pos, b.radius, b.tint)
		draw_circle(b.pos, b.radius * 0.45, Color(1, 1, 1, 0.72))


func _draw_player() -> void:
	var blink := player_invuln > 0.0 and int(player_invuln * 18.0) % 2 == 0
	var alpha := 0.35 if blink else 1.0
	var tint := Color.html(CFG.WEAPON_LINES["pulse"]["tint"])

	_blob(player_pos, 36.0, Color(tint.r, tint.g, tint.b, 0.16 * alpha))
	if not _draw_ship("player_pulse", player_pos, PLAYER_ART_RADIUS, player_bank, Color(1, 1, 1, alpha)):
		_draw_player_fallback(alpha)

	if focus:
		draw_circle(player_pos, CFG.PLAYER_HIT_R, Color(1, 1, 1, 0.95))
		draw_arc(player_pos, CFG.PLAYER_GRAZE_R, 0, TAU, 40, Color(0.4, 0.95, 0.86, 0.45), 1.0, true)


## 缺精灵时的几何块回退（保证构建缺图也能跑）。
func _draw_player_fallback(alpha: float) -> void:
	var tint := Color.html(CFG.WEAPON_LINES["pulse"]["tint"])
	var deep := Color.html(CFG.WEAPON_LINES["pulse"]["deep"])
	var white := Color(0.95, 0.97, 1.0, alpha)
	tint.a = alpha
	deep.a = alpha
	draw_set_transform(player_pos, player_bank, Vector2.ONE)
	var hull := PackedVector2Array([
		Vector2(0, -28), Vector2(8, -8), Vector2(25, 12), Vector2(12, 17),
		Vector2(5, 11), Vector2(-5, 11), Vector2(-12, 17), Vector2(-25, 12),
		Vector2(-8, -8),
	])
	draw_colored_polygon(hull, deep)
	draw_polyline(_closed(hull), white, 1.5, true)
	var canopy := PackedVector2Array([
		Vector2(0, -20), Vector2(5, -5), Vector2(0, 2), Vector2(-5, -5),
	])
	draw_colored_polygon(canopy, Color(0.45, 0.95, 0.92, alpha))
	var flame := PackedVector2Array([
		Vector2(-5, 12), Vector2(0, 24 + sin(Time.get_ticks_msec() * 0.04) * 4.0),
		Vector2(5, 12),
	])
	draw_colored_polygon(flame, Color(1.0, 0.82, 0.45, 0.85 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_enemies() -> void:
	for e: Enemy in enemies:
		var base := Color.html(String(e.def.get("color", "#ff6f91")))
		var accent := Color.html(String(e.def.get("accent", "#ffffff")))
		var ang := e.turn + e.spin
		if e.elite:
			draw_arc(e.pos, e.size * 1.35, 0, TAU, 32, Color(1.0, 0.82, 0.35, 0.5), 1.5, true)
		if not _draw_ship("enemy_" + e.kind, e.pos, e.size, ang, Color.WHITE):
			draw_circle(e.pos, e.size * 1.45, Color(base.r, base.g, base.b, 0.12))
			var pts := _enemy_shape(e)
			draw_colored_polygon(pts, Color(base.r, base.g, base.b, 0.92))
			draw_polyline(_closed(pts), accent, 1.2, true)
		elif e.flash > 0.0:
			# 命中闪白：同尺寸白剪影叠一层（归档里的 *_mask.png）
			_draw_ship("enemy_" + e.kind + "_mask", e.pos, e.size, ang,
				Color(1, 1, 1, clampf(e.flash / 0.08, 0.0, 1.0) * 0.85))
		if e.max_hp > 20.0:
			var w: float = e.size * 2.0
			var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
			draw_rect(Rect2(e.pos.x - w * 0.5, e.pos.y - e.size - 8.0, w, 2.5),
				Color(0.1, 0.1, 0.15, 0.8))
			draw_rect(Rect2(e.pos.x - w * 0.5, e.pos.y - e.size - 8.0, w * ratio, 2.5),
				accent)


func _enemy_shape(e: Enemy) -> PackedVector2Array:
	var r := e.size
	match e.kind:
		"wasp", "shardling":
			return PackedVector2Array([
				e.pos + Vector2(0, r), e.pos + Vector2(r, -r * 0.8),
				e.pos + Vector2(-r, -r * 0.8),
			])
		"lancer", "orbiter", "bulwark", "carrier", "sniper", "minekeeper":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := TAU * float(i) / 6.0 + PI / 6.0
				pts.append(e.pos + Vector2(cos(a), sin(a)) * r)
			return pts
		"rock":
			var pts := PackedVector2Array()
			for i in range(7):
				var a := TAU * float(i) / 7.0
				pts.append(e.pos + Vector2(cos(a), sin(a)) * r * (0.8 + 0.2 * float(i % 2)))
			return pts
		_:
			return PackedVector2Array([
				e.pos + Vector2(0, -r), e.pos + Vector2(r, 0),
				e.pos + Vector2(0, r), e.pos + Vector2(-r, 0),
			])


func _draw_hud() -> void:
	var font := ui_font
	draw_rect(Rect2(0, 0, CFG.WIDTH, 88), Color(0.02, 0.04, 0.08, 0.72))
	draw_string(font, Vector2(16, 30), "%d" % score,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.html("#f3f8ff"))
	draw_string(font, Vector2(16, 52), "GRAZE %d" % graze,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.html("#69f5dc"))
	draw_string(font, Vector2(16, 72), "ZONE %02d" % zone,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.html("#8d9bbd"))
	if multiplier > 1:
		draw_string(font, Vector2(120, 30), "x%d" % multiplier,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.html("#ffd27a"))
	# 右上：生命 + 护盾（右缘留 60 给暂停键）
	draw_string(font, Vector2(CFG.WIDTH - 260, 30), "HULL %d" % player_lives,
		HORIZONTAL_ALIGNMENT_RIGHT, 184, 16, Color.html("#ffd27a"))
	var sx := float(CFG.WIDTH) - 88.0
	for i in range(CFG.MAX_SHIELDS):
		var on := i < player_shields
		draw_circle(Vector2(sx - i * 16.0, 48.0), 5.0 if on else 3.5,
			Color(0.41, 0.96, 0.86, 0.95) if on else Color(0.25, 0.3, 0.4, 0.8))
	draw_string(font, Vector2(CFG.WIDTH - 260, 72), CFG.DIFFICULTY[difficulty]["name"],
		HORIZONTAL_ALIGNMENT_RIGHT, 184, 12, Color.html("#8fa4c9"))
	# 底部：当前武器 + 蓄能条 + 星爆条
	var w := weapons.active()
	var wdef: Dictionary = CFG.WEAPON_LINES[w.id]
	var wname := CFG.weapon_name(w.id, w.level)
	var tint := Color.html(String(wdef["tint"]))
	draw_string(font, Vector2(16, CFG.HEIGHT - 52), "%s LV%d" % [wname, w.level],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
	draw_rect(Rect2(16, CFG.HEIGHT - 44, 150, 5), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(16, CFG.HEIGHT - 44, 150.0 * clampf(w.charge / 100.0, 0.0, 1.0), 5),
		tint if not w.detuned else Color(1.0, 0.45, 0.35))
	if w.detuned:
		draw_string(font, Vector2(172, CFG.HEIGHT - 39), "失谐排气", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(1.0, 0.45, 0.35))
	if weapons.resonance > 0.0:
		draw_string(font, Vector2(16, CFG.HEIGHT - 26), "共鸣 x%d" % int(weapons.resonance),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.html("#9b8cff"))


func _draw_overlay(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, CFG.WIDTH, CFG.HEIGHT), Color(0, 0, 0, 0.55))
	var font := ui_font
	draw_string(font, Vector2(0, CFG.HEIGHT * 0.45), title,
		HORIZONTAL_ALIGNMENT_CENTER, CFG.WIDTH, 34, Color.WHITE)
	draw_string(font, Vector2(0, CFG.HEIGHT * 0.53), subtitle,
		HORIZONTAL_ALIGNMENT_CENTER, CFG.WIDTH, 16, Color.html("#8fa4c9"))


func _grade() -> String:
	if score >= CFG.GRADE_S:
		return "S"
	if score >= CFG.GRADE_A:
		return "A"
	if score >= CFG.GRADE_B:
		return "B"
	return "C"


func _draw_game_over() -> void:
	var font := ui_font
	draw_rect(Rect2(0, 0, CFG.WIDTH, CFG.HEIGHT), Color(0.01, 0.02, 0.05, 0.78))
	var card := Rect2(40, CFG.HEIGHT * 0.28, CFG.WIDTH - 80, 420)
	draw_rect(card, Color(0.035, 0.055, 0.117, 0.96))
	draw_rect(card, Color(0.63, 0.71, 1.0, 0.25), false, 1.0)
	draw_string(font, Vector2(card.position.x, card.position.y + 34), "巡航终止",
		HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 28, Color.html("#ff6f91"))
	draw_string(font, Vector2(card.position.x, card.position.y + 62), "信号消失在裂隙深处。",
		HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 12, Color.html("#8d9bbd"))
	draw_string(font, Vector2(card.position.x + 28, card.position.y + 104), "SCORE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.html("#5e6b8c"))
	draw_string(font, Vector2(card.position.x + 28, card.position.y + 146), "%d" % score,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.html("#f3f8ff"))
	# 评级圆章
	var gc := Vector2(card.position.x + card.size.x - 78, card.position.y + 124)
	draw_circle(gc, 34.0, Color(0.41, 0.96, 0.86, 0.10))
	draw_arc(gc, 34.0, 0, TAU, 40, Color(0.41, 0.96, 0.86, 0.6), 2.0, true)
	draw_string(font, Vector2(gc.x - 34, gc.y + 13), _grade(), HORIZONTAL_ALIGNMENT_CENTER, 68, 32,
		Color.html("#69f5dc"))
	draw_string(font, Vector2(gc.x - 34, gc.y + 30), "RANK", HORIZONTAL_ALIGNMENT_CENTER, 68, 9,
		Color.html("#8d9bbd"))
	var rows := [
		["最远星区", "%02d" % zone],
		["擦弹", "%d" % graze],
		["击坠", "%d" % total_kills],
		["最高分", "%d" % best_score],
	]
	for i in range(rows.size()):
		var y := card.position.y + 200.0 + i * 34.0
		draw_rect(Rect2(card.position.x + 20, y - 18, card.size.x - 40, 30), Color(0.02, 0.031, 0.075, 0.6))
		draw_string(font, Vector2(card.position.x + 34, y + 4), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color.html("#5e6b8c"))
		draw_string(font, Vector2(card.position.x + 34, y + 4), rows[i][1], HORIZONTAL_ALIGNMENT_RIGHT,
			card.size.x - 68, 16, Color.html("#e8eeff"))
	draw_string(font, Vector2(0, CFG.HEIGHT * 0.28 + 460), "点按重新出击  ·  R",
		HORIZONTAL_ALIGNMENT_CENTER, CFG.WIDTH, 15, Color.html("#8fa4c9"))


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out
