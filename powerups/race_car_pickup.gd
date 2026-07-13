extends Area2D

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("powerups")
	body_entered.connect(_on_body_entered)
	sprite.z_index = 6


func _on_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	var game := get_tree().current_scene
	if game != null and game.has_method("handle_race_car_pickup"):
		game.handle_race_car_pickup(self, body)
