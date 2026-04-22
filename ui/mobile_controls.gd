extends Control

const STYLE_TEXTURE := preload("res://ui/mobile_controls/assets/style-g-large.png")
const ICONS_TEXTURE := preload("res://ui/mobile_controls/assets/icons-large.png")
const JOYSTICK_PAD_REGION := Rect2(516, 0, 256, 256)
const JOYSTICK_NUB_REGION := Rect2(968, 904, 128, 128)
const BUTTON_REGION := Rect2(1228, 780, 128, 128)
const CROSSHAIR_ICON_REGION := Rect2(392, 0, 96, 96)
const FIRE_ICON_REGION := Rect2(294, 588, 96, 96)
const JOYSTICK_MARGIN := Vector2(44, 44)
const BUTTON_MARGIN := Vector2(44, 44)
const BUTTON_VERTICAL_GAP := 26.0
const JOYSTICK_DEADZONE := 0.18
const AIM_DEADZONE := 0.12
const DEFAULT_AIM := Vector2.RIGHT

@onready var joystick_pad: TextureRect = $JoystickPad
@onready var joystick_nub: TextureRect = $JoystickPad/JoystickNub
@onready var shoot_button: TextureRect = $ShootButton
@onready var shoot_icon: TextureRect = $ShootButton/Icon
@onready var bomb_button: TextureRect = $BombButton
@onready var bomb_icon: TextureRect = $BombButton/Icon

var move_vector := Vector2.ZERO
var aim_vector := DEFAULT_AIM
var fire_pressed := false
var _bomb_queued := false
var _joystick_touch_id := -1
var _shoot_touch_id := -1
var _bomb_touch_id := -1
var _joystick_center := Vector2.ZERO
var _shoot_center := Vector2.ZERO
var _bomb_center := Vector2.ZERO
var _joystick_radius := 96.0
var _shoot_radius := 72.0
var _bomb_radius := 60.0


func _ready() -> void:
	set_process_unhandled_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_ensure_textures()
	_update_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
		return
	if event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)


func get_move_vector() -> Vector2:
	return move_vector


func get_aim_vector() -> Vector2:
	return aim_vector


func is_fire_pressed() -> bool:
	return fire_pressed


func consume_bomb_pressed() -> bool:
	if not _bomb_queued:
		return false
	_bomb_queued = false
	return true


func reset_state() -> void:
	move_vector = Vector2.ZERO
	fire_pressed = false
	_bomb_queued = false
	_joystick_touch_id = -1
	_shoot_touch_id = -1
	_bomb_touch_id = -1
	joystick_nub.position = (joystick_pad.size - joystick_nub.size) * 0.5
	shoot_button.modulate = Color(1, 1, 1, 0.92)
	bomb_button.modulate = Color(1, 1, 1, 0.92)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	var position := event.position
	if event.pressed:
		if _joystick_touch_id == -1 and position.distance_to(_joystick_center) <= _joystick_radius * 1.35:
			_joystick_touch_id = event.index
			_update_joystick(position)
			get_viewport().set_input_as_handled()
			return
		if _shoot_touch_id == -1 and position.distance_to(_shoot_center) <= _shoot_radius * 1.35:
			_shoot_touch_id = event.index
			_update_shoot(position)
			get_viewport().set_input_as_handled()
			return
		if _bomb_touch_id == -1 and position.distance_to(_bomb_center) <= _bomb_radius * 1.35:
			_bomb_touch_id = event.index
			_bomb_queued = true
			bomb_button.modulate = Color(1.08, 1.08, 1.08, 1.0)
			get_viewport().set_input_as_handled()
			return
	else:
		if event.index == _joystick_touch_id:
			_joystick_touch_id = -1
			move_vector = Vector2.ZERO
			joystick_nub.position = (joystick_pad.size - joystick_nub.size) * 0.5
			get_viewport().set_input_as_handled()
			return
		if event.index == _shoot_touch_id:
			_shoot_touch_id = -1
			fire_pressed = false
			shoot_button.modulate = Color(1, 1, 1, 0.92)
			get_viewport().set_input_as_handled()
			return
		if event.index == _bomb_touch_id:
			_bomb_touch_id = -1
			bomb_button.modulate = Color(1, 1, 1, 0.92)
			get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == _joystick_touch_id:
		_update_joystick(event.position)
		get_viewport().set_input_as_handled()
		return
	if event.index == _shoot_touch_id:
		_update_shoot(event.position)
		get_viewport().set_input_as_handled()


