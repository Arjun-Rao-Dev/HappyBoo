extends Node2D

@export var fire_interval: float = 0.5

@onready var projectile_scene: PackedScene = preload("res://pistol/projectile.tscn")
@onready var muzzle_flash_scene: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
@onready var fire_timer: Timer = $FireTimer
@onready var muzzle: Marker2D = $Muzzle
@onready var detection_area: Area2D = $DetectionArea

var detected_mobs: Array[Node2D] = []


func _ready() -> void:
	fire_timer.wait_time = fire_interval
	fire_timer.start()
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)


func _process(_delta: float) -> void:
	look_at(get_global_mouse_position())


func _on_fire_timer_timeout() -> void:
	_fire_projectile()


func _fire_projectile() -> void:
	var projectile := projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = muzzle.global_position
	projectile.rotation = global_rotation
	projectile.direction = Vector2.RIGHT.rotated(global_rotation)

	var muzzle_flash := muzzle_flash_scene.instantiate()
	get_tree().current_scene.add_child(muzzle_flash)
	muzzle_flash.global_position = muzzle.global_position
	muzzle_flash.global_rotation = global_rotation


func _on_detection_area_body_entered(body: Node) -> void:
	if body.is_in_group("mobs"):
		detected_mobs.append(body)


func _on_detection_area_body_exited(body: Node) -> void:
	if body.is_in_group("mobs"):
		detected_mobs.erase(body)


func set_active(active: bool) -> void:
	set_process(active)
	if active:
		fire_timer.start()
	else:
		fire_timer.stop()
