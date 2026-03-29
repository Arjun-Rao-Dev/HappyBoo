extends Area2D

@export var heal_amount: float = 20.0

const FOOD_TEXTURE_PATHS := [
	"res://food/tile_0000.png",
	"res://food/tile_0005.png",
	"res://food/tile_0010.png",
	"res://food/tile_0015.png",
	"res://food/tile_0020.png",
	"res://food/tile_0025.png",
	"res://food/tile_0030.png",
	"res://food/tile_0035.png",
	"res://food/tile_0040.png",
	"res://food/tile_0045.png",
	"res://food/tile_0050.png",
	"res://food/tile_0055.png"
]

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite.texture = _load_texture_from_file(FOOD_TEXTURE_PATHS.pick_random())
	sprite.scale = Vector2.ONE * randf_range(1.6, 2.1)


func _on_body_entered(body: Node) -> void:
	if body.name != "Player":
		return
	if body.has_method("heal"):
		body.heal(heal_amount)
	queue_free()


func _load_texture_from_file(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)
