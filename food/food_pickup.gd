extends Area2D

@export var heal_amount: float = 20.0

var network_id := ""
var network_mode := "local"

const FOOD_TEXTURES: Array[Texture2D] = [
	preload("res://food/tile_0000.png"),
	preload("res://food/tile_0005.png"),
	preload("res://food/tile_0010.png"),
	preload("res://food/tile_0015.png"),
	preload("res://food/tile_0020.png"),
	preload("res://food/tile_0025.png"),
	preload("res://food/tile_0030.png"),
	preload("res://food/tile_0035.png"),
	preload("res://food/tile_0040.png"),
	preload("res://food/tile_0045.png"),
	preload("res://food/tile_0050.png"),
	preload("res://food/tile_0055.png")
]

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("foods")
	body_entered.connect(_on_body_entered)
	sprite.texture = FOOD_TEXTURES.pick_random()
	sprite.scale = Vector2.ONE * randf_range(1.6, 2.1)
	sprite.z_index = 5


func apply_network_visual(texture_index: int, visual_scale: float) -> void:
	var safe_index := clampi(texture_index, 0, FOOD_TEXTURES.size() - 1)
	sprite.texture = FOOD_TEXTURES[safe_index]
	sprite.scale = Vector2.ONE * maxf(visual_scale, 0.1)


func _on_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	var game := get_tree().current_scene
	if game != null and game.has_method("handle_food_pickup"):
		game.handle_food_pickup(self, body)
		return
	if body.has_method("heal"):
		body.heal(heal_amount)
	queue_free()
