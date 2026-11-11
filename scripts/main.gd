extends Node2D

const CFG := preload("res://scripts/game_config.gd")

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
	var turn_rate := 4.6     # 追踪转向速率（rad/s）
	var phased := false      # 相位冲刺已标记（不再重复计分）
	var boss_bonus := 1.0
	var hit_enemies: Array = []  # 贯穿弹已 hit 过的敌机，避免一帧多次扣血
	var seed := randf() * 10.0   # 波动相位/破片角偏移（Unity _seed）
	var armed := false           # 水雷引信 <0.9s 的一次性提示闪光
	var homing_target = null     # 追踪缓存目标（Enemy 或 Boss，Unity HomingTarget）
	var hit_boss := false        # Unity HitBoss：同一颗弹对 Boss 只结算一次

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


## Boss 光束（Unity BossLaser）：原点跟随本体，warn 期冻结角度，active 期才扫。
class Beam:
	var angle := 0.0
	var warn := 0.9
	var active := 0.9
	var width := 14.0
	var sweep := 0.0
	var t := 0.0


var player_pos := Vector2(CFG.WIDTH * 0.5, CFG.HEIGHT - 130.0)
var player_lives := 3
var player_invuln := 0.0
var player_bank := 0.0
var player_last_dir := 0.0
var hurt_flash := 0.0     # 纯视觉：船体受击屏幕边缘红闪，UIOverlay 消费衰减
var shield_flash := 0.0   # 纯视觉：护盾破碎/获得屏幕边缘青闪，UIOverlay 消费衰减


# 武器与玩家生存/技能（迁移C）
var weapons := WeaponSystem.new()
var player_shields := 1
var nova := 0.0            # 星爆充能 0..100
var overdrive := 0.0       # 超频剩余时间
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var reflect_t := 0.0       # 反射护盾剩余时间（吸收敌弹 + 一次免死）
var swap_idle := 0.0
var combo := 0
var combo_timer := 0.0
var multiplier := 1

# 界面状态 / 存档 / 音效
var in_menu := true
var settings_open := false
var best_score := 0
var sfx: Sfx
var music: MusicPlayer
var ui_font: Font

# Boss / 补给 / 僚机
var boss: Boss = null
var boss_pending := false
var boss_cleared := false
var boss_warn := 0.0       # Boss 预警倒计时（Unity Clearing→3s WARNING 清场）
var beams: Array = []
var crates: Array = []
var crate_timer := CFG.SUPPLY_INTERVAL
var pity_weapon := 0       # 连续未出成长箱计数（Unity pityWeapon）
var pity_drone := 0        # 连续未出僚机箱计数（Unity pityDrone）
var clear_hold := 0.0      # Boss 击破后的结算缓冲（Unity Intermission clearHold 4.4s）
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
var won := false
var paused := false
var game_over_time := 0.0
var difficulty := "standard"

var player_bullets: Array = []
var enemy_bullets: Array = []
var enemies: Array = []

var pointer_active := false
var pointer_pos := Vector2.ZERO
var drag_offset := Vector2.ZERO
var zone := 1
var total_kills := 0
var _tex_cache: Dictionary = {}
var _keyart_cache: Dictionary = {}
# 热路径用：避免每帧把 "#ff6f91" 这种字符串重新解析成 Color
var _color_cache: Dictionary = {}

# 自适应视口与安全区（长屏/平板/刘海屏）
var view_size := Vector2(CFG.WIDTH, CFG.HEIGHT)
var safe_top := 0.0
var safe_bottom := 0.0
var safe_left := 0.0
var safe_right := 0.0
var is_mobile := false
# 设置（持久化）与破坏性操作二次确认
var opt_music := true
var opt_sfx := true
var opt_shake := true
var confirm_action := ""
var confirm_t := 0.0

# 视觉层
var backdrop: SpaceBackdrop
var ui: UIOverlay
var fx: FXLayer
var shake := 0.0
var shake_t := 0.0
# 手感层：打击停顿（冻结）与慢镜（拖慢），对齐原版 Freeze/Slow 常量
var hitstop := 0.0
var slowmo_t := 0.0
var slowmo_scale := 1.0
# UI 显示用插值：分数滚动、Boss 血条平滑
var display_score := 0.0
var display_boss_hp := 1.0

# 截图验收：`godot --path . -- -shot menu|play|boss`
var _shot_mode := ""
var _shot_t := 0.0
var _shot_taken := false
var _demo_no_fire := false

