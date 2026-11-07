extends Node2D

const CFG := preload("res://scripts/game_config.gd")

const PLAYER_FIRE_LEVEL := 2
const PLAYER_BULLET_RADIUS := 5.0
const ENEMY_BULLET_RADIUS := 6.0
const GAME_OVER_TAP_DELAY := 0.6

# 美术契约（与归档 Unity 版 ShipArt.cs 一致）：PNG 画布的最大半径 = 0.46 × 边长，
# 所以"视觉外缘 = 判定半径"时，画布边长 = radius / 0.46。
# Unity 原画布视觉半径约 26.8px；v1.1.0 为赛璐璐描边可读性放大到 36px，
# 判定半径仍是 4.6px（视觉远大于判定，标准弹幕手感）。敌机精灵机头朝下，无需旋转。
const ART_EXTENT := 0.46
const PLAYER_ART_RADIUS := 36.0
# 碎片绘制复用同一组顶点，避免每帧为 30 枚碎片重新分配数组
var mote_diamond := PackedVector2Array([
	Vector2(0, -8.5), Vector2(5.5, 0), Vector2(0, 8.5), Vector2(-5.5, 0)])
var mote_outline := PackedVector2Array([
	Vector2(0, -8.5), Vector2(5.5, 0), Vector2(0, 8.5), Vector2(-5.5, 0),
	Vector2(0, -8.5)])

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
var music: MusicPlayer
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
# v1.2.0 裂隙碎片 / 星区突破
var rift := 0
var motes: Array = []
var upgrades := {}
var upgrade_pending := false
var upgrade_options: Array = []
var game_over := false
var paused := false
var game_over_time := 0.0
var difficulty := "standard"

var player_bullets: Array = []
var enemy_bullets: Array = []
var enemies: Array = []

var pointer_active := false
var pointer_pos := Vector2.ZERO
var drag_offset := Vector2.ZERO
var spawn_timer := 1.0
var wave_timer := 2.0
var spawn_count := 0
var zone := 1
var zone_kills := 0
var zone_time := 0.0
var total_kills := 0
var _tex_cache: Dictionary = {}
var _keyart_cache: Dictionary = {}

# 自适应视口与安全区（长屏/平板/刘海屏）
var view_size := Vector2(CFG.WIDTH, CFG.HEIGHT)
var safe_top := 0.0
var safe_bottom := 0.0
var safe_left := 0.0
var safe_right := 0.0
var is_mobile := false

# 视觉层
var backdrop: SpaceBackdrop
var ui: UIOverlay
var fx: FXLayer
var shake := 0.0
var shake_t := 0.0
# UI 显示用插值：分数滚动、Boss 血条平滑
var display_score := 0.0
var display_boss_hp := 1.0

# 截图验收：`godot --path . -- -shot menu|play|boss`
var _shot_mode := ""
var _shot_t := 0.0
var _shot_taken := false
var _demo_no_fire := false


func _ready() -> void:
	randomize()
	_update_viewport_layout()
	get_viewport().size_changed.connect(_update_viewport_layout)
	is_mobile = OS.has_feature("mobile")
	player_pos = Vector2(view_size.x * 0.5, view_size.y - CFG.RESPAWN_INSET - safe_bottom)
	if is_mobile:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	weapons.spawn = _player_spawn_bullet
	sfx = Sfx.new()
	add_child(sfx)
	music = MusicPlayer.new()
	add_child(music)
	_load_font()
	_load_best()
	_spawn_visuals()
	var args := OS.get_cmdline_user_args()
	# headless 行为自检：`godot --headless --path . -- -selftest`
	if args.has("-selftest"):
		_run_selftest()
		return
	# 调试：`godot --path . -- -boss` 直接进 Boss 战（截图/验证用）
	if args.has("-boss"):
		in_menu = false
		_reset_game()
		_start_boss()
	if args.has("-shot"):
		var idx := args.find("-shot")
		if idx + 1 < args.size():
			_shot_mode = String(args[idx + 1])
		if _shot_mode == "play":
			in_menu = false
			_reset_game()
		elif _shot_mode.begins_with("boss"):
			in_menu = false
			_reset_game()
			# `boss` 默认第 1 台；`boss2`..`boss6` 用于逐个验收新外观
			var boss_idx := 0
			if _shot_mode.length() > 4:
				boss_idx = int(_shot_mode.substr(4)) - 1
			zone = boss_idx + 1
			_start_boss()
		elif _shot_mode == "demo":
			_demo_no_fire = true
			in_menu = false
			_reset_game()
		elif _shot_mode == "action":
			in_menu = false
			_reset_game()
			var kinds := ["drifter", "lancer", "orbiter", "bulwark", "sniper", "sidewinder"]
			for i in range(6):
				_spawn_enemy(kinds[i], Vector2(80.0 + (i % 3) * 180.0, 260.0 + (i / 3) * 180.0),
					i == 0, "none")
		elif _shot_mode == "upgrade":
			in_menu = false
			_reset_game()
			# 截图验收：预置层数，确保每张卡都能看到 ×N
			upgrades["damage_mul"] = 1.48
			upgrades["drone_rate"] = 1.75
			upgrades["max_hull"] = 4.0
			upgrades["nova_gain"] = 1.75
			upgrades["overdrive_bonus"] = 4.5
			upgrades["speed"] = 1.22
			upgrades["crate_rate"] = 1.75
			upgrades["break_mul"] = 1.75
			upgrades["rift_gain"] = 2.0
			_open_upgrade_draft()
		elif _shot_mode == "upgrade_apply":
			in_menu = false
			_reset_game()
			_open_upgrade_draft()
		elif _shot_mode == "motes":
			in_menu = false
			_reset_game()
			for i in range(8):
				var a := TAU * float(i) / 8.0
				_spawn_mote(player_pos + Vector2(cos(a), sin(a)) * 150.0)
		elif _shot_mode == "switch":
			# 截图验收：解锁全部武器线并切到棱镜，确认机体贴图跟随换线
			in_menu = false
			_reset_game()
			for l in weapons.lines:
				l.unlocked = true
			weapons.select_weapon("prism")
		elif _shot_mode == "pause" or _shot_mode == "gameover":
			in_menu = false
			_reset_game()
		_shot_taken = false


