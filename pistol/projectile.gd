extends Area2D

@export var speed: float = 1200.0
@export var life_time: float = 2.0
@export var player_damage: float = 20.0

var direction: Vector2 = Vector2.RIGHT
var network_visual_only: bool = false
var shooter: Node = null

@onready var life_timer: Timer = $LifeTimer
@onready var impact_scene: PackedScene = preload("res://pistol/impact/impact.tscn")


func _ready() -> void:
	life_timer.wait_time = life_time
	life_timer.start()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if network_visual_only:
		return
	if body == shooter:
		return
	var game := get_tree().current_scene
	var killed := false
	if body.is_in_group("mobs"):
		if body.has_method("take_damage"):
			killed = body.take_damage(1.0)
		else:
			body.queue_free()
			killed = true
		if killed and game and game.has_method("add_score"):
			game.add_score(1)
		_spawn_impact()
		queue_free()
		return

	if body.is_in_group("players") and _can_damage_players(game):
		if body.has_method("take_projectile_damage"):
			body.take_projectile_damage(player_damage)
		_spawn_impact()
		queue_free()
		return

	return


func _can_damage_players(game: Node) -> bool:
	if game == null:
		return false
	if not game.has_method("get"):
		return false
	var mode: String = String(game.get("session_mode"))
	return mode == "pvp"


func _on_life_timer_timeout() -> void:
	queue_free()


func _spawn_impact() -> void:
	var impact := impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
