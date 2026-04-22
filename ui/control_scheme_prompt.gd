extends Control

@onready var body_label: Label = $CenterContainer/Panel/Margin/VBox/Body
@onready var keyboard_button: Button = $CenterContainer/Panel/Margin/VBox/KeyboardButton
@onready var touchscreen_button: Button = $CenterContainer/Panel/Margin/VBox/TouchscreenButton
@onready var back_button: Button = $CenterContainer/Panel/Margin/VBox/BackButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	keyboard_button.pressed.connect(_on_keyboard_pressed)
	touchscreen_button.pressed.connect(_on_touchscreen_pressed)
	back_button.pressed.connect(_on_back_pressed)
	var target_scene := SettingsManager.consume_start_scene()
	SettingsManager.queue_start_scene(target_scene)
	body_label.text = "Choose how you want to control this run before the game loads."
	var scheme := SettingsManager.get_control_scheme()
	if scheme == SettingsManager.CONTROL_SCHEME_TOUCHSCREEN:
		touchscreen_button.grab_focus()
	else:
		keyboard_button.grab_focus()


func _on_keyboard_pressed() -> void:
	_start_game_with_scheme(SettingsManager.CONTROL_SCHEME_KEYBOARD_MOUSE)


func _on_touchscreen_pressed() -> void:
	_start_game_with_scheme(SettingsManager.CONTROL_SCHEME_TOUCHSCREEN)


func _on_back_pressed() -> void:
	SettingsManager.queue_start_scene("res://survivors_game.tscn")
	if MultiplayerSession != null and MultiplayerSession.is_multiplayer:
		MultiplayerSession.leave_session()
		MultiplayerSession.reset_to_single_player()
		get_tree().change_scene_to_file("res://ui/multiplayer_menu.tscn")
		return
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _start_game_with_scheme(scheme: String) -> void:
	SettingsManager.set_control_scheme(scheme)
	var next_scene := SettingsManager.consume_start_scene()
	if next_scene.strip_edges().is_empty():
		next_scene = "res://survivors_game.tscn"
	get_tree().change_scene_to_file(next_scene)