func _update_viewport_layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x < 1.0 or vs.y < 1.0:
		return
	view_size = vs
	CFG.set_view(vs)
	safe_top = 0.0
	safe_bottom = 0.0
	safe_left = 0.0
	safe_right = 0.0
	if OS.has_feature("mobile"):
		var win := Vector2(DisplayServer.window_get_size())
		var scale := minf(win.x / CFG.WIDTH, win.y / CFG.HEIGHT)
		if scale <= 0.0:
			scale = 1.0
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.size.x > 0.0 and safe.size.y > 0.0:
			safe_top = maxf(0.0, safe.position.y / scale)
			safe_bottom = maxf(0.0, (win.y - safe.end.y) / scale)
			safe_left = maxf(0.0, safe.position.x / scale)
			safe_right = maxf(0.0, (win.x - safe.end.x) / scale)
	CFG.set_safe(safe_top, safe_bottom, safe_left, safe_right)
	player_pos.x = clampf(player_pos.x, CFG.BOUND_SIDE_INSET, view_size.x - CFG.BOUND_SIDE_INSET)
	player_pos.y = clampf(player_pos.y, view_size.y * CFG.BOUND_TOP_FRAC,
		view_size.y - CFG.BOUND_BOTTOM_INSET - safe_bottom)


func _spawn_visuals() -> void:
	backdrop = SpaceBackdrop.new()
	backdrop.main = self
	backdrop.z_as_relative = false
	backdrop.z_index = -1000
	add_child(backdrop)
	fx = FXLayer.new()
	fx.font = ui_font
	add_child(fx)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	ui = UIOverlay.new()
	ui.main = self
	ui.font = ui_font
	layer.add_child(ui)


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


