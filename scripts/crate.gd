class_name Crate
extends RefCounted

## 补给箱（10 种）：缓慢下落 + 靠近磁吸，落地超时消失。

const CFG := preload("res://scripts/game_config.gd")

const KINDS := ["weapon", "drone", "life", "shield", "charge", "nova", "gem", "swap", "reflect", "prism"]

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var kind := "weapon"
var age := 0.0
var life := 14.0
var dead := false
var spin := 0.0


func setup(p_pos: Vector2, p_kind: String) -> void:
	pos = p_pos
	kind = p_kind if KINDS.has(p_kind) else "weapon"
	vel = Vector2(randf_range(-12.0, 12.0), 58.0)


func tick(dt: float, player_pos: Vector2) -> void:
	age += dt
	spin += dt * 1.6
	life -= dt
	var to_player := player_pos - pos
	var d := to_player.length()
	if d < 170.0 and d > 1.0:
		# 磁吸：越近越快
		var pull := (1.0 - d / 170.0) * 620.0
		vel = vel.lerp(to_player.normalized() * pull, 1.0 - exp(-6.0 * dt))
	pos += vel * dt
	if life <= 0.0 or pos.y > CFG.VIEW.y + 40.0:
		dead = true