extends CharacterBody2D

signal died
signal health_changed(current: float, maximum: float)

@export var move_speed: float = 600.0
@export var max_health: float = 100.0
@export var damage_per_tick: float = 12.0
@export var bomb_cooldown_seconds: float = 30.0
@export var start_invulnerable_seconds: float = 5.0

var current_health: float
var is_dead := false
var overlapping_mobs: Array[Node2D] = []
var gun_unlocked_after_headstart := false
var spawn_time_ms: int = 0
var _use_external_input := false
var _external_input := Vector2.ZERO
var _external_aim_position := Vector2.ZERO
var _external_fire_pressed := false
var _actions_enabled := true

@onready var bomb_scene: PackedScene = preload("res://bombs/bomb.tscn")
@onready var health_bar: ProgressBar = $HealthBar
@onready var username_label: Label = $UsernameLabel
@onready var hurtbox: Area2D = $Hurtbox
@onready var damage_timer: Timer = $DamageTimer
@onready var bomb_cooldown_timer: Timer = $BombCooldownTimer
@onready var health_fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill").duplicate()

func _ready() -> void:
	add_to_group("players")
	spawn_time_ms = Time.get_ticks_msec()
	current_health = max_health
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_bar.add_theme_stylebox_override("fill", health_fill_style)
	_update_health_bar_color()
	health_bar.visible = false
	_update_username_label()
	emit_signal("health_changed", current_health, max_health)
	if has_node("Gun"):
		$Gun.set_active(false)


