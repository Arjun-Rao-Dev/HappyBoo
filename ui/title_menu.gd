extends Control

@onready var continue_button: Button = $CenterContainer/Panel/Margin/VBox/ContinueButton
@onready var multiplayer_button: Button = $CenterContainer/Panel/Margin/VBox/MultiplayerButton
@onready var options_button: Button = $CenterContainer/Panel/Margin/VBox/OptionsButton
@onready var new_run_button: Button = $CenterContainer/Panel/Margin/VBox/NewRunButton
@onready var quit_button: Button = $CenterContainer/Panel/Margin/VBox/QuitButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/VBox/StatusLabel
@onready var options_panel = $OptionsPanel


func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SettingsManager.load_settings()
	continue_button.pressed.connect(_on_continue_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	options_button.pressed.connect(_on_options_pressed)
	new_run_button.pressed.connect(_on_new_run_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	options_panel.closed.connect(_on_options_closed)
	_refresh_continue_state()
	if continue_button.disabled:
		new_run_button.grab_focus()
	else:
		continue_button.grab_focus()


func _refresh_continue_state() -> void:
	var can_continue := SaveManager.has_save()
	continue_button.disabled = not can_continue
	if can_continue:
		status_label.text = ""
	else:
		status_label.text = "No save found. Start a new run."


func _on_new_run_pressed() -> void:
	SaveManager.clear_pending_continue_run()
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_continue_pressed() -> void:
	var result := SaveManager.load_run()
	if bool(result.get("ok", false)):
		SaveManager.queue_continue_run(result.get("run_state", {}))
		get_tree().change_scene_to_file("res://survivors_game.tscn")
		return

	status_label.text = "Continue failed (%s). Starting a new run." % String(result.get("status", "error"))
	SaveManager.clear_pending_continue_run()
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_options_pressed() -> void:
	options_panel.show_panel()


func _on_multiplayer_pressed() -> void:
	SaveManager.clear_pending_continue_run()
	MultiplayerSession.reset_to_single_player()
	get_tree().change_scene_to_file("res://ui/multiplayer_menu.tscn")


func _on_options_closed() -> void:
	options_panel.hide_panel()
	_refresh_continue_state()


func _on_quit_pressed() -> void:
	get_tree().quit()
