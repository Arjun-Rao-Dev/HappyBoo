extends Node2D

signal projectile_fired(projectile_position: Vector2, projectile_rotation: float, projectile_direction: Vector2, muzzle_position: Vector2, muzzle_rotation: float)

@export var fire_interval: float = 0.5

@onready var projectile_scene: PackedScene = preload("res://pistol/projectile.tscn")
@onready var muzzle_flash_scene: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
@onready var fire_timer: Timer = $FireTimer
@onready var muzzle: Marker2D = $Muzzle
@onready var detection_area: Area2D = $DetectionArea

var detected_mobs: Array[Node2D] = []
var _is_active := true
var _external_control := false
var _external_fire_held := false
var _firing_enabled := true


func _ready() -> void:
	fire_timer.wait_time = fire_interval
	fire_timer.start()
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)


func _process(_delta: float) -> void:
	if _external_control:
		return
	look_at(get_global_mouse_position())


func _on_fire_timer_timeout() -> void:
	if not _firing_enabled:
		return
	if _external_control and not _external_fire_held:
		return
	_fire_projectile()


func _fire_projectile() -> void:
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	var shooter := get_parent()
	if shooter != null:
		projectile.shooter = shooter
	projectile.global_position = muzzle.global_position
	projectile.rotation = global_rotation
	projectile.direction = Vector2.RIGHT.rotated(global_rotation)

	var muzzle_flash := muzzle_flash_scene.instantiate()
	get_tree().current_scene.add_child(muzzle_flash)
	muzzle_flash.global_position = muzzle.global_position
	muzzle_flash.global_rotation = global_rotation
	emit_signal(
		"projectile_fired",
		projectile.global_position,
		projectile.rotation,
		projectile.direction,
		muzzle_flash.global_position,
		muzzle_flash.global_rotation
	)


func _on_detection_area_body_entered(body: Node) -> void:
	if body.is_in_group("mobs"):
		detected_mobs.append(body)


func _on_detection_area_body_exited(body: Node) -> void:
	if body.is_in_group("mobs"):
		detected_mobs.erase(body)


func set_active(active: bool) -> void:
	_is_active = active
	set_process(active)
	if active:
		if _firing_enabled:
			fire_timer.start()
	else:
		fire_timer.stop()


func set_external_control(enabled: bool) -> void:
	_external_control = enabled
	if not enabled:
		_external_fire_held = false
	if not _is_active:
		fire_timer.stop()
		return
	if not _firing_enabled:
		fire_timer.stop()
	else:
		fire_timer.start()


func set_external_aim_position(world_position: Vector2) -> void:
	if not _is_active:
		return
	look_at(world_position)


func set_external_fire_pressed(fire_pressed: bool) -> void:
	if not _is_active:
		return
	if not _firing_enabled:
		return
	if not _external_control:
		return
	if fire_pressed and not _external_fire_held:
		_fire_projectile()
		fire_timer.start()
	_external_fire_held = fire_pressed


func set_firing_enabled(enabled: bool) -> void:
	_firing_enabled = enabled
	if not enabled:
		fire_timer.stop()
		return
	if _is_active:
		fire_timer.start()