# 拆分出的职责模块（状态仍在 Main，模块负责结算逻辑）
var waves: WaveDirector
var collisions: CollisionSystem
var upgrade_flow: UpgradeSystem


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
	waves = WaveDirector.new(self)
	collisions = CollisionSystem.new(self)
	upgrade_flow = UpgradeSystem.new(self)
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
	if args.has("-play"):
		# 调试：直接开局（截图/长跑验证用）
		in_menu = false
		_reset_game()
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
		elif _shot_mode == "crates":
			# 补给箱陈列截图（验证掉落物在中屏且可辨识）
			in_menu = false
			_reset_game()
			var demo_kinds := ["weapon", "prism", "drone", "life", "reflect"]
			for i in range(demo_kinds.size()):
				var c := Crate.new()
				c.setup(Vector2(view_size.x * (0.18 + i * 0.16), view_size.y * 0.55),
					String(demo_kinds[i]))
				crates.append(c)
		elif _shot_mode == "victory":
			# 终局胜利结算截图
			in_menu = false
			_reset_game()
			zone = 10
			won = true
			game_over = true
			game_over_time = 1.0
			score = 126800
			graze = 132
			rift = 48
			total_kills = 260
			_save_best()
		elif _shot_mode == "demo":
			_demo_no_fire = true
			in_menu = false
			_reset_game()
		elif _shot_mode == "action":
			in_menu = false
			_reset_game()
			var kinds := ["drifter", "lancer", "orbiter", "bulwark", "sniper", "sidewinder"]
			for i in range(6):
				waves.spawn_enemy(kinds[i], Vector2(80.0 + (i % 3) * 180.0, 260.0 + (i / 3) * 180.0),
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
		elif _shot_mode == "hurt":
			# 纯视觉验收：受击/护盾边缘闪（DevShots）
			in_menu = false
			_reset_game()
		elif _shot_mode == "settings":
			in_menu = true
			settings_open = true
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
		opt_music = bool(cfg.get_value("opt", "music", true))
		opt_sfx = bool(cfg.get_value("opt", "sfx", true))
		opt_shake = bool(cfg.get_value("opt", "shake", true))
	_apply_opts()


func _save_opts() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://save.cfg")
	cfg.set_value("score", "best", best_score)
	cfg.set_value("opt", "music", opt_music)
	cfg.set_value("opt", "sfx", opt_sfx)
	cfg.set_value("opt", "shake", opt_shake)
	cfg.save("user://save.cfg")


func _apply_opts() -> void:
	if sfx != null:
		sfx.enabled = opt_sfx
	if music != null:
		music.enabled = opt_music
		if not opt_music:
			music.stop()


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
	collisions.resolve()
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
	collisions.resolve()
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
	collisions.resolve()
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

	# 5) 星区节奏：配额满但时间不足不清场；时间到进清场；清场后 WARNING 3s 才出 Boss
	_reset_game()
	waves.zone_kills = waves.quota()
	waves.zone_time = 0.0
	waves.tick(0.05)
	if waves.clearing or boss != null:
		failures += 1
		print("SELFTEST_FAIL pace early clear at 0s")
	waves.zone_time = CFG.ZONE_MIN_TIME - 0.2
	waves.tick(0.05)
	if waves.clearing or boss != null:
		failures += 1
		print("SELFTEST_FAIL pace early clear at %.1fs" % waves.zone_time)
	waves.tick(0.3)
	if not waves.clearing or boss != null:
		failures += 1
		print("SELFTEST_FAIL pace no clearing after %.1fs" % CFG.ZONE_MIN_TIME)
	for i in range(30):
		waves.tick(0.1)
	if boss_warn <= 0.0:
		failures += 1
		print("SELFTEST_FAIL pace no warning after clear")
	for i in range(35):
		waves.tick(0.1)
	if boss == null:
		failures += 1
		print("SELFTEST_FAIL pace no boss after warning")

	# 6) Boss 光束：active 期玩家压在射线上扣船体（Unity BossLaser.CheckHit）
	_reset_game()
	player_shields = 0
	player_invuln = 0.0
	_start_boss()
	boss.entered = true
	boss.pos = player_pos + Vector2(0, -200.0)
	var bm := Beam.new()
	bm.angle = PI * 0.5
	bm.warn = 0.5
	bm.active = 1.0
	bm.width = 14.0
	bm.t = 0.6
	beams.append(bm)
	_update_beams(0.016)
	if player_lives != 2:
		failures += 1
		print("SELFTEST_FAIL beam lives=%d" % player_lives)

	# 7) 水雷引信到期：炸默认 10 颗破片、本体移除、破片速度随星区
	_reset_game()
	var mine := Bullet.new(Vector2(270, 300), Vector2(60, 0), 9.0, 1.0, 8.0,
		false, Color.WHITE, "mine")
	mine.fuse = 0.01
	mine.split_on_expire = 0
	enemy_bullets.append(mine)
	_advance_bullets(enemy_bullets, 0.05)
	if enemy_bullets.size() != CFG.MINE_BURST_COUNT:
		failures += 1
		print("SELFTEST_FAIL mine burst n=%d" % enemy_bullets.size())
	elif not is_equal_approx(enemy_bullets[0].vel.length(), CFG.mine_burst_speed(1)):
		failures += 1
		print("SELFTEST_FAIL mine shard speed=%.1f" % enemy_bullets[0].vel.length())

	# 8) 补给箱武器语义（Unity GrantLevel/GrantLine/SwapToBest）
	var ws := WeaponSystem.new()
	if not ws.grant_level() or ws.active().level != CFG.START_PULSE_LEVEL + 1:
		failures += 1
		print("SELFTEST_FAIL grant_level basic")
	ws.grant_level()
	ws.grant_level()
	if ws.active().level != 5:
		failures += 1
		print("SELFTEST_FAIL grant_level max")
	if not ws.grant_level() or ws.active_id != "prism" or ws.line("prism").level != 1:
		failures += 1
		print("SELFTEST_FAIL grant_level unlock")
	if not ws.grant_line("swarm") or ws.active_id != "swarm" or ws.line("swarm").charge != 100.0:
		failures += 1
		print("SELFTEST_FAIL grant_line unlock")
	ws.line("pulse").charge = 90.0
	ws.line("prism").charge = 40.0
	if not ws.swap_to_best(30.0) or ws.active_id != "pulse" or ws.line("pulse").charge != 100.0:
		failures += 1
		print("SELFTEST_FAIL swap_to_best")
	var ws2 := WeaponSystem.new()
	ws2.active().charge = 10.0
	if ws2.swap_to_best(30.0) or ws2.active().charge != 55.0:
		failures += 1
		print("SELFTEST_FAIL swap_to_best solo")

	if failures == 0:
		print("SELFTEST_OK n=8")
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


## 追踪目标（Unity Director.NearestEnemy）：跳过未入屏敌机，Boss 未崩解时也算目标。
func _nearest_target(pos: Vector2):
	var best = null
	var bd := INF
	for e: Enemy in enemies:
		if e.entry_delay > 0.0:
			continue
		var d := pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = e
	if boss != null and not boss.dying:
		var d := pos.distance_squared_to(boss.pos)
		if d < bd:
			best = boss
	return best


func _process(delta: float) -> void:
	if _shot_mode != "" and not _shot_taken:
		_shot_t += delta
		var wait := 3.6 if (_shot_mode == "play" or _shot_mode.begins_with("boss")) else 1.6
		if _shot_mode == "bossdeploy":
			wait = 0.15
		elif _shot_mode == "hurt":
			wait = 1.2
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
		if _shot_mode == "hurt" and _shot_t > wait - 0.3:
			hurt_flash = 0.7
			shield_flash = 0.6
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
	# 二次确认窗口倒计时（暂停时也走真实时间）
	if confirm_t > 0.0:
		confirm_t = maxf(0.0, confirm_t - delta)
		if confirm_t <= 0.0:
			confirm_action = ""
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
	# 手感层：hitstop 冻结、slowmo 拖慢；只作用于世界更新，UI/震屏仍走真实时间
	var dt := delta
	if hitstop > 0.0:
		hitstop = maxf(0.0, hitstop - delta)
		dt = 0.0
	elif slowmo_t > 0.0:
		slowmo_t = maxf(0.0, slowmo_t - delta)
		dt = delta * slowmo_scale
		if slowmo_t <= 0.0:
			slowmo_scale = 1.0
	player_invuln = maxf(0.0, player_invuln - dt)
	_update_skills(dt)
	_update_economy(dt)
	_update_player(dt)
	_update_player_fire(dt)
	_update_enemies(dt)
	_update_boss(dt)
	_update_drones(dt)
	_update_crates(dt)
	_update_bullets(dt)
	_update_beams(dt)
	_update_motes(dt)
	# Boss 击破后的 4.4s 结算缓冲：打捞箱落地、残弹飞完，再开突破三选一
	if clear_hold > 0.0:
		clear_hold -= dt
		if clear_hold <= 0.0 and not game_over and not upgrade_pending:
			_open_upgrade_draft()
	waves.tick(dt)
	collisions.resolve()
	queue_redraw()


func _add_shake(amount: float, duration := 0.24) -> void:
	if not opt_shake:
		return
	shake = maxf(shake, amount)
	shake_t = maxf(shake_t, duration)


func _shake_offset() -> Vector2:
	if shake_t <= 0.0 or shake <= 0.0:
		return Vector2.ZERO
	var k := shake * clampf(shake_t / 0.24, 0.0, 1.0)
	return Vector2(randf_range(-k, k), randf_range(-k, k))


## 打击停顿：把世界冻结 t 秒（关键命中/Boss 破防/星爆）。
func _feel_freeze(t: float) -> void:
	hitstop = maxf(hitstop, t)


## 慢镜：以 scale 倍速拖世界 dur 秒（受创/星爆/Boss 崩解）。
func _feel_slow(scale: float, dur: float) -> void:
	slowmo_scale = scale
	slowmo_t = maxf(slowmo_t, dur)


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
	reflect_t = maxf(0.0, reflect_t - delta)
	swap_idle += delta
	# 星爆自然回充
	_gain_nova(CFG.NOVA_REGEN_PER_SECOND * delta)
	# 反射护盾：吸收 50px 内敌弹，每颗 +0.6×0.42 星爆（Unity Reflect field）
	if reflect_t > 0.0:
		for i in range(enemy_bullets.size() - 1, -1, -1):
			var eb: Bullet = enemy_bullets[i]
			if eb.pos.distance_to(player_pos) < 50.0 + eb.radius:
				enemy_bullets.remove_at(i)
				_gain_nova(CFG.NOVA_ON_POINT_DEFENSE * 0.42)
				if fx != null:
					fx.hit(eb.pos, Color.html("#6FA8FF"))


func _update_economy(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
			multiplier = 1


func _reset_upgrades() -> void:
	upgrade_flow.reset()


func _gain_nova(amount: float) -> void:
	# 超频期间不充能（Unity AddNova: blocked during overdrive）
	if overdrive > 0.0:
		return
	var mul := float(upgrades.get("nova_gain", 1.0))
	# 失谐 ×0.45；共鸣每层 +6%（Unity AddNova）
	if weapons.active().detuned:
		mul *= CFG.DETUNED_NOVA_MUL
	else:
		mul *= 1.0 + weapons.resonance * CFG.RESONANCE_PER_STACK_CHARGE
	mul *= float(CFG.DIFFICULTY[difficulty]["nova"])
	nova = minf(100.0, nova + amount * mul)


## 受创充能：不受失谐/共鸣/难度修正（Unity AddNovaRaw）
func _gain_nova_raw(amount: float) -> void:
	if overdrive > 0.0:
		return
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


func _open_upgrade_draft() -> void:
	upgrade_flow.open_draft()


func _choose_upgrade(index: int) -> void:
	upgrade_flow.choose(index)


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
	# 无按键时用最近移动方向（Unity _lastMove），触屏拖拽也能冲刺
	if dir.length_squared() > 0.0:
		dash_dir = dir.normalized()
	elif absf(player_last_dir) > 0.05:
		dash_dir = Vector2(player_last_dir, -0.3).normalized()
	else:
		dash_dir = Vector2(0, -1)
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
	_feel_freeze(CFG.FREEZE_NOVA)
	_feel_slow(CFG.SLOW_NOVA_SCALE, CFG.SLOW_NOVA_DUR)
	# 清屏敌弹并造成伤害
	var cleared := enemy_bullets.size()
	score += cleared * CFG.NOVA_SCORE_PER_CLEARED_BULLET
	enemy_bullets.clear()
	for i in range(enemies.size() - 1, -1, -1):
		var e: Enemy = enemies[i]
		e.hp -= CFG.NOVA_ENEMY_DAMAGE
		e.flash = 0.12
		if e.hp <= 0.0:
			collisions.kill_enemy(i, CFG.DIFFICULTY[difficulty])
	# Boss 星爆伤害：6% 最大血量 + 30 固定（Unity NovaBlast）
	if boss != null and boss.entered and not boss.dying:
		var boss_dmg := roundf(boss.max_hp * CFG.NOVA_BOSS_DAMAGE_FRAC) + CFG.NOVA_BOSS_DAMAGE_FLAT
		boss.take_damage(boss_dmg)
		boss.damage_flash()


## 星区击杀进度 0..1，HUD 进度条使用。
func zone_progress() -> float:
	return waves.progress()


func _player_pos() -> Vector2:
	return player_pos


func _enemy_spawn_bullet(pos: Vector2, vel: Vector2, color: Color, radius: float,
		kind: String, life: float, extra: Dictionary = {}) -> void:
	if enemy_bullets.size() >= CFG.MAX_ENEMY_BULLETS:
		return
	var b := Bullet.new(pos, vel, radius, 1.0, life, false, color, kind)
	# 默认值对齐 Unity Projectile：引信/分裂/波动/追踪全部由调用方显式给定
	if kind == "mine":
		b.fuse = float(extra.get("fuse", randf_range(1.8, 2.4)))
		b.split_on_expire = int(extra.get("split", CFG.MINE_BURST_COUNT))
	elif extra.has("fuse"):
		# 挥发词缀的等离子雷（Unity VolatileBlast）：life 1.2、引信 0.5、炸 6 发
		b.fuse = float(extra["fuse"])
		b.split_on_expire = int(extra.get("split", CFG.VOLATILE_SPLIT))
	b.wave = float(extra.get("wave", 0.0))
	if bool(extra.get("homing", false)) or kind == "homing" or kind == "seeker":
		b.homing = true
		b.homing_time = float(extra.get("homing_time", 2.6))
		b.homing_delay = float(extra.get("homing_delay", 0.0))
		b.turn_rate = float(extra.get("turn_rate", 1.9))
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
	var boss_index: int = 5 if CFG.is_final_zone(int(zone)) else (int(zone) - 1) % 6
	boss.setup(boss_index, zone, waves.density_tier(), CFG.DIFFICULTY[difficulty])
	if CFG.is_final_zone(int(zone)):
		# 终局：裁决者额外 20% 血量，作为整局的收束
		boss.max_hp *= 1.2
		boss.hp = boss.max_hp
	boss.spawn_bullet = _enemy_spawn_bullet
	boss.spawn_child = waves.spawn_child
	boss.player_pos_fn = _player_pos
	boss.spawn_beam = _boss_spawn_beam
	boss.fx_impact = _boss_fx_impact
	boss.sfx_fn = _boss_sfx
	boss.shake_fn = _boss_shake
	boss.on_phase_change = _on_boss_phase
	boss.on_desperate = _on_boss_desperate
	boss_pending = true


func _boss_spawn_beam(angle: float, warn: float, active: float, width_px: float, sweep: float) -> void:
	var bm := Beam.new()
	bm.angle = angle
	bm.warn = warn
	bm.active = active
	bm.width = width_px
	bm.sweep = sweep
	beams.append(bm)


func _boss_fx_impact(pos: Vector2, col: Color, size_px: float, life: float) -> void:
	if fx != null:
		fx.impact(pos, col, size_px, life)


## Unity 音效映射：PlayWarn/PlayHit→hit，PlaySwitch→pick，PlayExplode→boom。
func _boss_sfx(sname: String) -> void:
	match sname:
		"boom":
			sfx.play_boom()
		"pick":
			sfx.play_pick()
		_:
			sfx.play_hit()


func _boss_shake(amount_px: float, dur: float) -> void:
	_add_shake(amount_px, dur)


func _on_boss_phase(_phase: int) -> void:
	# Unity：阶段切换给玩家 0.75s 无敌 + hitstop 0.06
	player_invuln = maxf(player_invuln, CFG.INVULN_ON_BOSS_PHASE)
	_feel_freeze(CFG.FREEZE_PHASE)


func _on_boss_desperate() -> void:
	_feel_freeze(CFG.FREEZE_DESPERATE)
	if fx != null:
		fx.float_text(boss.pos + Vector2(0, -boss.size), "核心临界",
			Color.html("#FF6B7A"), 16)


func _update_boss(delta: float) -> void:
	if boss == null:
		return
	boss.tick(delta, player_pos)
	if boss.entered:
		boss_pending = false
	if boss.dying and not beams.is_empty():
		beams.clear()  # Unity BossLaser.ClearAll：崩解即收光束
	if not boss.dying and player_invuln <= 0.0:
		var dx := (player_pos.x - boss.pos.x) / boss.contact_rx()
		var dy := (player_pos.y - boss.pos.y) / boss.contact_ry()
		if dx * dx + dy * dy <= 1.0:
			collisions.player_hit()
	if boss.dying and boss.die_t > 1.2:
		score += int(roundf(3000.0 * float(CFG.DIFFICULTY[difficulty]["scoreMul"]) * multiplier))
		# 过关结算：基础 + 星区 + 无伤奖励（对齐 web Clear* 常量）
		var diff: Dictionary = CFG.DIFFICULTY[difficulty]
		var bonus := int(roundf((CFG.CLEAR_BASE_SCORE + CFG.CLEAR_BASE_PER_SECTOR * zone)
			* float(diff["scoreMul"])))
		if player_lives >= CFG.START_LIVES:
			bonus += int(CFG.CLEAR_NO_HIT_BASE + CFG.CLEAR_NO_HIT_PER_SECTOR * zone)
		bonus += int(CFG.SECTOR_COMPENSATION_PER_ZONE * zone)
		score += bonus
		if fx != null:
			fx.float_text(boss.pos + Vector2(0, -40), "过关 +%d" % bonus, Color(1.0, 0.94, 0.72), 16)
		sfx.play_boom()
		if fx != null:
			fx.explode(boss.pos, Color.html("#FFB3D9"), boss.size * 1.6, true)
			fx.nova(boss.pos)
		_add_shake(17.28, 0.55)
		_feel_freeze(CFG.FREEZE_BOSS_DIE)
		_feel_slow(CFG.SLOW_BOSS_DIE_SCALE, CFG.SLOW_BOSS_DIE_DUR)
		boss = null
		boss_cleared = true
		waves.zone_kills = 0
		enemy_bullets.clear()
		if CFG.is_final_zone(int(zone)):
			# 第 10 区终局击破 → 巡航完成（不再无限循环）
			won = true
			game_over = true
			game_over_time = 0.0
			_save_best()
			sfx.play_nova()
		else:
			# Unity OnBossDefeated：铺通关必掉箱 + 4.4s 幕间，幕间结束才开三选一
			_deploy_sector_salvage()
			clear_hold = CFG.SECTOR_CLEAR_SECONDS


## Boss 光束推进（Unity BossLaser.Update）：warn 期冻结角度，active 期才扫射/判定。
func _update_beams(delta: float) -> void:
	if boss == null:
		if not beams.is_empty():
			beams.clear()
		return
	var length := view_size.y * CFG.BEAM_LENGTH_MUL
	for i in range(beams.size() - 1, -1, -1):
		var bm: Beam = beams[i]
		bm.t += delta
		if bm.t > bm.warn and bm.t < bm.warn + bm.active:
			bm.angle += bm.sweep * delta
		if bm.t > bm.warn + bm.active + CFG.BEAM_TAIL:
			beams.remove_at(i)
			continue
		if bm.t < bm.warn or bm.t > bm.warn + bm.active:
			continue
		if player_invuln > 0.0 or dash_t > 0.0:
			continue  # 无敌帧与冲刺可穿光束
		var d := CFG.point_ray_distance(player_pos, boss.pos, bm.angle, length)
		if d < bm.width * 0.5 + CFG.PLAYER_HIT_R:
			collisions.player_hit()


# ---------------------------------------------------------------- 僚机

func _add_drone() -> void:
	if drones.size() >= CFG.MAX_DRONES:
		return
	var in_use: Array = []
	for d in drones:
		in_use.append(d["kind"])
	var kind := CFG.pick_drone_kind(in_use, randi())
	var slots := _drone_slots_for(drones.size() + 1)
	var slot: Vector2 = slots[drones.size()] if drones.size() < slots.size() else Vector2.ZERO
	drones.append({
		"kind": kind,
		"timer": randf_range(0.15, 0.5),
		"pos": player_pos + slot,
	})


func _drone_slots() -> Array:
	return _drone_slots_for(drones.size())


func _drone_slots_for(count: int) -> Array:
	match count:
		1:
			return CFG.DRONE_SLOTS_1
		2:
			return CFG.DRONE_SLOTS_2
		3:
			return CFG.DRONE_SLOTS_3
	return []


## 僚机（Unity DroneShip）：挂点阻尼跟随（不绕圈），弹种跟着主机当前武器线走，
## 横向偏移换算 lean 侧向分量让侧翼弹道自然张开。
func _update_drones(delta: float) -> void:
	var slots := _drone_slots()
	var line_id := String(weapons.active_id)
	var tint := Color.html(String(CFG.WEAPON_LINES[line_id]["tint"]))
	var dmul := weapons.damage_mul()
	for i in range(drones.size()):
		var d: Dictionary = drones[i]
		var slot: Vector2 = slots[i] if i < slots.size() else Vector2.ZERO
		var want := player_pos + slot
		want.x = clampf(want.x, 18.0, view_size.x - 18.0)
		var cur := Vector2(d["pos"])
		cur = cur.lerp(want, 1.0 - exp(-13.0 * delta))
		d["pos"] = cur
		d["timer"] = float(d["timer"]) - delta * float(upgrades.get("drone_rate", 1.0))
		if float(d["timer"]) > 0.0:
			continue
		var kind := String(d["kind"])
		var lean := clampf((cur.x - player_pos.x) / 55.0, -0.18, 0.18)
		if kind == "aegis":
			d["timer"] = CFG.AEGIS_PD_INTERVAL
			var cleared := 0
			for j in range(enemy_bullets.size() - 1, -1, -1):
				if cleared >= CFG.AEGIS_PD_CLEAR_COUNT:
					break
				var eb: Bullet = enemy_bullets[j]
				if eb.pos.distance_to(cur) <= CFG.AEGIS_PD_RADIUS:
					enemy_bullets.remove_at(j)
					_gain_nova(CFG.NOVA_ON_POINT_DEFENSE)
					cleared += 1
			if cleared > 0 and fx != null:
				fx.impact(cur, Color(tint.r, tint.g, tint.b, 0.5), CFG.AEGIS_PD_RADIUS * 2.0, 0.22)
			continue
		if line_id == "swarm" or kind == "swarm":
			d["timer"] = 0.86 if kind == "gunner" else 1.02
			var n := 2 if kind == "lance" else 1
			for k in range(n):
				var vx := lean * 520.0 + (k - (n - 1) * 0.5) * 140.0
				var sb := Bullet.new(cur + Vector2(0, -5), Vector2(vx, -700.0),
					4.0, maxf(1.0, roundf(2.0 * dmul)), 2.1, true, tint, "micro")
				sb.homing = true
				sb.homing_time = 1.6
				sb.turn_rate = 4.4
				sb.homing_delay = 0.12
				sb.homing_target = _nearest_target(cur)
				player_bullets.append(sb)
			continue
		if line_id == "prism":
			d["timer"] = 0.82 if kind == "lance" else 1.05
			var pb := Bullet.new(cur + Vector2(0, -9), Vector2(lean * 150.0, -600.0),
				6.0, maxf(1.0, roundf((4.0 if kind == "lance" else 3.0) * dmul)),
				2.4, true, tint, "beam")
			pb.pierce_left = 2 if kind == "lance" else 1
			player_bullets.append(pb)
			continue
		d["timer"] = 0.34 if kind == "gunner" else 0.5
		player_bullets.append(Bullet.new(cur + Vector2(0, -7), Vector2(lean * 260.0, -1180.0),
			4.0, maxf(1.0, roundf(dmul)), 1.9, true, tint, "drone"))
		if kind == "lance":
			player_bullets.append(Bullet.new(cur + Vector2(-5, -4), Vector2(lean * 320.0 - 60.0, -1140.0),
				4.0, maxf(1.0, roundf(dmul)), 1.9, true, tint, "drone"))


# ---------------------------------------------------------------- 补给箱

func _update_crates(delta: float) -> void:
	# 周期补给只在波次阶段走（Unity：仅 Waves 状态）；首箱 20s，之后固定 19s
	if boss == null and not boss_cleared and not waves.clearing and boss_warn <= 0.0:
		crate_timer -= delta * float(upgrades.get("crate_rate", 1.0))
		if crate_timer <= 0.0:
			crate_timer = CFG.SUPPLY_INTERVAL_MIN
			_collect_supply()
	for i in range(crates.size() - 1, -1, -1):
		var c: Crate = crates[i]
		c.tick(delta, player_pos)
		if not c.dead and c.pos.distance_to(player_pos) < CFG.CRATE_PICKUP_R:
			_apply_crate(c.kind)
			c.dead = true
		if c.dead:
			crates.remove_at(i)


## 周期补给（Unity Director.CollectSupply）：成长优先 + 换线箱 + 双保底计数。
func _collect_supply() -> void:
	var missing := not weapons.line("prism").unlocked or not weapons.line("swarm").unlocked
	var kind := "weapon"
	if weapons.active().level < 3:
		kind = "weapon"
	elif missing and (pity_weapon >= CFG.PITY_THRESHOLD or randf() < 0.35):
		if not weapons.line("prism").unlocked:
			kind = "prism"
		elif not weapons.line("swarm").unlocked:
			kind = "swarm"
		else:
			kind = "prism" if randf() < 0.5 else "swarm"
	elif weapons.unlocked_count() >= 2 and swap_idle > CFG.SWAP_IDLE_FOR_SWAP_CRATE \
			and randf() < CFG.SWAP_CRATE_CHANCE:
		kind = "swap"
	elif drones.size() < CFG.MAX_DRONES and pity_drone >= CFG.PITY_THRESHOLD:
		kind = "drone"
	elif player_shields < CFG.MAX_SHIELDS and randf() < 0.4:
		kind = "shield"
	elif drones.size() < CFG.MAX_DRONES and randf() < 0.35:
		kind = "drone"
	elif reflect_t <= 0.0 and randf() < 0.25:
		kind = "reflect"
	elif player_lives <= 2 and randf() < 0.3:
		kind = "life"
	else:
		var idx := CFG.weighted_pick([2, 2, 1, 1, 1, 1, 1], randf())
		kind = String(["weapon", "weapon", "shield", "swap", "prism", "swarm", "gems"][idx])
	# 保底计数（Unity：抽到即清零，没抽到且仍缺才累加）
	if kind == "prism" or kind == "swarm":
		pity_weapon = 0
	elif missing:
		pity_weapon += 1
	if kind == "drone":
		pity_drone = 0
	else:
		pity_drone += 1
	if not missing:
		pity_weapon = 0
	if kind == "gems":
		for i in range(4):
			_spawn_crate_at(Vector2(view_size.x * 0.5 + randf_range(-48.6, 48.6),
				-21.6 - i * 10.8), "gem")
	else:
		_spawn_crate_at(Vector2(view_size.x * randf_range(0.38, 0.62), -32.4), kind)


## 精英掉落类型（Unity Director.PickUpgradeType）：保底→武器→护盾→僚机→缺线→杂项。
func _pick_upgrade_type() -> String:
	var missing := not weapons.line("prism").unlocked or not weapons.line("swarm").unlocked
	if missing and pity_weapon >= CFG.PITY_THRESHOLD:
		return "prism" if not weapons.line("prism").unlocked else "swarm"
	if drones.size() < CFG.MAX_DRONES and pity_drone >= CFG.PITY_THRESHOLD:
		return "drone"
	if weapons.active().level < 5 and randf() < 0.4:
		return "weapon"
	if player_shields < CFG.MAX_SHIELDS and randf() < 0.45:
		return "shield"
	if drones.size() < CFG.MAX_DRONES and randf() < 0.55:
		return "drone"
	if not weapons.line("prism").unlocked and randf() < 0.4:
		return "prism"
	if not weapons.line("swarm").unlocked and randf() < 0.4:
		return "swarm"
	if randf() < 0.45:
		return "prism" if randf() < 0.5 else "reflect"
	var pool := ["weapon", "prism", "shield", "life"]
	return String(pool[randi() % pool.size()])


## 击杀掉落（Unity Director.RollDrop）：精英必掉成长箱+3 宝石；陨石 80% 撒 2 宝石；
## 其余按 dropChance 进两张权重表（未满级 / 已满级）。
func _roll_drop(e: Enemy, at: Vector2) -> void:
	if e.elite:
		_spawn_crate_at(at, _pick_upgrade_type())
		for i in range(3):
			_spawn_crate_at(at + Vector2(randf_range(-20.0, 20.0), randf_range(-10.0, 10.0)), "gem")
		return
	if e.kind == "rock":
		if randf() < 0.8:
			for i in range(2):
				_spawn_crate_at(at + Vector2(randf_range(-10.0, 10.0), randf_range(-8.0, 8.0)), "gem")
		return
	if randf() > float(e.def.get("drop", 0.0)):
		return
	var kind := "gem"
	if weapons.active().level < 5:
		var idx := CFG.weighted_pick([38, 17, 13, 6, 6, 5, 4, 11], randf())
		kind = String(["weapon", "shield", "drone", "prism", "swarm", "reflect", "life", "gem"][idx])
	else:
		var idx := CFG.weighted_pick([22, 20, 9, 9, 7, 4, 20, 9], randf())
		kind = String(["shield", "drone", "prism", "swarm", "reflect", "life", "weapon", "gem"][idx])
	_spawn_crate_at(at, kind)
	if kind == "gem":
		_spawn_crate_at(at + Vector2(12.0, 0.0), "gem")


func _spawn_crate_at(pos: Vector2, kind: String) -> void:
	var c := Crate.new()
	c.setup(pos, kind)
	crates.append(c)


## 剧本补给（Unity SpawnSupplyNow）：投在玩家左右 ±140、上方 330，夹在 16%~52% 屏高。
func _spawn_supply_now(kind: String) -> void:
	var px := clampf(player_pos.x + randf_range(-140.0, 140.0), 54.0, view_size.x - 54.0)
	var py := clampf(player_pos.y - 330.0, view_size.y * 0.16, view_size.y * 0.52)
	_spawn_crate_at(Vector2(px, py), kind)


## 拾取后的保底复位（Unity Director.OnCrateCollected）。
func _on_crate_collected(kind: String) -> void:
	if kind == "prism" or kind == "swarm" or kind == "weapon":
		pity_weapon = 0
	if kind == "drone":
		pity_drone = 0


## 通关必掉（Unity DeploySectorSalvage）：升级+缺线+护盾/反射+僚机/命+换线+5 宝石，
## 摆在玩家上方 240px 的拱形里，幕间 4.4s 留给玩家收箱。
func _deploy_sector_salvage() -> void:
	var loot: Array = ["weapon"]
	loot.append("prism" if not weapons.line("prism").unlocked
		else ("swarm" if not weapons.line("swarm").unlocked else "weapon"))
	loot.append("reflect" if player_shields >= 2 else "shield")
	loot.append("drone" if drones.size() < CFG.MAX_DRONES else "life")
	if weapons.unlocked_count() >= 2:
		loot.append("swap")
	if player_lives < 3:
		loot.append("life")
	var px := player_pos.x
	var py := clampf(player_pos.y - 240.0, view_size.y * 0.28, view_size.y * 0.72)
	var n := loot.size()
	var gap := minf(56.0, (view_size.x - 96.0) / maxf(1.0, float(n - 1)))
	var mid := (n - 1) * 0.5
	for i in range(n):
		var x := clampf(px + (i - mid) * gap, 46.0, view_size.x - 46.0)
		_spawn_crate_at(Vector2(x, py - absf(i - mid) * 14.0), String(loot[i]))
	for i in range(5):
		var gx := clampf(px + randf_range(-90.0, 90.0), 30.0, view_size.x - 30.0)
		_spawn_crate_at(Vector2(gx, py + randf_range(-20.0, 40.0)), "gem")


func _apply_crate(kind: String) -> void:
	sfx.play_pick()
	_on_crate_collected(kind)
	var label := "补给"
	var col := Color.html("#FFC554")
	match kind:
		"gem":
			score += int(roundf(25.0 * multiplier))
			_gain_nova(CFG.NOVA_ON_GEM)
			if fx != null:
				fx.pickup(player_pos, Color.html("#FFE9B0"), "+%d" % int(roundf(25.0 * multiplier)))
			return
		"weapon":
			if not weapons.grant_level():
				score += CFG.CRATE_FULL_WEAPON_SCORE
			label = "武器强化 LV.%d" % weapons.active().level
			col = Color.html("#FFD27A")
		"shield":
			if player_shields < CFG.MAX_SHIELDS:
				player_shields += 1
				shield_flash = 0.6
				label = "护盾 %d/%d" % [player_shields, CFG.MAX_SHIELDS]
			else:
				score += CFG.CRATE_FULL_SHIELD_SCORE
				label = "+%d" % CFG.CRATE_FULL_SHIELD_SCORE
			col = Color.html("#9B8CFF")
		"drone":
			if drones.size() < CFG.MAX_DRONES:
				_add_drone()
				label = "僚机归队"
			else:
				score += CFG.CRATE_FULL_DRONE_SCORE
				label = "+%d" % CFG.CRATE_FULL_DRONE_SCORE
			col = Color.html("#8FA4C9")
		"prism":
			if not weapons.grant_line("prism"):
				score += CFG.CRATE_FULL_LINE_SCORE
			label = "棱镜线解锁/升级"
			col = Color.html("#FF6F91")
		"swarm":
			if not weapons.grant_line("swarm"):
				score += CFG.CRATE_FULL_LINE_SCORE
			label = "蜂群线解锁/升级"
			col = Color.html("#FFC24B")
		"reflect":
			reflect_t = CFG.REFLECT_DURATION
			label = "反射力场 8s"
			col = Color.html("#FFD27A")
		"life":
			if player_lives < int(upgrades.get("max_hull", CFG.START_LIVES)):
				player_lives += 1
				label = "舰体 +1"
			else:
				score += CFG.CRATE_FULL_LIFE_SCORE
				label = "+%d" % CFG.CRATE_FULL_LIFE_SCORE
			col = Color.html("#FF6F91")
		"swap":
			if weapons.swap_to_best(30.0):
				swap_idle = 0.0
				label = "武器切换 · %s" % CFG.weapon_name(weapons.active_id, weapons.active().level)
			else:
				label = "三线回充"
			col = Color.html("#69F5DC")
	if fx != null:
		fx.pickup(player_pos, col, label)


func _update_bullets(delta: float) -> void:
	_advance_bullets(player_bullets, delta)
	_advance_bullets(enemy_bullets, delta)


func _advance_bullets(arr: Array, delta: float) -> void:
	for i in range(arr.size() - 1, -1, -1):
		var b: Bullet = arr[i]
		b.prev = b.pos
		b.age += delta
		# 引信优先于寿命结算（Unity Projectile.Tick）；按弹种分流爆炸
		if b.fuse > 0.0:
			b.fuse -= delta
			if b.fuse <= 0.0:
				if b.kind == "plasma":
					_burst_plasma(b)
				else:
					_burst_mine(b)
				arr.remove_at(i)
				continue
		b.life -= delta
		if b.life <= 0.0:
			if not b.friendly:
				if b.kind == "mine":
					_burst_mine(b)
				elif b.kind == "plasma":
					_burst_plasma(b)
			arr.remove_at(i)
			continue
		if b.kind == "mine":
			# 水雷速度指数衰减到停住；引信剩 0.9s 时一次性提示闪光
			b.vel *= exp(-CFG.MINE_DRAG * delta)
			if not b.armed and b.fuse > 0.0 and b.fuse < CFG.MINE_ARMED_FLASH:
				b.armed = true
				if fx != null:
					fx.impact(b.pos, Color(1, 0.82, 0.35, 0.7), 33.48, 0.24)
		elif b.wave != 0.0:
			# 波动弹允许负振幅（Unity Wave!=0）
			var spd := b.vel.length()
			var ang := b.vel.angle() + sin(b.age * CFG.WAVE_PHASE_RATE + b.seed) * b.wave * delta
			b.vel = Vector2(cos(ang), sin(ang)) * spd
		# 追踪：有目标才消耗追踪时长；友军弹缓存目标，失效才重新索敌
		if b.homing and b.homing_time > 0.0 and b.age >= b.homing_delay:
			var target_pos := Vector2.ZERO
			var has_target := false
			if b.friendly:
				var t = b.homing_target
				var alive := false
				if t != null:
					if t is Enemy:
						alive = enemies.has(t)
					elif t is Boss:
						alive = boss == t and not boss.dying
				if not alive:
					t = _nearest_target(b.pos)
					b.homing_target = t
				if t != null:
					target_pos = t.pos
					has_target = true
			else:
				target_pos = player_pos
				has_target = true
			if has_target:
				b.homing_time -= delta
				var spd := b.vel.length()
				var cur_ang := b.vel.angle()
				var want_ang := (target_pos - b.pos).angle()
				var diff_ang := wrapf(want_ang - cur_ang, -PI, PI)
				var max_turn := b.turn_rate * delta
				var new_ang := cur_ang + clampf(diff_ang, -max_turn, max_turn)
				b.vel = Vector2(cos(new_ang), sin(new_ang)) * spd
		b.pos += b.vel * delta
		# 出界按 Unity 世界单位换算：x±1world=54px，y −0.5/+0.5world
		if b.pos.x < -54.0 or b.pos.x > view_size.x + 54.0 \
				or b.pos.y < -48.6 or b.pos.y > view_size.y + 59.4:
			arr.remove_at(i)


func _burst_mine(b: Bullet) -> void:
	if b.friendly:
		return
	var n := b.split_on_expire if b.split_on_expire > 0 else CFG.MINE_BURST_COUNT
	var speed := CFG.mine_burst_speed(zone)
	for i in range(n):
		var a := TAU * float(i) / n + b.seed * 0.3
		enemy_bullets.append(Bullet.new(b.pos, Vector2(cos(a), sin(a)) * speed,
			CFG.MINE_SHARD_RADIUS, 1.0, CFG.MINE_SHARD_LIFE, false, Color(1, 0.85, 0.35), "shard"))
	if fx != null:
		fx.impact(b.pos, Color(1, 0.82, 0.35, 0.85), 51.3, 0.3)
	sfx.play_hit()


func _burst_plasma(b: Bullet) -> void:
	if b.friendly:
		return
	var n := b.split_on_expire if b.split_on_expire > 0 else CFG.PLASMA_BURST_COUNT
	for i in range(n):
		var a := TAU * float(i) / n + b.seed
		enemy_bullets.append(Bullet.new(b.pos, Vector2(cos(a), sin(a)) * CFG.PLASMA_BURST_SPEED,
			CFG.PLASMA_SHARD_RADIUS, 1.0, CFG.PLASMA_SHARD_LIFE, false, Color(1, 0.6, 0.3), "orb"))
	if fx != null:
		fx.impact(b.pos, Color(0.61, 0.55, 1, 0.8), 59.4, 0.32)


## 碰撞与受击结算已拆分到 CollisionSystem。


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
			if settings_open:
				if event.keycode == KEY_ESCAPE:
					settings_open = false
				return
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
		"settings":
			settings_open = true
		"settings_back":
			settings_open = false
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
			confirm_action = ""
			if music != null:
				music.set_paused(false)
		"restart", "retry":
			# 暂停中「重新出击」会丢本局进度，需二次确认；结算页重开无损失直接执行
			if paused and action == "restart" and confirm_action != "restart":
				confirm_action = "restart"
				confirm_t = 2.5
			else:
				confirm_action = ""
				_start_run()
		"menu":
			if paused and confirm_action != "menu":
				confirm_action = "menu"
				confirm_t = 2.5
			else:
				confirm_action = ""
				_to_menu()
		"opt_music":
			opt_music = not opt_music
			_apply_opts()
			# 菜单里不播战斗 BGM；暂停中切换只记开关不 resume（修 A2）
			if opt_music and music != null and not in_menu:
				music.play_zone(int(zone))
				music.set_paused(paused)
			_save_opts()
		"opt_sfx":
			opt_sfx = not opt_sfx
			_apply_opts()
			_save_opts()
		"opt_shake":
			opt_shake = not opt_shake
			_save_opts()
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
	settings_open = false
	paused = false
	game_over = false
	won = false
	score = 0
	display_score = 0.0
	display_boss_hp = 1.0
	graze = 0
	combo = 0
	multiplier = 1
	zone = 1
	waves.reset()
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
	score = 0
	display_score = 0.0
	display_boss_hp = 1.0
	graze = 0
	game_over = false
	won = false
	paused = false
	game_over_time = 0.0
	player_bullets.clear()
	enemy_bullets.clear()
	enemies.clear()
	zone = 1
	waves.reset()
	total_kills = 0
	pointer_active = false
	weapons = WeaponSystem.new()
	weapons.spawn = _player_spawn_bullet
	player_shields = CFG.START_SHIELDS
	nova = 0.0
	overdrive = 0.0
	dash_t = 0.0
	dash_cd = 0.0
	reflect_t = 0.0
	swap_idle = 0.0
	combo = 0
	combo_timer = 0.0
	multiplier = 1
	boss = null
	boss_pending = false
	boss_cleared = false
	boss_warn = 0.0
	beams.clear()
	clear_hold = 0.0
	crates.clear()
	crate_timer = CFG.SUPPLY_INTERVAL
	pity_weapon = 0
	pity_drone = 0
	drones.clear()
	if music != null:
		music.play_zone(1)
		music.set_paused(false)


func _html_color(spec: String) -> Color:
	if _color_cache.has(spec):
		return _color_cache[spec]
	var c := Color.html(spec)
	_color_cache[spec] = c
	return c


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
		_draw_beams()
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
	_draw_ship(ring, boss.pos, boss.size * grow * 1.08, -boss.spin,
		Color(1, 1, 1, (0.62 if boss.phase >= 1 else 0.40) * alpha))
	if boss.flash > 0.0:
		_draw_ship(art + "_mask", boss.pos, boss.size * grow, 0.0,
			Color(1, 1, 1, clampf(boss.flash / 0.08, 0.0, 1.0) * 0.85 * alpha))


## 光束渲染（Unity BossLaser）：预告细线+炮口呼吸 → 外层光晕+白芯，包络进 12/s 退 8/s。
func _draw_beams() -> void:
	if boss == null:
		return
	var length := view_size.y * CFG.BEAM_LENGTH_MUL
	var tint := _html_color(CFG.BEAM_COLOR)
	for bm in beams:
		var active: bool = bm.t >= bm.warn and bm.t <= bm.warn + bm.active
		var k := clampf(bm.t / maxf(0.01, bm.warn), 0.0, 1.0)
		draw_set_transform(boss.pos, bm.angle, Vector2.ONE)
		if not active:
			draw_rect(Rect2(0, -1.1, length, 2.2), Color(1, 0.55, 0.62, 0.14 + k * 0.35))
			var pulse := 1.0 + sin(bm.t * 22.0) * 0.18
			draw_circle(Vector2.ZERO, (34.0 + k * 20.0) * 0.5 * pulse,
				Color(tint.r, tint.g, tint.b, 0.2 + k * 0.3))
		else:
			var env := clampf(minf((bm.t - bm.warn) * 12.0,
				(bm.warn + bm.active - bm.t) * 8.0), 0.0, 1.0)
			draw_rect(Rect2(0, -bm.width * 0.5, length, bm.width),
				Color(tint.r, tint.g, tint.b, env * 0.62))
			draw_rect(Rect2(0, -bm.width * 0.19, length, bm.width * 0.38),
				Color(1, 1, 1, env * 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_crates() -> void:
	for c in crates:
		var tex := _ship_tex("crate_" + c.kind)
		var side := 38.0 + sin(c.spin) * 2.0
		_draw_shadow(c.pos + Vector2(0, 7), 16.0, Color(0.10, 0.06, 0.16, 0.20))
		_blob(c.pos, 26.0, Color(1.0, 0.93, 0.72, 0.20), 5)
		if tex != null:
			# 宝石不旋转，其余箱体按 42°/s 自旋（Unity SupplyCrate）
			var rot: float = 0.0 if c.kind == "gem" else c.spin
			draw_set_transform(c.pos, rot, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-side * 0.5, -side * 0.5, side, side), false, Color.WHITE)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_rect(Rect2(c.pos - Vector2(13, 13), Vector2(26, 26)), Color(0.41, 0.96, 0.86, 0.8))
		draw_arc(c.pos, side * 0.72, c.spin * 0.4, c.spin * 0.4 + PI * 1.1, 20,
			Color(1, 1, 1, 0.30), 1.5, true)


func _draw_drones() -> void:
	# 美术映射对齐 Unity DroneShip：gunner→seeker 机体，lance→cannon 机体
	var art := {"gunner": "drone_seeker", "lance": "drone_cannon", "aegis": "drone_support", "swarm": "drone_swarm"}
	for i in range(drones.size()):
		var dp := Vector2(drones[i]["pos"])
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
			"lance", "beam":
				var half: Vector2 = dir * b.radius * 3.2
				draw_line(b.pos - half, b.pos + half, Color(1, 1, 1, 0.85), b.radius * 0.7, true)
				draw_line(b.pos - half * 0.8, b.pos + half * 0.8, col, b.radius * 1.5, true)
			"bolt", "micro", "drone":
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
	var tint := _html_color(String(CFG.WEAPON_LINES[String(weapons.active_id)]["tint"]))
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
		var base := _html_color(String(e.def.get("color", "#ff6f91")))
		var accent := _html_color(String(e.def.get("accent", "#ffffff")))
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