## 行为自检：确保判定不是"击杀帧才结算"的回归版本。
func _run_selftest() -> void:
	var failures := 0

	# 1) 没有任何击杀时，贴脸弹幕也必须扣除船体
	_reset_game()
	player_shields = 0
	player_invuln = 0.0
	var b1 := Bullet.new(player_pos, Vector2.ZERO, 6.0, 1.0, 4.0, false,
		Color.WHITE, "orb")
	b1.prev = player_pos
	enemy_bullets.append(b1)
	_resolve_collisions()
	if player_lives != 2:
		failures += 1
		print("SELFTEST_FAIL hazard lives=%d" % player_lives)

	# 2) 命中半径之外、擦弹半径之内：计数 +1 且掉落 1 枚碎片
	_reset_game()
	player_shields = 0
	player_invuln = 0.0
	graze = 0
	motes.clear()
	var b2 := Bullet.new(player_pos + Vector2(14.0, 0.0), Vector2.ZERO, 6.0, 1.0,
		4.0, false, Color.WHITE, "orb")
	b2.prev = b2.pos
	enemy_bullets.append(b2)
	_resolve_collisions()
	if graze != 1 or motes.size() != 1 or player_lives != 3:
		failures += 1
		print("SELFTEST_FAIL graze graze=%d motes=%d lives=%d"
		% [graze, motes.size(), player_lives])

	# 3) 最后一格船体被击穿：游戏结束且关闭突破草稿
	_reset_game()
	player_shields = 0
	player_lives = 1
	player_invuln = 0.0
	upgrade_pending = true
	upgrade_options = [CFG.UPGRADE_POOL[0]]
	var b3 := Bullet.new(player_pos, Vector2.ZERO, 6.0, 1.0, 4.0, false,
		Color.WHITE, "orb")
	b3.prev = player_pos
	enemy_bullets.append(b3)
	_resolve_collisions()
	if not game_over or upgrade_pending:
		failures += 1
		print("SELFTEST_FAIL draft game_over=%s pending=%s"
		% [str(game_over), str(upgrade_pending)])

	# 4) 开局 BGM 必须落在第 1 星区并处于播放状态
	if music == null or not music.is_playing() or music.current_zone() != 1:
		failures += 1
		print("SELFTEST_FAIL music playing=%s zone=%d"
		% [str(music != null and music.is_playing()),
		-1 if music == null else music.current_zone()])

	# 5) 星区最短时长：击杀配额满但时间不足时，不能提前进 Boss
	_reset_game()
	zone_kills = _zone_quota()
	zone_time = 0.0
	_update_spawner(0.05)
	if boss != null:
		failures += 1
		print("SELFTEST_FAIL pace early boss at 0s")
	zone_time = CFG.ZONE_MIN_TIME - 0.2
	_update_spawner(0.05)
	if boss != null:
		failures += 1
		print("SELFTEST_FAIL pace early boss at %.1fs" % zone_time)
	_update_spawner(0.3)
	if boss == null:
		failures += 1
		print("SELFTEST_FAIL pace no boss after %.1fs" % CFG.ZONE_MIN_TIME)

	if failures == 0:
		print("SELFTEST_OK n=5")
	else:
		print("SELFTEST_FAIL n=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


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


func _process(delta: float) -> void:
	if _shot_mode != "" and not _shot_taken:
		_shot_t += delta
		var wait := 3.6 if (_shot_mode == "play" or _shot_mode.begins_with("boss")) else 1.6
		if _shot_mode == "demo":
			wait = 4.8
		elif _shot_mode == "action":
			wait = 3.0
		elif _shot_mode == "pause" or _shot_mode == "gameover" or _shot_mode == "upgrade_apply":
			wait = 2.2
		if _shot_mode == "upgrade_apply" and upgrade_pending and _shot_t > 0.8:
			_choose_upgrade(0)
		if _shot_mode == "pause" and not paused and _shot_t > 1.0:
			paused = true
		if _shot_mode == "gameover" and not game_over and _shot_t > 1.0:
			game_over = true
			game_over_time = 1.0
			score = 66800
			zone = 5
			graze = 88
			rift = 32
			total_kills = 120
			best_score = 60000
		if _shot_t > wait:
			_shot_taken = true
			var dir := ProjectSettings.globalize_path("res://build/shots")
			DirAccess.make_dir_recursive_absolute(dir)
			var img := get_viewport().get_texture().get_image()
			var path := dir.path_join("ui_%s_%dx%d.png" % [_shot_mode,
				int(view_size.x), int(view_size.y)])
			img.save_png(path)
			print("SHOT_SAVED ", path)
			get_tree().quit()
	if in_menu:
		return
	if paused:
		queue_redraw()
		return
	if game_over:
		game_over_time += delta
		queue_redraw()
		return
	if upgrade_pending:
		queue_redraw()
		return

	if shake_t > 0.0:
		shake_t = maxf(0.0, shake_t - delta)
		if shake_t <= 0.0:
			shake = 0.0
	player_invuln = maxf(0.0, player_invuln - delta)
	_update_skills(delta)
	_update_economy(delta)
	_update_player(delta)
	_update_player_fire(delta)
	_update_enemies(delta)
	_update_boss(delta)
	_update_drones(delta)
	_update_crates(delta)
	_update_bullets(delta)
	_update_motes(delta)
	_update_spawner(delta)
	_resolve_collisions()
	queue_redraw()


func _add_shake(amount: float, duration := 0.24) -> void:
	shake = maxf(shake, amount)
	shake_t = maxf(shake_t, duration)


func _shake_offset() -> Vector2:
	if shake_t <= 0.0 or shake <= 0.0:
		return Vector2.ZERO
	var k := shake * clampf(shake_t / 0.24, 0.0, 1.0)
	return Vector2(randf_range(-k, k), randf_range(-k, k))


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
			var speed := CFG.PLAYER_SPEED * float(upgrades.get("speed", 1.0))
			player_pos += dir * speed * delta
			pointer_active = false
			player_last_dir = dir.x
		elif pointer_active:
			var target := pointer_pos + drag_offset
			var k := 1.0 - exp(-CFG.DRAG_FOLLOW_RATE * delta)
			player_pos = player_pos.lerp(target, k)
			player_last_dir = clampf((target.x - player_pos.x) * 0.02, -1.0, 1.0)

	var min_y := maxf(view_size.y * CFG.BOUND_TOP_FRAC, safe_top + 110.0)
	player_pos.x = clampf(player_pos.x, CFG.BOUND_SIDE_INSET, view_size.x - CFG.BOUND_SIDE_INSET)
	player_pos.y = clampf(player_pos.y, min_y,
		view_size.y - CFG.BOUND_BOTTOM_INSET - safe_bottom)
	player_bank = lerpf(player_bank, player_last_dir * 0.22, 1.0 - exp(-12.0 * delta))


func _update_player_fire(delta: float) -> void:
	if _demo_no_fire:
		return
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
	_gain_nova(CFG.NOVA_REGEN_PER_SECOND * delta)


func _update_economy(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			multiplier = 1


func _reset_upgrades() -> void:
	upgrades = {
		"damage_mul": 1.0, "drone_rate": 1.0, "max_hull": float(CFG.START_LIVES),
		"nova_gain": 1.0, "overdrive_bonus": 0.0, "speed": 1.0,
		"crate_rate": 1.0, "break_mul": 1.0,
		"rift_gain": 1.0, "rift_score": 1.0,
	}
	upgrade_pending = false
	upgrade_options.clear()
	rift = 0
	motes.clear()


func _gain_nova(amount: float) -> void:
	nova = minf(100.0, nova + amount * float(upgrades.get("nova_gain", 1.0)))


func _spawn_mote(pos: Vector2) -> void:
	if motes.size() >= CFG.MOTE_MAX:
		return
	motes.append({
		"pos": pos, "vel": Vector2(randf_range(-22.0, 22.0), randf_range(-8.0, 20.0)),
		"life": CFG.MOTE_LIFE, "spin": randf() * TAU,
	})


func _update_motes(delta: float) -> void:
	for i in range(motes.size() - 1, -1, -1):
		var m: Dictionary = motes[i]
		m["life"] = float(m["life"]) - delta
		if float(m["life"]) <= 0.0:
			motes.remove_at(i)
			continue
		var pos := Vector2(m["pos"])
		var to_player := player_pos - pos
		if to_player.length() < CFG.MOTE_MAGNET_RADIUS:
			pos += to_player.normalized() * CFG.MOTE_MAGNET_SPEED * delta
		else:
			pos += Vector2(m["vel"]) * delta
			m["vel"] = Vector2(m["vel"]) * maxf(0.0, 1.0 - 1.8 * delta)
		m["pos"] = pos
		m["spin"] = float(m["spin"]) + delta * 5.0
		if pos.distance_to(player_pos) < CFG.MOTE_COLLECT_RADIUS:
			motes.remove_at(i)
			_collect_mote()


func _collect_mote() -> void:
	rift += 1
	score += int(roundf(CFG.MOTE_SCORE * multiplier * float(upgrades.get("rift_score", 1.0))))
	combo_timer = maxf(combo_timer, CFG.MOTE_COMBO_EXTEND)
	_gain_nova(CFG.MOTE_NOVA * float(upgrades.get("rift_gain", 1.0)))
	if rift % 6 == 0 and fx != null:
		fx.float_text(player_pos + Vector2(0, -38), "裂隙 ×%d" % rift,
			Color.html("#8FF7EA"), 13)


## 已满级/已满层的强化不再进入卡池，避免三选一出废卡。
func _upgrade_available(u: Dictionary) -> bool:
	match String(u.get("id", "")):
		"hull":
			return float(upgrades["max_hull"]) < float(CFG.UPGRADE_MAX_HULL)
		"shield":
			return player_shields < CFG.MAX_SHIELDS
		"speed":
			return float(upgrades["speed"]) < CFG.UPGRADE_SPEED_MAX
	return true


## 当前已叠加层数，用于卡片右上角 ×N 提示。
func _upgrade_stacks(id: String) -> int:
	match id:
		"damage":
			return int(roundf((float(upgrades["damage_mul"]) - 1.0) / CFG.UPGRADE_DAMAGE_STEP))
		"drone":
			return int(roundf((float(upgrades["drone_rate"]) - 1.0) / CFG.UPGRADE_DRONE_STEP))
		"hull":
			return int(upgrades["max_hull"]) - CFG.START_LIVES
		"nova":
			return int(roundf((float(upgrades["nova_gain"]) - 1.0) / CFG.UPGRADE_NOVA_STEP))
		"overdrive":
			return int(roundf(float(upgrades["overdrive_bonus"]) / CFG.UPGRADE_OVERDRIVE_STEP))
		"speed":
			return int(roundf((float(upgrades["speed"]) - 1.0) / CFG.UPGRADE_SPEED_STEP))
		"crate":
			return int(roundf((float(upgrades["crate_rate"]) - 1.0) / CFG.UPGRADE_CRATE_STEP))
		"break":
			return int(roundf((float(upgrades["break_mul"]) - 1.0) / CFG.UPGRADE_BREAK_STEP))
		"rift":
			return int(roundf((float(upgrades["rift_gain"]) - 1.0) / CFG.UPGRADE_RIFT_NOVA_STEP))
	return 0


func _roll_upgrades() -> void:
	upgrade_options.clear()
	var pool: Array = []
	for u in CFG.UPGRADE_POOL:
		if _upgrade_available(u):
			var copy: Dictionary = u.duplicate()
			copy["stacks"] = _upgrade_stacks(String(u.get("id", "")))
			pool.append(copy)
	if pool.is_empty():
		pool = CFG.UPGRADE_POOL.duplicate()
	for i in range(mini(CFG.UPGRADE_CARD_COUNT, pool.size())):
		var idx := randi() % pool.size()
		upgrade_options.append(pool[idx])
		pool.remove_at(idx)


func _open_upgrade_draft() -> void:
	_roll_upgrades()
	upgrade_pending = true
	player_invuln = maxf(player_invuln, 1.0)
	_add_shake(8.0, 0.4)


func _choose_upgrade(index: int) -> void:
	if not upgrade_pending or index < 0 or index >= upgrade_options.size():
		return
	var u: Dictionary = upgrade_options[index]
	match String(u.get("id", "")):
		"damage":
			upgrades["damage_mul"] = float(upgrades["damage_mul"]) + CFG.UPGRADE_DAMAGE_STEP
		"drone":
			upgrades["drone_rate"] = float(upgrades["drone_rate"]) + CFG.UPGRADE_DRONE_STEP
		"hull":
			upgrades["max_hull"] = minf(CFG.UPGRADE_MAX_HULL,
				float(upgrades["max_hull"]) + 1.0)
			player_lives = mini(int(upgrades["max_hull"]), player_lives + 1)
		"shield":
			player_shields = mini(CFG.MAX_SHIELDS, player_shields + 1)
		"nova":
			upgrades["nova_gain"] = float(upgrades["nova_gain"]) + CFG.UPGRADE_NOVA_STEP
		"overdrive":
			upgrades["overdrive_bonus"] = float(upgrades["overdrive_bonus"]) + CFG.UPGRADE_OVERDRIVE_STEP
		"speed":
			upgrades["speed"] = minf(CFG.UPGRADE_SPEED_MAX,
				float(upgrades["speed"]) + CFG.UPGRADE_SPEED_STEP)
		"crate":
			upgrades["crate_rate"] = float(upgrades["crate_rate"]) + CFG.UPGRADE_CRATE_STEP
		"break":
			upgrades["break_mul"] = float(upgrades["break_mul"]) + CFG.UPGRADE_BREAK_STEP
		"rift":
			upgrades["rift_gain"] = float(upgrades["rift_gain"]) + CFG.UPGRADE_RIFT_NOVA_STEP
			upgrades["rift_score"] = float(upgrades["rift_score"]) + CFG.UPGRADE_RIFT_SCORE_STEP
	upgrade_pending = false
	upgrade_options.clear()
	zone = mini(10, zone + 1)
	zone_kills = 0
	zone_time = 0.0
	if music != null:
		music.play_zone(zone)
	boss_cleared = false
	boss_pending = false
	player_invuln = maxf(player_invuln, CFG.INVULN_ON_ZONE_CHANGE)
	crate_timer = minf(crate_timer, 4.0)
	sfx.play_pick()
	if fx != null:
		fx.float_text(player_pos + Vector2(0, -46), "星区突破 · %s" % String(u.get("name", "")),
			Color.html("#FFD27A"), 18)


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
	if fx != null:
		fx.dash(player_pos, dash_dir, Color.html("#57E6D8"))
	_add_shake(3.0, 0.16)


func _trigger_nova() -> void:
	if nova < 100.0:
		return
	nova = 0.0
	overdrive = CFG.OVERDRIVE_TIME + float(upgrades.get("overdrive_bonus", 0.0))
	player_invuln = maxf(player_invuln, CFG.INVULN_AFTER_NOVA)
	sfx.play_nova()
	if fx != null:
		fx.nova(player_pos)
	_add_shake(13.0, 0.45)
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
	return CFG.ZONE_QUOTA_BASE + zone * CFG.ZONE_QUOTA_STEP


## 星区击杀进度 0..1，HUD 进度条使用。
func zone_progress() -> float:
	# 击杀配额与最短时长都要满足，进度条取两者较小值
	var kills_k := float(zone_kills) / maxf(1.0, float(_zone_quota()))
	var time_k := float(zone_time) / CFG.ZONE_MIN_TIME
	return clampf(minf(kills_k, time_k), 0.0, 1.0)


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
	# 打满本区配额且停留够最短时长才进 Boss；Boss 战期间停刷小怪
	if boss != null:
		return
	zone_time += delta
	if zone_kills >= _zone_quota() and zone_time >= CFG.ZONE_MIN_TIME:
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
				var x := 90.0 + i * (view_size.x - 180.0) / maxf(1.0, count - 1.0)
				_spawn_enemy(kind, Vector2(x, -40.0 - absf(i - (count - 1) * 0.5) * 18.0),
					elite_wave and i == count / 2, affix)
		1:  # V 字
			for i in range(count):
				var off := i - (count - 1) * 0.5
				_spawn_enemy(kind, Vector2(view_size.x * 0.5 + off * 62.0, -40.0 - absf(off) * 34.0),
					elite_wave and absf(off) < 0.6, affix)
		2:  # 双列
			for i in range(count):
				var side := -1.0 if i % 2 == 0 else 1.0
				var row := i / 2
				_spawn_enemy(kind, Vector2(view_size.x * 0.5 + side * 120.0, -40.0 - row * 52.0),
					elite_wave and i < 2, affix)
		3:  # 集群
			for i in range(count + 1):
				_spawn_enemy(kind, Vector2(randf_range(70.0, view_size.x - 70.0), -40.0 - i * 26.0),
					elite_wave and i == 0, affix)
		_:  # 侧翼包抄
			for i in range(count):
				var side := -1.0 if i < count * 0.5 else 1.0
				_spawn_enemy(kind, Vector2(view_size.x * 0.5 + side * (150.0 + i * 16.0), -40.0 - (i % 2) * 30.0),
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
	# 六台 Boss 按星区轮换（第 7 星区起回到第 1 台）
	boss.setup((zone - 1) % 6, zone, _density_tier(), CFG.DIFFICULTY[difficulty])
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
		if fx != null:
			fx.explode(boss.pos, Color.html("#FFB3D9"), boss.size * 1.6, true)
			fx.nova(boss.pos)
		_add_shake(15.0, 0.55)
		boss = null
		boss_cleared = true
		zone_kills = 0
		enemy_bullets.clear()
		_open_upgrade_draft()


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
		d["timer"] = float(d["timer"]) - delta * float(upgrades.get("drone_rate", 1.0))
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
						_gain_nova(CFG.NOVA_ON_POINT_DEFENSE)


# ---------------------------------------------------------------- 补给箱

func _update_crates(delta: float) -> void:
	crate_timer -= delta * float(upgrades.get("crate_rate", 1.0))
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
	var kind: String = kinds[randi() % kinds.size()]
	# 第二条武器线没解锁时，补给箱优先掉落棱镜，保证玩家在本局能换机
	if weapons.unlocked_count() < 2 and not weapons.line("prism").unlocked:
		kind = "prism"
	var c := Crate.new()
	c.setup(Vector2(randf_range(60.0, view_size.x - 60.0), -30.0), kind)
	crates.append(c)


func _apply_crate(kind: String) -> void:
	sfx.play_pick()
	if fx != null:
		var labels := {
			"weapon": "武器强化", "drone": "僚机 +1", "life": "船体修复",
			"shield": "护盾 +1", "charge": "能量满充", "nova": "星爆就绪",
			"gem": "+500", "swap": "解锁武器线", "reflect": "反射护盾", "prism": "棱镜解锁",
		}
		fx.pickup(player_pos, Color.html("#FFC554"), String(labels.get(kind, "补给")))
	match kind:
		"weapon":
			weapons.grant_level()
		"drone":
			_add_drone()
		"life":
			player_lives = mini(int(upgrades.get("max_hull", CFG.START_LIVES)), player_lives + 1)
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
	_advance_bullets(player_bullets, delta)
	_advance_bullets(enemy_bullets, delta)


func _advance_bullets(arr: Array, delta: float) -> void:
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
		if b.life <= 0.0 or b.pos.y < -40.0 or b.pos.y > view_size.y + 40.0 \
				or b.pos.x < -40.0 or b.pos.x > view_size.x + 40.0:
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
				var bdmg := b.damage * float(upgrades.get("damage_mul", 1.0)) \
					* float(upgrades.get("break_mul", 1.0)) \
					* (CFG.PRISM_BOSS_BONUS if b.kind == "lance" else 1.0)
				if boss.take_damage(bdmg):
					sfx.play_hit()
				boss.damage_flash()
				if fx != null:
					fx.hit(b.pos, Color.html("#FFF0C2"))
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
				e.hp -= b.damage * e.damage_taken_mul * float(upgrades.get("damage_mul", 1.0))
				e.flash = 0.08
				if fx != null:
					fx.hit(b.pos, Color(1.0, 0.92, 0.68))
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
	_resolve_player_hazards()


## 玩家受击 / 擦弹判定：每帧独立结算，不能放进击杀回调。
## 对齐 web 版 collide()：先擦弹（命中半径之外），再命中，最后机体接触。
func _resolve_player_hazards() -> void:
	if player_invuln > 0.0:
		return
	for i in range(enemy_bullets.size() - 1, -1, -1):
		var b: Bullet = enemy_bullets[i]
		var d2 := _seg_point_d2(b.prev, b.pos, player_pos)
		var hit_r := CFG.PLAYER_HIT_R + b.radius
		var graze_r := CFG.PLAYER_GRAZE_R + b.radius
		if not b.grazed and d2 <= graze_r * graze_r and d2 > hit_r * hit_r:
			b.grazed = true
			graze += 1
			_gain_nova(CFG.NOVA_ON_GRAZE)
			_spawn_mote(b.pos)
		elif d2 <= hit_r * hit_r:
			enemy_bullets.remove_at(i)
			_player_hit()
			return
	for en: Enemy in enemies:
		var rr: float = CFG.PLAYER_HIT_R + en.hit_r
		if player_pos.distance_squared_to(en.pos) <= rr * rr:
			_player_hit()
			return


func _kill_enemy(index: int, diff: Dictionary) -> void:
	var e: Enemy = enemies[index]
	score += int(roundf(e.score_value * float(diff["scoreMul"]) * multiplier))
	_gain_nova(CFG.NOVA_ON_ELITE_KILL if e.elite else CFG.NOVA_ON_KILL)
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
	if fx != null:
		var col := Color.html(String(e.def.get("color", "#ff6f91")))
		fx.explode(at, col, e.size, e.elite)
		fx.float_text(at + Vector2(0, -e.size * 0.7), "+%d" % int(e.score_value),
			Color(1.0, 0.94, 0.72), 14)
	_add_shake(5.0 if e.elite else 1.8, 0.26)


func _player_hit() -> void:
	sfx.play_hit()
	if fx != null:
		fx.explode(player_pos, Color.html("#FF6B7A"), 34.0, true)
	_add_shake(10.0, 0.36)
	# 护盾优先，掉了只丢一层；护盾耗尽才吃船体
	if player_shields > 0:
		player_shields -= 1
		player_invuln = CFG.INVULN_AFTER_SHIELD
		_gain_nova(CFG.NOVA_ON_SHIELD_BREAK)
	else:
		player_lives -= 1
		player_invuln = CFG.INVULN_AFTER_HULL_HIT
		_gain_nova(CFG.NOVA_ON_HULL_HIT)
		combo = 0
		multiplier = 1
		combo_timer = 0.0
	enemy_bullets.clear()
	weapons.active().charge = maxf(0.0, weapons.active().charge - CFG.HIT_CHARGE_PENALTY)
	if player_lives <= 0:
		game_over = true
		game_over_time = 0.0
		# 死亡立即关闭突破草稿，避免结算被三选一卡片挡住
		upgrade_pending = false
		upgrade_options.clear()
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
	if upgrade_pending:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_1:
				_choose_upgrade(0)
			elif event.keycode == KEY_2:
				_choose_upgrade(1)
			elif event.keycode == KEY_3:
				_choose_upgrade(2)
		elif (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			if ui != null:
				var choice: String = ui.press(event.position)
				if choice.begins_with("upgrade_"):
					_choose_upgrade(int(choice.substr(8)))
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if in_menu:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				_start_run()
			elif event.keycode == KEY_1:
				difficulty = "cruise"
			elif event.keycode == KEY_2:
				difficulty = "standard"
			elif event.keycode == KEY_3:
				difficulty = "abyss"
			return
		if paused:
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
				paused = false
				if music != null:
					music.set_paused(false)
			return
		if game_over:
			if event.keycode == KEY_R or event.keycode == KEY_ENTER:
				_start_run()
			return
		match event.keycode:
			KEY_R:
				_reset_game()
			KEY_ESCAPE, KEY_P:
				paused = true
				if music != null:
					music.set_paused(true)
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
		return

	var press_pos := Vector2.ZERO
	var is_press := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		press_pos = event.position
		is_press = event.pressed
		if in_menu or paused or game_over:
			if is_press and ui != null:
				_handle_ui_action(ui.press(press_pos))
			return
		if is_press and ui != null:
			var a: String = ui.press(press_pos)
			if a != "":
				_handle_ui_action(a)
				return
		pointer_active = is_press
		if is_press:
			pointer_pos = press_pos
			_start_drag()
	elif event is InputEventMouseMotion and pointer_active:
		pointer_pos = event.position
	elif event is InputEventScreenTouch:
		press_pos = event.position
		is_press = event.pressed
		if in_menu or paused or game_over:
			if is_press and ui != null:
				_handle_ui_action(ui.press(press_pos))
			return
		if is_press and ui != null:
			var a: String = ui.press(press_pos)
			if a != "":
				_handle_ui_action(a)
				return
		pointer_active = is_press
		if is_press:
			pointer_pos = press_pos
			_start_drag()
	elif event is InputEventScreenDrag:
		pointer_pos = event.position


func _handle_ui_action(action: String) -> bool:
	if action.begins_with("upgrade_"):
		_choose_upgrade(int(action.substr(8)))
		return true
	match action:
		"":
			return false
		"diff_cruise":
			difficulty = "cruise"
		"diff_standard":
			difficulty = "standard"
		"diff_abyss":
			difficulty = "abyss"
		"start":
			_start_run()
		"pause":
			paused = true
			if music != null:
				music.set_paused(true)
		"nova":
			_trigger_nova()
		"dash":
			_trigger_dash()
		"weapon":
			if weapons.cycle_weapon():
				swap_idle = 0.0
			elif fx != null:
				fx.float_text(player_pos + Vector2(0, -46), "拾取棱镜补给解锁换线",
					Color.html("#FFD27A"), 13)
		"resume":
			paused = false
			if music != null:
				music.set_paused(false)
		"restart", "retry":
			_start_run()
		"menu":
			_to_menu()
		_:
			return false
	return true


func _start_drag() -> void:
	drag_offset.x = clampf(player_pos.x - pointer_pos.x, -view_size.x * 0.3, view_size.x * 0.3)
	drag_offset.y = clampf(player_pos.y - pointer_pos.y, -140.0, 60.0)


func _start_run() -> void:
	_reset_game()


func _to_menu() -> void:
	_save_best()
	_reset_upgrades()
	in_menu = true
	paused = false
	game_over = false
	score = 0
	display_score = 0.0
	display_boss_hp = 1.0
	graze = 0
	combo = 0
	multiplier = 1
	zone = 1
	zone_kills = 0
	zone_time = 0.0
	total_kills = 0
	player_bullets.clear()
	enemy_bullets.clear()
	enemies.clear()
	crates.clear()
	drones.clear()
	boss = null
	boss_pending = false
	boss_cleared = false
	player_pos = Vector2(view_size.x * 0.5, view_size.y - CFG.RESPAWN_INSET - safe_bottom)
	if music != null:
		music.stop()


func _reset_game() -> void:
	in_menu = false
	_reset_upgrades()
	player_pos = Vector2(view_size.x * 0.5, view_size.y - CFG.RESPAWN_INSET - safe_bottom)
	player_lives = int(upgrades["max_hull"])
	player_invuln = CFG.INVULN_ON_SPAWN
	player_bank = 0.0
	fire_timer = 0.0
	score = 0
	display_score = 0.0
	display_boss_hp = 1.0
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
	zone_time = 0.0
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
	if music != null:
		music.play_zone(1)
		music.set_paused(false)


func _ship_tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := "res://assets/ships/%s.png" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[name] = tex
	return tex


func _keyart_tex(name: String) -> Texture2D:
	if _keyart_cache.has(name):
		return _keyart_cache[name]
	var path := "res://assets/keyart/%s.png" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_keyart_cache[name] = tex
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
	if in_menu:
		return
	var off := _shake_offset()
	draw_set_transform(off, 0.0, Vector2.ONE)
	_draw_crates()
	_draw_bullets()
	_draw_motes()
	_draw_enemies()
	if boss != null:
		_draw_boss()
	if not game_over:
		_draw_player()
		_draw_drones()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _blob(center: Vector2, radius: float, col: Color, layers := 7) -> void:
	for i in range(layers, 0, -1):
		var k := float(i) / float(layers)
		draw_circle(center, radius * k, Color(col.r, col.g, col.b, col.a / float(layers)))


func _draw_boss() -> void:
	var art: String = ["boss_gatekeeper", "boss_weaver", "boss_helios",
		"boss_dreadnought", "boss_serpent", "boss_seraph"][boss.index]
	var ring: String = ["boss_gatekeeper_ring", "boss_weaver_ring", "boss_helios_ring",
		"boss_dreadnought_ring", "boss_serpent_ring", "boss_seraph_ring"][boss.index]
	var alpha := 1.0
	var grow := 1.06
	if boss.dying:
		var k := clampf(boss.die_t / 1.2, 0.0, 1.0)
		alpha = 1.0 - k
		grow = 1.06 + k * 0.16
	_draw_shadow(boss.pos + Vector2(0, 12), boss.size * 0.98, Color(0.10, 0.06, 0.16, 0.24 * alpha))
	_blob(boss.pos, boss.size * 1.42, Color(1.0, 0.96, 0.86, 0.10 * alpha), 8)
	if boss.telegraph > 0.0 and not boss.dying:
		var k := clampf(float(boss.telegraph) / 0.5, 0.0, 1.0)
		var warn: Color = boss.tell_color
		draw_arc(boss.pos, boss.size * (1.16 + (1.0 - k) * 0.22), 0, TAU, 64,
			Color(warn.r, warn.g, warn.b, 0.35 + 0.45 * k), 3.0, true)
		for i in range(8):
			var ang := TAU * float(i) / 8.0
			draw_line(boss.pos + Vector2(cos(ang), sin(ang)) * boss.size * 1.2,
				boss.pos + Vector2(cos(ang), sin(ang)) * boss.size * 1.46,
				Color(warn.r, warn.g, warn.b, 0.55 * k), 2.0, true)
	_draw_ship(art, boss.pos, boss.size * grow, 0.0, Color(1, 1, 1, alpha))
	_draw_ship(ring, boss.pos, boss.size * grow * 1.08, -boss.spin * 0.8,
		Color(1, 1, 1, (0.62 if boss.phase >= 1 else 0.40) * alpha))
	if boss.flash > 0.0:
		_draw_ship(art + "_mask", boss.pos, boss.size * grow, 0.0,
			Color(1, 1, 1, clampf(boss.flash / 0.08, 0.0, 1.0) * 0.85 * alpha))


func _draw_crates() -> void:
	for c in crates:
		var tex := _ship_tex("crate_" + (c.kind if c.kind != "nova" else "gem"))
		var side := 38.0 + sin(c.spin) * 2.0
		_draw_shadow(c.pos + Vector2(0, 7), 16.0, Color(0.10, 0.06, 0.16, 0.20))
		_blob(c.pos, 26.0, Color(1.0, 0.93, 0.72, 0.20), 5)
		if tex != null:
			draw_set_transform(c.pos, c.spin * 0.15, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-side * 0.5, -side * 0.5, side, side), false, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(Rect2(c.pos - Vector2(13, 13), Vector2(26, 26)), Color(0.41, 0.96, 0.86, 0.8))
		draw_arc(c.pos, side * 0.72, c.spin * 0.4, c.spin * 0.4 + PI * 1.1, 20,
			Color(1, 1, 1, 0.30), 1.5, true)


func _draw_drones() -> void:
	var slots := _drone_slots()
	var art := {"gunner": "drone_cannon", "lance": "drone_seeker", "aegis": "drone_support", "swarm": "drone_swarm"}
	for i in range(drones.size()):
		var slot: Vector2 = slots[i] if i < slots.size() else Vector2.ZERO
		var dp := player_pos + slot
		_blob(dp, 17.0, Color(0.85, 1.0, 0.96, 0.18), 5)
		_draw_ship(String(art[drones[i]["kind"]]), dp, 16.0, 0.0, Color(1, 1, 1, 0.96))


func _draw_motes() -> void:
	for m in motes:
		var pos := Vector2(m["pos"])
		var spin := float(m["spin"])
		var life_k := clampf(float(m["life"]) / CFG.MOTE_LIFE, 0.0, 1.0)
		if life_k > 0.35:
			_blob(pos, 16.0, Color(0.45, 1.0, 0.92, 0.20 * life_k), 3)
		draw_set_transform(pos, spin, Vector2.ONE)
		draw_colored_polygon(mote_diamond, Color(0.62, 1.0, 0.95, 0.98 * life_k))
		draw_polyline(mote_outline, Color(0.10, 0.10, 0.18, 0.60 * life_k), 1.8, true)
		draw_circle(Vector2(0, 0), 2.8, Color(1, 1, 1, 0.95 * life_k))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bullets() -> void:
	for b in player_bullets:
		var col: Color = b.tint
		var dir: Vector2 = b.vel.normalized()
		var tail: Vector2 = b.pos - dir * minf(20.0, b.pos.distance_to(b.prev))
		draw_line(tail, b.pos, Color(col.r, col.g, col.b, 0.35), b.radius * 1.25, true)
		draw_circle(b.pos, b.radius * 1.5, Color(col.r, col.g, col.b, 0.16))
		match String(b.kind):
			"lance":
				var half: Vector2 = dir * b.radius * 3.2
				draw_line(b.pos - half, b.pos + half, Color(1, 1, 1, 0.85), b.radius * 0.7, true)
				draw_line(b.pos - half * 0.8, b.pos + half * 0.8, col, b.radius * 1.5, true)
			"bolt", "micro":
				var half2: Vector2 = dir * b.radius * 1.7
				draw_line(b.pos - half2, b.pos + half2, col, b.radius * 0.9, true)
				draw_circle(b.pos, b.radius * 0.62, Color(1, 1, 1, 0.9))
			_:
				draw_circle(b.pos, b.radius, col)
				draw_circle(b.pos, b.radius * 0.5, Color(1, 1, 1, 0.85))
	for b in enemy_bullets:
		var ecol: Color = b.tint
		var r: float = b.radius
		draw_circle(b.pos, r + 3.0, Color(0.12, 0.08, 0.18, 0.42))
		draw_circle(b.pos, r + 1.5, Color(ecol.r, ecol.g, ecol.b, 0.30))
		draw_circle(b.pos, r, ecol)
		draw_circle(b.pos, r * 0.42, Color(1, 1, 1, 0.92))
		match String(b.kind):
			"shard", "needle":
				var dir2: Vector2 = b.vel.normalized()
				var side: Vector2 = dir2.orthogonal()
				var pts := PackedVector2Array([
					b.pos + dir2 * r * 1.9, b.pos + side * r * 0.75,
					b.pos - dir2 * r * 1.2, b.pos - side * r * 0.75,
				])
				draw_colored_polygon(pts, Color(ecol.r, ecol.g, ecol.b, 0.82))
				draw_polyline(_closed(pts), Color(0.12, 0.08, 0.18, 0.55), 1.5, true)
			"heavy", "plasma":
				draw_arc(b.pos, r + 4.0, 0, TAU, 24, Color(ecol.r, ecol.g, ecol.b, 0.55), 2.0, true)
			"mine":
				for i in range(6):
					var a2: float = TAU * float(i) / 6.0 + float(b.age)
					draw_line(b.pos + Vector2(cos(a2), sin(a2)) * r,
						b.pos + Vector2(cos(a2), sin(a2)) * (r + 5.0),
						Color(1.0, 0.86, 0.45, 0.85), 1.5, true)
			"wave":
				var wdir: Vector2 = b.vel.normalized().orthogonal()
				draw_circle(b.pos + wdir * sin(b.age * 8.0) * 7.0, r * 0.9,
					Color(ecol.r, ecol.g, ecol.b, 0.55))


func _draw_player() -> void:
	var blink := player_invuln > 0.0 and int(player_invuln * 18.0) % 2 == 0
	var alpha := 0.35 if blink else 1.0
	var tint := Color.html(String(CFG.WEAPON_LINES[String(weapons.active_id)]["tint"]))
	_draw_shadow(player_pos + Vector2(0, 15), PLAYER_ART_RADIUS * 0.92,
		Color(0.10, 0.06, 0.16, 0.24 * alpha))
	_blob(player_pos, PLAYER_ART_RADIUS * 1.65, Color(1.0, 0.96, 0.86, 0.26 * alpha), 9)
	_blob(player_pos, PLAYER_ART_RADIUS * 1.12, Color(tint.r, tint.g, tint.b, 0.24 * alpha), 5)
	_draw_engine_flame(alpha, tint)
	var art := "player_" + String(weapons.active_id)
	if not _draw_ship(art, player_pos, PLAYER_ART_RADIUS, player_bank, Color(1.05, 1.05, 1.02, alpha)):
		_draw_player_fallback(alpha)
	else:
		# 白色剪影轻叠一层，把赛璐璐阴影提亮成奶油色，同时不盖住描边
		_draw_ship(art + "_mask", player_pos, PLAYER_ART_RADIUS, player_bank,
			Color(1.0, 0.99, 0.94, 0.28 * alpha))
	if dash_t > 0.0:
		draw_arc(player_pos, PLAYER_ART_RADIUS * 1.25, 0, TAU, 40,
			Color(0.45, 1.0, 0.9, 0.55), 2.0, true)


func _draw_engine_flame(alpha: float, tint: Color) -> void:
	var flick := 0.86 + 0.20 * sin(Time.get_ticks_msec() * 0.045)
	var boost := 1.6 if overdrive > 0.0 else 1.0
	var ln := 34.0 * flick * boost
	draw_set_transform(player_pos + Vector2(0, 30), player_bank, Vector2.ONE)
	var outer := PackedVector2Array([Vector2(-9, 0), Vector2(0, ln), Vector2(9, 0)])
	draw_colored_polygon(outer, Color(tint.r, tint.g, tint.b, 0.48 * alpha))
	var inner := PackedVector2Array([Vector2(-4.5, 1), Vector2(0, ln * 0.64), Vector2(4.5, 1)])
	draw_colored_polygon(inner, Color(1.0, 0.95, 0.78, 0.80 * alpha))
	draw_circle(Vector2(0, 2), 5.0, Color(1.0, 0.98, 0.90, 0.55 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		var vis := e.size * 1.06
		_draw_shadow(e.pos + Vector2(0, e.size * 0.42), e.size * 0.92,
			Color(0.10, 0.06, 0.16, 0.20))
		_blob(e.pos, e.size * 1.32, Color(1.0, 0.96, 0.88, 0.12), 5)
		if e.elite:
			_blob(e.pos, e.size * 1.55, Color(1.0, 0.85, 0.45, 0.18), 6)
			draw_arc(e.pos, e.size * 1.34, 0, TAU, 36, Color(1.0, 0.82, 0.35, 0.55), 2.0, true)
			star_dot(e.pos + Vector2(e.size * 1.25, -e.size * 1.05), 5.0, Color(1, 0.9, 0.55))
		if not _draw_ship("enemy_" + e.kind, e.pos, vis, ang, Color(1.04, 1.04, 1.02)):
			draw_circle(e.pos, e.size * 1.45, Color(base.r, base.g, base.b, 0.12))
			var pts := _enemy_shape(e)
			draw_colored_polygon(pts, Color(base.r, base.g, base.b, 0.92))
			draw_polyline(_closed(pts), accent, 1.2, true)
		else:
			_draw_ship("enemy_" + e.kind + "_mask", e.pos, vis, ang,
				Color(1.0, 0.98, 0.93, 0.08))
			if e.flash > 0.0:
				_draw_ship("enemy_" + e.kind + "_mask", e.pos, vis, ang,
					Color(1, 1, 1, clampf(e.flash / 0.08, 0.0, 1.0) * 0.85))
		if e.max_hp > 20.0:
			var w: float = e.size * 2.0
			var ratio := clampf(e.hp / e.max_hp, 0.0, 1.0)
			var hr := Rect2(e.pos.x - w * 0.5, e.pos.y - e.size - 10.0, w, 4.0)
			draw_rect(hr.grow(1.5), Color(0.12, 0.08, 0.18, 0.75))
			draw_rect(Rect2(hr.position, Vector2(w * ratio, hr.size.y)), accent)
			draw_rect(Rect2(hr.position, Vector2(w, 1.0)), Color(1, 1, 1, 0.35))


func _draw_shadow(center: Vector2, radius: float, col: Color) -> void:
	draw_set_transform(center, 0.0, Vector2(1.0, 0.62))
	draw_circle(Vector2.ZERO, radius, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func star_dot(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(8):
		var a := -PI * 0.5 + PI * float(i) / 4.0
		var rr := r if i % 2 == 0 else r * 0.35
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)


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


func _grade() -> String:
	if score >= CFG.GRADE_S:
		return "S"
	if score >= CFG.GRADE_A:
		return "A"
	if score >= CFG.GRADE_B:
		return "B"
	return "C"


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(points)
	if out.size() > 0:
		out.append(out[0])
	return out
