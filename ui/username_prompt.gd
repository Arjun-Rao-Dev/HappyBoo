extends Control

const KenneyUI = preload("res://ui/kenney_ui.gd")

@onready var background: ColorRect = $Background
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/Margin/VBox/Title
@onready var body_label: Label = $CenterContainer/Panel/Margin/VBox/Body
@onready var line_edit: LineEdit = $CenterContainer/Panel/Margin/VBox/UsernameInput
@onready var continue_button: Button = $CenterContainer/Panel/Margin/VBox/ContinueButton
@onready var error_label: Label = $CenterContainer/Panel/Margin/VBox/ErrorLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SettingsManager.load_settings()
	_apply_kenney_style()
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


func _apply_kenney_style() -> void:
	KenneyUI.apply_background(background)
	KenneyUI.apply_panel(panel, "Grey")
	KenneyUI.apply_title_label(title_label, 34)
	KenneyUI.apply_body_label(body_label, 18)
	KenneyUI.apply_input(line_edit)
	KenneyUI.apply_primary_button(continue_button)
	error_label.add_theme_font_size_override("font_size", 15)
