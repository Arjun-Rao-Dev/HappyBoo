extends CanvasLayer

@onready var sprite: TextureRect = $Crosshair


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	follow_mouse()


func _process(_delta: float) -> void:
	follow_mouse()


func follow_mouse() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	sprite.position = mouse_pos - sprite.size * 0.5
