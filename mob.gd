extends CharacterBody2D

@export var move_speed: float = 300.0
@export var headstart_seconds: float = 5.0
@export var max_health: float = 1.0
@export var contact_damage: float = 12.0

var player: Node2D
var spawn_time_ms: int = 0
var current_health: float = 1.0


func _ready() -> void:
	add_to_group("mobs")
	player = _find_target_player()
	spawn_time_ms = Time.get_ticks_msec()
	current_health = max_health


func _physics_process(_delta: float) -> void:
	var elapsed_seconds := float(Time.get_ticks_msec() - spawn_time_ms) / 1000.0
	if elapsed_seconds < headstart_seconds:
		velocity = Vector2.ZERO
		return

	if player == null or not is_instance_valid(player):
		player = _find_target_player()
	if player == null:
		velocity = Vector2.ZERO
		return

	var direction := global_position.direction_to(player.global_position)
	velocity = direction * move_speed
	move_and_slide()


func take_damage(amount: float) -> bool:
	current_health = max(current_health - amount, 0.0)
	if current_health > 0.0:
		return false
	queue_free()
	return true


func get_contact_damage() -> float:
	return contact_damage


func _find_target_player() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := INF
	for candidate in get_tree().get_nodes_in_group("players"):
		if not (candidate is Node2D):
			continue
		var node := candidate as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("is_dead_state") and node.is_dead_state():
			continue
		var dist := global_position.distance_squared_to(node.global_position)
		if dist < nearest_distance:
			nearest_distance = dist
			nearest = node
	return nearest
