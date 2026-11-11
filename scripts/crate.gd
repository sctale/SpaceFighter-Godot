class_name Crate
extends RefCounted

## 补给箱（Unity SupplyCrate，9 类）：75.6px/s 直线下落，非宝石 42°/s 自旋；
## 无磁吸、无寿命超时，拾取半径 30px 由 Main 判定，落出屏幕才消失。

const CFG := preload("res://scripts/game_config.gd")

const KINDS := ["weapon", "drone", "life", "shield", "gem", "swap", "reflect", "prism", "swarm"]

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var kind := "weapon"
var age := 0.0
var dead := false
var spin := 0.0


func setup(p_pos: Vector2, p_kind: String) -> void:
	pos = p_pos
	kind = p_kind if KINDS.has(p_kind) else "weapon"
	vel = Vector2(0, CFG.CRATE_FALL_SPEED)


func tick(dt: float, _player_pos: Vector2) -> void:
	age += dt
	if kind != "gem":
		spin += dt * deg_to_rad(CFG.CRATE_SPIN_DEG)
	pos += vel * dt
	# Unity DespawnY = −HalfHeight−0.6world → 画布 y > H+32.4
	if pos.y > CFG.VIEW.y + 32.4:
		dead = true