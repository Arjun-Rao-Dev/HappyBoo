extends CanvasLayer

@export var hotspot: Vector2 = Vector2(1.0, 1.0)
@onready var pointer: TextureRect = $Pointer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_follow_mouse()


func _process(_delta: float) -> void:
	_follow_mouse()


func _follow_mouse() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	pointer.position = mouse_pos - hotspot
