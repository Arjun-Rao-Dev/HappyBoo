extends "res://mob.gd"

@export var sprite_path: String = ""
@export var sprite_scale: float = 2.0

@onready var body_sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	super._ready()
	body_sprite.texture = _load_texture_from_file(sprite_path)
	body_sprite.scale = Vector2.ONE * sprite_scale


func _load_texture_from_file(path: String) -> Texture2D:
	var image := Image.new()
	var err := image.load(path)
	if err != OK:
		return null
	return ImageTexture.create_from_image(image)
