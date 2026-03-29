extends RigidBody2D

@export var throw_impulse: float = 950.0
@export var fuse_time: float = 1.4
@export var blast_radius: float = 3000.0
@export var blast_damage: float = 9999.0

@onready var fuse_timer: Timer = $FuseTimer
@onready var bomb_sprite: Sprite2D = $Sprite2D
@onready var explosion_scene: PackedScene = preload("res://pistol/impact/impact.tscn")


func _ready() -> void:
	bomb_sprite.texture = _load_texture_from_file("res://bombs/tanks_mineOn.png")
	fuse_timer.wait_time = fuse_time
	fuse_timer.start()


func launch(direction: Vector2) -> void:
	if direction.length() == 0.0:
		direction = Vector2.RIGHT
	apply_central_impulse(direction.normalized() * throw_impulse)
	angular_velocity = randf_range(-8.0, 8.0)


func _on_fuse_timer_timeout() -> void:
	_explode()


func _explode() -> void:
	_spawn_explosion_visual()

	var kills := 0
	for mob in get_tree().get_nodes_in_group("mobs"):
		if is_instance_valid(mob):
			if not (mob is Node2D):
				continue
			var mob_node := mob as Node2D
			if mob_node.global_position.distance_to(global_position) > blast_radius:
				continue
			if mob.has_method("take_damage"):
				if mob.take_damage(blast_damage):
					kills += 1
			else:
				mob.queue_free()
				kills += 1

	var game := get_tree().current_scene
	if kills > 0 and game and game.has_method("add_score"):
		game.add_score(kills)

	queue_free()


func _spawn_explosion_visual() -> void:
	var impact := explosion_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position

	var sprite := Sprite2D.new()
	sprite.texture = _load_texture_from_file("res://bombs/tank_explosion12.png")
	sprite.scale = Vector2.ONE * 13.0
	impact.add_child(sprite)


func _load_texture_from_file(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)
