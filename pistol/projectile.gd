extends Area2D

@export var speed: float = 1200.0
@export var life_time: float = 2.0
@export var damage: float = 1.0

var direction: Vector2 = Vector2.RIGHT
var shooter: Node = null
var visual_only := false

@onready var life_timer: Timer = $LifeTimer
@onready var impact_scene: PackedScene = preload("res://pistol/impact/impact.tscn")


func _ready() -> void:
	add_to_group("projectiles")
	life_timer.wait_time = life_time
	life_timer.start()
	if visual_only:
		monitoring = false
		collision_mask = 0
		collision_layer = 0
		return
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	var game := get_tree().current_scene
	if body.is_in_group("network_mobs"):
		if game and game.has_method("request_network_projectile_hit"):
			game.request_network_projectile_hit(body, damage)
		_spawn_impact()
		queue_free()
		return

	var killed := false
	if body.is_in_group("mobs"):
		if body.has_method("take_damage"):
			if game and game.has_method("apply_network_mob_damage"):
				killed = game.apply_network_mob_damage(body, damage, true)
			else:
				killed = body.take_damage(damage)
		else:
			body.queue_free()
			killed = true
		if killed and game and game.has_method("add_score"):
			game.add_score(1)
		_spawn_impact()
		queue_free()
		return

	return


func _on_life_timer_timeout() -> void:
	queue_free()


func _spawn_impact() -> void:
	var impact := impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