func _physics_process(_delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return
	_update_headstart_gun_state()
	var direction := _external_input if _use_external_input else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * move_speed
	move_and_slide()
	if _use_external_input:
		var gun_node := get_node_or_null("Gun")
		if gun_node:
			if gun_node.has_method("set_external_aim_position"):
				gun_node.set_external_aim_position(_external_aim_position)
			if gun_node.has_method("set_external_fire_pressed"):
				gun_node.set_external_fire_pressed(_external_fire_pressed)
		_external_fire_pressed = false
	if _actions_enabled:
		_try_throw_bomb()
	
	if velocity.length() > 0.0:
		$%HappyBoo.play_walk_animation()
	else: 
		$%HappyBoo.play_idle_animation()


func _on_hurtbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("mobs") and not overlapping_mobs.has(body):
		overlapping_mobs.append(body)


func _on_hurtbox_body_exited(body: Node2D) -> void:
	if body.is_in_group("mobs"):
		overlapping_mobs.erase(body)


func _on_damage_timer_timeout() -> void:
	if is_dead:
		return
	var elapsed_seconds := float(Time.get_ticks_msec() - spawn_time_ms) / 1000.0
	if elapsed_seconds < start_invulnerable_seconds:
		return

	# Query the area each tick so damage doesn't rely on potentially stale enter/exit signals.
	var current_overlaps: Array[Node2D] = []
	for body in hurtbox.get_overlapping_bodies():
		if body is Node2D and body.is_in_group("mobs"):
			current_overlaps.append(body as Node2D)
	overlapping_mobs = current_overlaps
	if overlapping_mobs.is_empty():
		return

	var total_damage := 0.0
	var tick_seconds := maxf(damage_timer.wait_time, 0.016)
	for mob in overlapping_mobs:
		if not is_instance_valid(mob):
			continue
		if mob.has_method("get_contact_damage"):
			total_damage += float(mob.get_contact_damage()) * tick_seconds
		else:
			total_damage += damage_per_tick * tick_seconds

	if total_damage > 0.0:
		_apply_damage(total_damage)


func _apply_damage(amount: float) -> void:
	current_health = max(current_health - amount, 0.0)
	health_bar.value = current_health
	_update_health_bar_color()
	emit_signal("health_changed", current_health, max_health)
	if current_health > 0.0:
		return
	_die()


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	damage_timer.stop()
	set_physics_process(false)
	if has_node("Gun"):
		$Gun.set_active(false)
	emit_signal("died")


func heal(amount: float) -> void:
	if is_dead:
		return
	current_health = min(current_health + amount, max_health)
	health_bar.value = current_health
	_update_health_bar_color()
	emit_signal("health_changed", current_health, max_health)


func _update_health_bar_color() -> void:
	var health_ratio := clampf(current_health / max_health, 0.0, 1.0)
	var green := Color(0.55, 0.85, 0.33, 1.0)
	var yellow := Color(0.97, 0.88, 0.25, 1.0)
	var orange := Color(0.98, 0.58, 0.20, 1.0)
	var red := Color(0.90, 0.20, 0.20, 1.0)
	var health_color: Color

	if health_ratio >= 0.66:
		var t_high := inverse_lerp(0.66, 1.0, health_ratio)
		health_color = yellow.lerp(green, t_high)
	elif health_ratio >= 0.33:
		var t_mid := inverse_lerp(0.33, 0.66, health_ratio)
		health_color = orange.lerp(yellow, t_mid)
	else:
		var t_low := inverse_lerp(0.0, 0.33, health_ratio)
		health_color = red.lerp(orange, t_low)

	health_fill_style.bg_color = health_color


func _try_throw_bomb() -> void:
	if not Input.is_action_just_pressed("throw_bomb"):
		return
	if not can_throw_bomb():
		return

	var throw_direction := get_global_mouse_position() - global_position
	if throw_direction.length() == 0.0:
		throw_direction = Vector2.RIGHT

	var bomb := bomb_scene.instantiate()
	get_tree().current_scene.add_child(bomb)
	bomb.global_position = global_position + throw_direction.normalized() * 36.0
	if bomb.has_method("launch"):
		bomb.launch(throw_direction)

	bomb_cooldown_timer.start(bomb_cooldown_seconds)


func can_throw_bomb() -> bool:
	return (not is_dead) and bomb_cooldown_timer.is_stopped() and current_health >= max_health


func get_bomb_cooldown_remaining() -> float:
	return bomb_cooldown_timer.time_left


func get_bomb_cooldown_total() -> float:
	return bomb_cooldown_seconds


func is_full_health() -> bool:
	return current_health >= max_health


func get_current_health() -> float:
	return current_health


func get_max_health() -> float:
	return max_health


func restore_from_run_state(restored_health: float, restored_max_health: float) -> void:
	max_health = maxf(restored_max_health, 1.0)
	current_health = clampf(restored_health, 0.0, max_health)
	health_bar.max_value = max_health
	health_bar.value = current_health
	_update_health_bar_color()
	emit_signal("health_changed", current_health, max_health)


func _update_username_label() -> void:
	var username := ""
	if SettingsManager != null:
		username = SettingsManager.get_username()
	if username.strip_edges().is_empty():
		username = "Player"
	username_label.text = username


func _update_headstart_gun_state() -> void:
	if not _actions_enabled:
		return
	if gun_unlocked_after_headstart:
		return
	var elapsed_seconds := float(Time.get_ticks_msec() - spawn_time_ms) / 1000.0
	if elapsed_seconds < start_invulnerable_seconds:
		return
	gun_unlocked_after_headstart = true
	if has_node("Gun"):
		$Gun.set_active(true)


func set_use_external_input(enabled: bool) -> void:
	_use_external_input = enabled
	var gun_node := get_node_or_null("Gun")
	if gun_node and gun_node.has_method("set_external_control"):
		gun_node.set_external_control(enabled)


func set_external_input_vector(input_vector: Vector2) -> void:
	_external_input = input_vector


func set_external_aim_position(aim_position: Vector2) -> void:
	_external_aim_position = aim_position


func set_external_fire_pressed(fire_pressed: bool) -> void:
	_external_fire_pressed = fire_pressed


func set_actions_enabled(enabled: bool) -> void:
	_actions_enabled = enabled
	if not enabled and has_node("Gun"):
		var gun_node := get_node_or_null("Gun")
		if gun_node and gun_node.has_method("set_active"):
			gun_node.set_active(false)


func set_display_name(name: String) -> void:
	var normalized := name.strip_edges()
	if normalized.is_empty():
		normalized = "Player"
	if username_label != null:
		username_label.text = normalized


func is_dead_state() -> bool:
	return is_dead
