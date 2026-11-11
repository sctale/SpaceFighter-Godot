class_name CollisionSystem
extends RefCounted

## 碰撞与击杀结算：玩家弹 vs 敌机/Boss、敌弹/机体 vs 玩家、击杀奖励与受击。
## 所有状态仍由 Main 持有，本模块只负责结算顺序。
## 对齐归档 Unity v0.21.14：相位标记不删弹、受击分级、反射免死、星爆命中充能。

const CFG := preload("res://scripts/game_config.gd")

var m  # Main


func _init(main_ref) -> void:
	m = main_ref


func resolve() -> void:
	var diff: Dictionary = CFG.DIFFICULTY[String(m.difficulty)]

	for bi in range(m.player_bullets.size() - 1, -1, -1):
		var b = m.player_bullets[bi]
		var consumed := false
		# Boss 判定：椭圆（size×1.02 / ×0.82），棱镜对巨构 +18%
		if m.boss != null and m.boss.entered and not m.boss.dying:
			var bdx: float = (b.pos.x - m.boss.pos.x) / (m.boss.hit_rx() + b.radius)
			var bdy: float = (b.pos.y - m.boss.pos.y) / (m.boss.hit_ry() + b.radius)
			if bdx * bdx + bdy * bdy <= 1.0:
				var bdmg: float = b.damage * float(m.upgrades.get("damage_mul", 1.0)) \
					* float(m.upgrades.get("break_mul", 1.0)) \
					* (CFG.PRISM_BOSS_BONUS if b.kind == "lance" else 1.0)
				if m.boss.take_damage(bdmg):
					m.sfx.play_hit()
					m._feel_freeze(CFG.FREEZE_HIT)
				m.boss.damage_flash()
				if m.fx != null:
					m.fx.hit(b.pos, m._html_color("#FFF0C2"))
				m.score += int(roundf(10.0 * float(diff["scoreMul"])))
				m._gain_nova(CFG.NOVA_ON_HIT_BOSS)
				if b.pierce_left > 0:
					b.pierce_left -= 1
				else:
					m.player_bullets.remove_at(bi)
					continue
		for ei in range(m.enemies.size() - 1, -1, -1):
			var e: Enemy = m.enemies[ei]
			if b.hit_enemies.has(e):
				continue
			var rr: float = e.hit_r + b.radius
			if _seg_point_d2(b.prev, b.pos, e.pos) <= rr * rr:
				e.hp -= b.damage * e.damage_taken_mul * float(m.upgrades.get("damage_mul", 1.0))
				e.flash = 0.08
				if m.fx != null:
					m.fx.hit(b.pos, Color(1.0, 0.92, 0.68))
				b.hit_enemies.append(e)
				m._gain_nova(CFG.NOVA_ON_HIT_ENEMY)
				if e.hp <= 0.0:
					kill_enemy(ei, diff)
				if b.pierce_left > 0:
					b.pierce_left -= 1
				else:
					consumed = true
					break
		if consumed:
			m.player_bullets.remove_at(bi)
	resolve_player_hazards()


## 玩家受击 / 擦弹判定：每帧独立结算，不能放进击杀回调。
## 对齐 web 版 collide()：先擦弹（命中半径之外），再命中，最后机体接触。
func resolve_player_hazards() -> void:
	# 命中中心：玩家位置下方 2px（Unity：pos - up×2，y-down 即 +2）
	var hit_center: Vector2 = m.player_pos + Vector2(0, 2.0)
	# 相位（冲刺期间）：标记 phased 而非删除（Unity：b.Phased=true，不 splice）
	if m.dash_t > 0.0:
		for i in range(m.enemy_bullets.size() - 1, -1, -1):
			var pb = m.enemy_bullets[i]
			if pb.phased:
				continue
			if pb.pos.distance_to(hit_center) <= CFG.PHASE_RADIUS + pb.radius:
				pb.phased = true
				m.score += CFG.PHASE_SCORE_PER_BULLET
				m._gain_nova(CFG.PHASE_NOVA_PER_BULLET)
				m._spawn_mote(pb.pos)
	if m.player_invuln > 0.0:
		return
	for i in range(m.enemy_bullets.size() - 1, -1, -1):
		var b = m.enemy_bullets[i]
		if b.phased:
			continue
		var d2 := _seg_point_d2(b.prev, b.pos, hit_center)
		var hit_r: float = CFG.PLAYER_HIT_R + b.radius
		var graze_r: float = CFG.PLAYER_GRAZE_R + b.radius
		if not b.grazed and d2 <= graze_r * graze_r and d2 > hit_r * hit_r:
			b.grazed = true
			m.graze += 1
			m._gain_nova(CFG.NOVA_ON_GRAZE)
			m._spawn_mote(b.pos)
		elif d2 <= hit_r * hit_r:
			m.enemy_bullets.remove_at(i)
			player_hit()
			return
	for en: Enemy in m.enemies:
		var rr: float = CFG.PLAYER_HIT_R + en.hit_r
		if hit_center.distance_squared_to(en.pos) <= rr * rr:
			player_hit()
			return


