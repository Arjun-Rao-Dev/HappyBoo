extends Node2D

const POSITION_LERP_SPEED := 12.0

var target_position := Vector2.ZERO
var _username := "Player"
var _skin_id := "classic"
var _animation_state := "idle"
var _gun_active := false
var _aim_angle := 0.0

@onready var happy_boo = $HappyBoo
@onready var gun_display: Node2D = $GunDisplay
@onready var username_label: Label = $UsernameLabel


func _ready() -> void:
	target_position = global_position
	_apply_display_state()


func _process(delta: float) -> void:
	global_position = global_position.lerp(target_position, clampf(delta * POSITION_LERP_SPEED, 0.0, 1.0))


func apply_state(state: Dictionary) -> void:
	var position_data: Variant = state.get("position", {})
	if position_data is Dictionary:
		target_position = Vector2(
			float(position_data.get("x", target_position.x)),
			float(position_data.get("y", target_position.y))
		)
		if global_position == Vector2.ZERO:
			global_position = target_position

	_username = String(state.get("username", _username))
	_skin_id = String(state.get("skin_id", _skin_id))
	_animation_state = String(state.get("animation", _animation_state))
	_gun_active = bool(state.get("gun_active", _gun_active))
	_aim_angle = float(state.get("aim_angle", _aim_angle))
	_apply_display_state()


func _apply_display_state() -> void:
	username_label.text = _username if not _username.strip_edges().is_empty() else "Player"
	if happy_boo.has_method("apply_skin_id"):
		happy_boo.apply_skin_id(_skin_id)
	if _animation_state == "walk":
		happy_boo.play_walk_animation()
	else:
		happy_boo.play_idle_animation()
	gun_display.visible = _gun_active
	gun_display.global_rotation = _aim_angle
