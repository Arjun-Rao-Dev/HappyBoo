extends CanvasLayer

signal resume_requested
signal save_requested
signal quit_to_title_requested

@onready var panel: PanelContainer = $Center/PausePanel
@onready var options_panel = $OptionsPanel
@onready var resume_button: Button = $Center/PausePanel/Margin/VBox/ResumeButton
@onready var save_button: Button = $Center/PausePanel/Margin/VBox/SaveButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	save_button.pressed.connect(_on_save_pressed)
	$Center/PausePanel/Margin/VBox/OptionsButton.pressed.connect(_on_options_pressed)
	$Center/PausePanel/Margin/VBox/QuitButton.pressed.connect(_on_quit_pressed)
	options_panel.closed.connect(_on_options_closed)


func open_menu() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	panel.visible = true
	options_panel.hide_panel()
	resume_button.grab_focus()


func close_menu() -> void:
	options_panel.hide_panel()
	panel.visible = true
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		if options_panel.visible:
			options_panel.hide_panel()
			panel.visible = true
		else:
			emit_signal("resume_requested")
		get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	emit_signal("resume_requested")


func _on_save_pressed() -> void:
	emit_signal("save_requested")


func _on_options_pressed() -> void:
	panel.visible = false
	options_panel.show_panel()


func _on_options_closed() -> void:
	options_panel.hide_panel()
	panel.visible = true
	resume_button.grab_focus()


func _on_quit_pressed() -> void:
	emit_signal("quit_to_title_requested")


func set_save_enabled(enabled: bool) -> void:
	save_button.disabled = not enabled
	save_button.visible = enabled
