extends Control

@onready var line_edit: LineEdit = $CenterContainer/Panel/Margin/VBox/UsernameInput
@onready var continue_button: Button = $CenterContainer/Panel/Margin/VBox/ContinueButton
@onready var error_label: Label = $CenterContainer/Panel/Margin/VBox/ErrorLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SettingsManager.load_settings()
	if SettingsManager.has_username():
		_go_to_title_menu()
		return

	continue_button.disabled = true
	continue_button.pressed.connect(_on_continue_pressed)
	line_edit.text_changed.connect(_on_username_changed)
	line_edit.text_submitted.connect(_on_username_submitted)
	line_edit.grab_focus()


func _on_username_changed(new_text: String) -> void:
	var trimmed := new_text.strip_edges()
	continue_button.disabled = not _is_valid(trimmed)
	if trimmed.is_empty():
		error_label.text = "Enter a username (3-16, letters/numbers/underscore)."
	else:
		error_label.text = ""


func _on_username_submitted(_new_text: String) -> void:
	if continue_button.disabled:
		return
	_on_continue_pressed()


func _on_continue_pressed() -> void:
	var username := line_edit.text.strip_edges()
	if not _is_valid(username):
		error_label.text = "Invalid username. Use 3-16 letters, numbers, or underscore."
		return
	if not SettingsManager.set_username(username):
		error_label.text = "Could not save username. Try again."
		return
	_go_to_title_menu()


func _is_valid(name: String) -> bool:
	var regex := RegEx.new()
	if regex.compile(SettingsManager.USERNAME_REGEX) != OK:
		return false
	return regex.search(name) != null


func _go_to_title_menu() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://ui/title_menu.tscn")
