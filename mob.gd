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
	player = get_node_or_null("/root/Game/Player")
	spawn_time_ms = Time.get_ticks_msec()
	current_health = max_health


func _physics_process(_delta: float) -> void:
	var elapsed_seconds := float(Time.get_ticks_msec() - spawn_time_ms) / 1000.0
	if elapsed_seconds < headstart_seconds:
		velocity = Vector2.ZERO
		return

	if player == null:
		player = get_node_or_null("/root/Game/Player")
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
