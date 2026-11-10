class_name CollisionSystem
extends RefCounted

## 碰撞与击杀结算：玩家弹 vs 敌机/Boss、敌弹/机体 vs 玩家、击杀奖励与受击。
## 所有状态仍由 Main 持有，本模块只负责结算顺序。

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
	# 相位（冲刺期间）：擦身敌弹被消除，换分与星爆（对齐 web Phase* 常量）
	if m.dash_t > 0.0:
		for i in range(m.enemy_bullets.size() - 1, -1, -1):
			var pb = m.enemy_bullets[i]
			if pb.pos.distance_to(m.player_pos) <= CFG.PHASE_RADIUS + pb.radius:
				m.enemy_bullets.remove_at(i)
				m.score += CFG.PHASE_SCORE_PER_BULLET
				m._gain_nova(CFG.PHASE_NOVA_PER_BULLET)
				m._spawn_mote(pb.pos)
	if m.player_invuln > 0.0:
		return
	for i in range(m.enemy_bullets.size() - 1, -1, -1):
		var b = m.enemy_bullets[i]
		var d2 := _seg_point_d2(b.prev, b.pos, m.player_pos)
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
		if m.player_pos.distance_squared_to(en.pos) <= rr * rr:
			player_hit()
			return


func kill_enemy(index: int, diff: Dictionary) -> void:
	var e: Enemy = m.enemies[index]
	m.score += int(roundf(e.score_value * float(diff["scoreMul"]) * m.multiplier))
	m._gain_nova(CFG.NOVA_ON_ELITE_KILL if e.elite else CFG.NOVA_ON_KILL)
	m._add_combo()
	m.total_kills += 1
	m.waves.zone_kills += 1
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
	# 护盾优先，掉了只丢一层；护盾耗尽才吃船体
	if m.player_shields > 0:
		m.player_shields -= 1
		m.player_invuln = CFG.INVULN_AFTER_SHIELD
		m._gain_nova(CFG.NOVA_ON_SHIELD_BREAK)
		m._feel_freeze(CFG.FREEZE_HIT)
	else:
		m.player_lives -= 1
		m.player_invuln = CFG.INVULN_AFTER_HULL_HIT
		m._gain_nova(CFG.NOVA_ON_HULL_HIT)
		m._feel_slow(CFG.SLOW_HIT_SCALE, CFG.SLOW_HIT_DUR)
		m.combo = 0
		m.multiplier = 1
		m.combo_timer = 0.0
	m.enemy_bullets.clear()
	m.weapons.active().charge = maxf(0.0, m.weapons.active().charge - CFG.HIT_CHARGE_PENALTY)
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