func kill_enemy(index: int, diff: Dictionary) -> void:
	var e: Enemy = m.enemies[index]
	m.score += int(roundf(e.score_value * float(diff["scoreMul"]) * m.multiplier))
	m._gain_nova(CFG.NOVA_ON_ELITE_KILL if e.elite else CFG.NOVA_ON_KILL)
	m._add_combo()
	m.total_kills += 1
	m.waves.zone_kills += 1
	# 超频击杀延长（Unity：0.11/0.26，封顶 OverdriveMax）
	if m.overdrive > 0.0:
		var ext := CFG.OVERDRIVE_ELITE_KILL_EXTEND if e.elite else CFG.OVERDRIVE_KILL_EXTEND
		m.overdrive = minf(CFG.OVERDRIVE_MAX, m.overdrive + ext)
	var at := e.pos
	var was_volatile := e.affix == "volatile"
	var was_splitter := e.kind == "splitter"
	m.enemies.remove_at(index)
	# 分裂体留下半血幼体；挥发机炸出一圈幼体
	if was_splitter:
		for s in [-1.0, 1.0]:
			m.waves.spawn_enemy("shardling", at + Vector2(s * 14.0, 0.0), false, "none",
				CFG.SPLITTER_CHILD_HP_FRAC)
	elif was_volatile:
		for i in range(CFG.VOLATILE_SPLIT):
			var a := TAU * float(i) / CFG.VOLATILE_SPLIT
			m.waves.spawn_enemy("shardling", at + Vector2(cos(a), sin(a)) * 18.0)
	if e.elite:
		m.sfx.play_boom()
		m._feel_freeze(CFG.FREEZE_KILL)
	if m.fx != null:
		var col: Color = m._html_color(String(e.def.get("color", "#ff6f91")))
		m.fx.explode(at, col, e.size, e.elite)
		m.fx.float_text(at + Vector2(0, -e.size * 0.7), "+%d" % int(e.score_value),
			Color(1.0, 0.94, 0.72), 14)
	m._add_shake(5.0 if e.elite else 1.8, 0.26)


func player_hit() -> void:
	m.sfx.play_hit()
	if m.fx != null:
		m.fx.explode(m.player_pos, m._html_color("#FF6B7A"), 34.0, true)
	m._add_shake(10.0, 0.36)
	# 反射护盾一次免死（Unity：ReflectT>0 → 消耗、invuln 1.5、nova+4 raw、清弹）
	if m.reflect_t > 0.0:
		m.reflect_t = 0.0
		m.player_invuln = CFG.INVULN_AFTER_REFLECT
		m._gain_nova_raw(CFG.NOVA_ON_REFLECT_SAVE)
		m.enemy_bullets.clear()
		m._feel_freeze(CFG.FREEZE_HIT)
		return
	# 护盾优先：掉了只丢一层，不清弹（Unity：shield break 不 clear）
	if m.player_shields > 0:
		m.player_shields -= 1
		m.player_invuln = CFG.INVULN_AFTER_SHIELD
		m._gain_nova_raw(CFG.NOVA_ON_SHIELD_BREAK)
		m._feel_freeze(CFG.FREEZE_HIT)
	else:
		# 船体受击：清弹、慢镜、武器惩罚、丢僚机、重生位移
		m.player_lives -= 1
		m.player_invuln = CFG.INVULN_AFTER_HULL_HIT
		m._gain_nova_raw(CFG.NOVA_ON_HULL_HIT)
		m._feel_slow(CFG.SLOW_HIT_SCALE, CFG.SLOW_HIT_DUR)
		m._feel_freeze(CFG.FREEZE_HIT)
		m.combo = 0
		m.multiplier = 1
		m.combo_timer = 0.0
		m.enemy_bullets.clear()
		# 武器惩罚：蓄能 -45、共鸣清零、等级 -1、失谐检查（Unity OnPlayerHit）
		var active: WeaponSystem.LineState = m.weapons.active()
		active.charge = maxf(0.0, active.charge - CFG.HIT_CHARGE_PENALTY)
		m.weapons.resonance = 0.0
		if active.charge <= 0.5:
			active.detuned = true
		if active.level > 1:
			active.level -= 1
		# 击落一架僚机（Unity DestroyOneDrone）
		if m.drones.size() > 0:
			m.drones.pop_back()
		# 重生位移到底部安全区（Unity RespawnY）
		m.player_pos = Vector2(m.view_size.x * 0.5,
			m.view_size.y - CFG.RESPAWN_INSET - m.safe_bottom)
	if m.player_lives <= 0:
		m.game_over = true
		m.game_over_time = 0.0
		# 死亡立即关闭突破草稿，避免结算被三选一卡片挡住
		m.upgrade_pending = false
		m.upgrade_options.clear()
		m._save_best()
		m.sfx.play_boom()


func _seg_point_d2(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0
	if len2 > 0.0:
		t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	var q := a + ab * t
	return p.distance_squared_to(q)