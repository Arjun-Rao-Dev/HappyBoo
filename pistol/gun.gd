extends Node2D

@export var fire_interval: float = 0.5
@export var projectile_damage: float = 1.0
@export var projectile_speed: float = 1200.0
@export var projectile_scale: float = 1.0
@export var shot_count: int = 1
@export var spread_degrees: float = 0.0
@export var projectile_color: Color = Color.WHITE

@onready var projectile_scene: PackedScene = preload("res://pistol/projectile.tscn")
@onready var muzzle_flash_scene: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
@onready var fire_timer: Timer = $FireTimer
@onready var muzzle: Marker2D = $Muzzle
@onready var detection_area: Area2D = $DetectionArea
@onready var weapon_sprite: Sprite2D = $Sprite2D

var detected_mobs: Array[Node2D] = []
var _is_active := true
var _base_weapon_data: Dictionary = {}
var _upgrade_level := 0


func _ready() -> void:
	apply_weapon_data(SettingsManager.get_weapon_data())
	fire_timer.wait_time = fire_interval
	fire_timer.start()
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)


func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())


func _on_fire_timer_timeout() -> void:
	_fire_projectile()


func _fire_projectile() -> void:
	if not _is_active:
		return
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return
	var angles := _get_shot_angles()
	for angle in angles:
		_spawn_projectile(current_scene, angle)
	_spawn_muzzle_flash(current_scene)


func _spawn_projectile(current_scene: Node, angle: float) -> void:
	var projectile := projectile_scene.instantiate()
	current_scene.add_child(projectile)
	var shooter := get_parent()
	if shooter != null:
		projectile.shooter = shooter
	projectile.global_position = muzzle.global_position
	projectile.rotation = angle
	projectile.direction = Vector2.RIGHT.rotated(angle)
	projectile.damage = projectile_damage
	projectile.speed = projectile_speed
	projectile.scale = Vector2.ONE * projectile_scale
	projectile.modulate = projectile_color
	if current_scene != null and current_scene.has_method("handle_local_projectile_fired"):
		current_scene.handle_local_projectile_fired(
			muzzle.global_position,
			angle,
			projectile_damage,
			projectile_speed,
			projectile_scale,
			projectile_color
		)


func _spawn_muzzle_flash(current_scene: Node) -> void:
	var muzzle_flash := muzzle_flash_scene.instantiate()
	current_scene.add_child(muzzle_flash)
	muzzle_flash.global_position = muzzle.global_position
	muzzle_flash.global_rotation = global_rotation


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
		fire_timer.wait_time = fire_interval
		fire_timer.start()
	else:
		fire_timer.stop()


func apply_weapon_data(weapon_data: Dictionary) -> void:
	_base_weapon_data = weapon_data.duplicate(true)
	fire_interval = float(_base_weapon_data.get("fire_interval", fire_interval))
	projectile_damage = float(_base_weapon_data.get("damage", projectile_damage))
	projectile_speed = float(_base_weapon_data.get("projectile_speed", projectile_speed))
	projectile_scale = float(_base_weapon_data.get("projectile_scale", projectile_scale))
	shot_count = maxi(int(_base_weapon_data.get("shot_count", shot_count)), 1)
	spread_degrees = maxf(float(_base_weapon_data.get("spread_degrees", spread_degrees)), 0.0)
	projectile_color = _base_weapon_data.get("projectile_color", projectile_color)
	var preview_path := String(_base_weapon_data.get("preview", ""))
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
		weapon_sprite.texture = load(preview_path) as Texture2D
	_apply_upgrade_level(_upgrade_level)


func set_upgrade_level(level: int) -> void:
	_upgrade_level = maxi(level, 0)
	_apply_upgrade_level(_upgrade_level)


func get_weapon_name() -> String:
	return String(_base_weapon_data.get("name", "Pistol"))


func _apply_upgrade_level(level: int) -> void:
	var base_interval := float(_base_weapon_data.get("fire_interval", 0.5))
	var base_damage := float(_base_weapon_data.get("damage", 1.0))
	var base_speed := float(_base_weapon_data.get("projectile_speed", 1200.0))
	var base_scale := float(_base_weapon_data.get("projectile_scale", 1.0))
	var base_shot_count := maxi(int(_base_weapon_data.get("shot_count", 1)), 1)
	var fire_rate_steps := int(ceil(float(level) / 4.0))
	var damage_steps := int(ceil(float(maxi(level - 1, 0)) / 4.0))
	var speed_steps := int(ceil(float(maxi(level - 2, 0)) / 4.0))
	var spread_steps := int(ceil(float(maxi(level - 3, 0)) / 4.0))
	fire_interval = maxf(base_interval * pow(0.88, fire_rate_steps), 0.12)
	projectile_damage = base_damage + float(damage_steps)
	projectile_speed = base_speed + float(speed_steps) * 120.0
	projectile_scale = base_scale + float(damage_steps) * 0.08
	shot_count = mini(base_shot_count + spread_steps, 5)
	spread_degrees = 10.0 if shot_count > 1 else float(_base_weapon_data.get("spread_degrees", 0.0))
	if fire_timer != null:
		fire_timer.wait_time = fire_interval


func _get_shot_angles() -> Array[float]:
	var angles: Array[float] = []
	var count := maxi(shot_count, 1)
	if count == 1:
		angles.append(global_rotation)
		return angles
	var total_spread := deg_to_rad(spread_degrees * float(count - 1))
	var start_angle := global_rotation - total_spread * 0.5
	var step := total_spread / float(count - 1)
	for index in range(count):
		angles.append(start_angle + step * float(index))
	return angles
