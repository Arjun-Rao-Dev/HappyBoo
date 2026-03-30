extends "res://mob.gd"

@export var sprite_texture: Texture2D
@export var sprite_scale: float = 2.0

@onready var body_sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	super._ready()
	body_sprite.texture = sprite_texture
	if body_sprite.texture == null:
		# Never keep a collider-only monster alive if art failed to load in exports.
		queue_free()
		return
	body_sprite.scale = Vector2.ONE * sprite_scale
