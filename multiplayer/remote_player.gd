extends Node2D

const POSITION_LERP_SPEED := 18.0
const AIM_LERP_SPEED := 24.0
const MAX_PREDICTION_SECONDS := 0.12
const SNAP_DISTANCE := 260.0

var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO
var _username := "Player"
var _skin_id := "classic"
var _animation_state := "idle"
var _gun_active := false
var _aim_angle := 0.0
var _target_aim_angle := 0.0
var _last_state_time_ms := 0

@onready var happy_boo = $HappyBoo
@onready var gun_display: Node2D = $GunDisplay
@onready var username_label: Label = $UsernameLabel


func _ready() -> void:
	target_position = global_position
	_apply_display_state()


func _process(delta: float) -> void:
	var age_seconds := float(Time.get_ticks_msec() - _last_state_time_ms) / 1000.0
	var predicted_position := target_position + target_velocity * minf(age_seconds, MAX_PREDICTION_SECONDS)
	if global_position.distance_to(predicted_position) > SNAP_DISTANCE:
		global_position = predicted_position
	else:
		global_position = global_position.lerp(predicted_position, clampf(delta * POSITION_LERP_SPEED, 0.0, 1.0))
	_aim_angle = lerp_angle(_aim_angle, _target_aim_angle, clampf(delta * AIM_LERP_SPEED, 0.0, 1.0))
	gun_display.global_rotation = _aim_angle


func apply_state(state: Dictionary) -> void:
	_last_state_time_ms = Time.get_ticks_msec()
	var position_data: Variant = state.get("position", {})
	if position_data is Dictionary:
		target_position = Vector2(
			float(position_data.get("x", target_position.x)),
			float(position_data.get("y", target_position.y))
		)
		if global_position == Vector2.ZERO:
			global_position = target_position
	var velocity_data: Variant = state.get("velocity", {})
	if velocity_data is Dictionary:
		target_velocity = Vector2(
			float(velocity_data.get("x", target_velocity.x)),
			float(velocity_data.get("y", target_velocity.y))
		)

	_username = String(state.get("username", _username))
	_skin_id = String(state.get("skin_id", _skin_id))
	_animation_state = String(state.get("animation", _animation_state))
	_gun_active = bool(state.get("gun_active", _gun_active))
	_target_aim_angle = float(state.get("aim_angle", _target_aim_angle))
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