func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	joystick_pad.size = Vector2(188, 188)
	joystick_nub.size = Vector2(92, 92)
	shoot_button.size = Vector2(136, 136)
	bomb_button.size = Vector2(116, 116)
	shoot_icon.size = Vector2(72, 72)
	bomb_icon.size = Vector2(62, 62)

	joystick_pad.position = Vector2(JOYSTICK_MARGIN.x, viewport_size.y - joystick_pad.size.y - JOYSTICK_MARGIN.y)
	shoot_button.position = Vector2(viewport_size.x - shoot_button.size.x - BUTTON_MARGIN.x, viewport_size.y - shoot_button.size.y - BUTTON_MARGIN.y)
	bomb_button.position = Vector2(
		shoot_button.position.x + (shoot_button.size.x - bomb_button.size.x) * 0.5,
		shoot_button.position.y - bomb_button.size.y - BUTTON_VERTICAL_GAP
	)
	joystick_nub.position = (joystick_pad.size - joystick_nub.size) * 0.5
	shoot_icon.position = (shoot_button.size - shoot_icon.size) * 0.5
	bomb_icon.position = (bomb_button.size - bomb_icon.size) * 0.5

	_joystick_center = joystick_pad.position + joystick_pad.size * 0.5
	_shoot_center = shoot_button.position + shoot_button.size * 0.5
	_bomb_center = bomb_button.position + bomb_button.size * 0.5
	_joystick_radius = joystick_pad.size.x * 0.36
	_shoot_radius = shoot_button.size.x * 0.42
	_bomb_radius = bomb_button.size.x * 0.42
	if _joystick_touch_id == -1:
		joystick_nub.position = (joystick_pad.size - joystick_nub.size) * 0.5


func _update_joystick(screen_position: Vector2) -> void:
	var delta := screen_position - _joystick_center
	var clamped := delta.limit_length(_joystick_radius)
	var normalized := clamped / _joystick_radius
	if normalized.length() < JOYSTICK_DEADZONE:
		move_vector = Vector2.ZERO
	else:
		move_vector = normalized
	joystick_nub.position = (joystick_pad.size - joystick_nub.size) * 0.5 + clamped


func _update_shoot(screen_position: Vector2) -> void:
	var delta := screen_position - _shoot_center
	var normalized := Vector2.ZERO
	if _shoot_radius > 0.0:
		normalized = delta / _shoot_radius
	if normalized.length() >= AIM_DEADZONE:
		aim_vector = normalized.normalized()
	fire_pressed = true
	shoot_button.modulate = Color(1.08, 1.08, 1.08, 1.0)


func _ensure_textures() -> void:
	joystick_pad.texture = _atlas_texture(STYLE_TEXTURE, JOYSTICK_PAD_REGION)
	joystick_nub.texture = _atlas_texture(STYLE_TEXTURE, JOYSTICK_NUB_REGION)
	shoot_button.texture = _atlas_texture(STYLE_TEXTURE, BUTTON_REGION)
	bomb_button.texture = _atlas_texture(STYLE_TEXTURE, BUTTON_REGION)
	shoot_icon.texture = _atlas_texture(ICONS_TEXTURE, CROSSHAIR_ICON_REGION)
	bomb_icon.texture = _atlas_texture(ICONS_TEXTURE, FIRE_ICON_REGION)
	joystick_pad.modulate = Color(1, 1, 1, 0.76)
	joystick_nub.modulate = Color(1, 1, 1, 0.96)
	shoot_button.modulate = Color(1, 1, 1, 0.92)
	bomb_button.modulate = Color(1, 1, 1, 0.92)
	shoot_icon.modulate = Color(0.15, 0.18, 0.2, 0.92)
	bomb_icon.modulate = Color(0.15, 0.18, 0.2, 0.92)


func _atlas_texture(texture: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = region
	return atlas
