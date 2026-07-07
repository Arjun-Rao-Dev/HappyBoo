extends PanelContainer

const KenneyUI = preload("res://ui/kenney_ui.gd")

signal closed

const ACTION_LABELS := {
	"move_left": "Move Left",
	"move_right": "Move Right",
	"move_up": "Move Up",
	"move_down": "Move Down",
	"throw_bomb": "Throw Bomb",
	"pause": "Pause"
}

var _capture_action: StringName = &""
var _action_buttons: Dictionary = {}

@onready var title_label: Label = $Margin/VBox/Title
@onready var audio_title: Label = $Margin/VBox/AudioTitle
@onready var display_title: Label = $Margin/VBox/DisplayTitle
@onready var gameplay_title: Label = $Margin/VBox/GameplayTitle
@onready var controls_title: Label = $Margin/VBox/ControlsTitle
@onready var master_slider: HSlider = $Margin/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Margin/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Margin/VBox/SfxRow/SfxSlider
@onready var fullscreen_check: CheckBox = $Margin/VBox/FullscreenCheck
@onready var tutorial_button: Button = $Margin/VBox/TutorialRow/TutorialButton
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var close_button: Button = $Margin/VBox/BottomRow/CloseButton
@onready var reset_button: Button = $Margin/VBox/BottomRow/ResetBindingsButton
@onready var controls_container: VBoxContainer = $Margin/VBox/ControlsContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	close_button.pressed.connect(_on_close_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	master_slider.value_changed.connect(_on_audio_slider_changed)
	music_slider.value_changed.connect(_on_audio_slider_changed)
	sfx_slider.value_changed.connect(_on_audio_slider_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	tutorial_button.pressed.connect(_on_tutorial_pressed)
	_build_controls_rows()
	_apply_kenney_style()
	refresh()


func show_panel() -> void:
	_capture_action = &""
	refresh()
	status_label.text = ""
	visible = true
	close_button.grab_focus()


func hide_panel() -> void:
	_capture_action = &""
	visible = false
	status_label.text = ""


func refresh() -> void:
	var settings: Dictionary = SettingsManager.load_settings()
	var audio: Dictionary = settings.get("audio", {})
	var display: Dictionary = settings.get("display", {})

	master_slider.set_value_no_signal(float(audio.get("master_db", 0.0)))
	music_slider.set_value_no_signal(float(audio.get("music_db", -2.0)))
	sfx_slider.set_value_no_signal(float(audio.get("sfx_db", 0.0)))
	fullscreen_check.set_pressed_no_signal(bool(display.get("fullscreen", false)))
	_update_action_button_texts()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if _capture_action != &"":
		if event is InputEventKey and event.pressed and not event.echo:
			var event_key := event as InputEventKey
			if event_key.physical_keycode == KEY_ESCAPE:
				_capture_action = &""
				status_label.text = "Rebind canceled."
				_update_action_button_texts()
				get_viewport().set_input_as_handled()
				return

			var success := SettingsManager.rebind_action(_capture_action, event_key)
			if success:
				status_label.text = "Bound %s to %s." % [ACTION_LABELS.get(String(_capture_action), String(_capture_action)), OS.get_keycode_string(event_key.physical_keycode)]
			else:
				status_label.text = "Binding conflict or invalid key."
			_capture_action = &""
			_update_action_button_texts()
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("pause"):
		hide_panel()
		emit_signal("closed")
		get_viewport().set_input_as_handled()


func _build_controls_rows() -> void:
	for child in controls_container.get_children():
		child.queue_free()
	_action_buttons.clear()

	for action_name in SettingsManager.TRACKED_ACTIONS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var label := Label.new()
		label.text = ACTION_LABELS.get(String(action_name), String(action_name))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var button := Button.new()
		button.custom_minimum_size = Vector2(190.0, 34.0)
		button.pressed.connect(_on_action_bind_pressed.bind(action_name))
		row.add_child(button)

		controls_container.add_child(row)
		_action_buttons[action_name] = button
		KenneyUI.apply_heading(label, 15)
		KenneyUI.apply_secondary_button(button)


func _update_action_button_texts() -> void:
	for action_name in _action_buttons.keys():
		var button: Button = _action_buttons[action_name]
		if action_name == _capture_action:
			button.text = "Press key..."
			continue
		button.text = SettingsManager.get_action_binding_text(action_name)


func _on_action_bind_pressed(action_name: StringName) -> void:
	_capture_action = action_name
	status_label.text = "Press a key for %s (Esc to cancel)." % ACTION_LABELS.get(String(action_name), String(action_name))
	_update_action_button_texts()


func _on_audio_slider_changed(_value: float) -> void:
	_save_from_controls()


func _on_fullscreen_toggled(_enabled: bool) -> void:
	_save_from_controls()


func _save_from_controls() -> void:
	var payload := SettingsManager.get_settings_snapshot()
	payload["audio"] = {
		"master_db": master_slider.value,
		"music_db": music_slider.value,
		"sfx_db": sfx_slider.value
	}
	payload["display"] = {
		"fullscreen": fullscreen_check.button_pressed
	}
	SettingsManager.apply_settings(payload)
	SettingsManager.save_settings(payload)


func _on_reset_pressed() -> void:
	SettingsManager.reset_bindings_to_default()
	status_label.text = "Bindings reset to defaults."
	_update_action_button_texts()


func _on_close_pressed() -> void:
	hide_panel()
	emit_signal("closed")


func _on_tutorial_pressed() -> void:
	if not SettingsManager.reset_tutorial_progress():
		status_label.text = "Could not reset tutorial."
		return
	status_label.text = "Tutorial will show on the next single-player run."


func _apply_kenney_style() -> void:
	KenneyUI.apply_panel(self, "Green")
	KenneyUI.apply_title_label(title_label, 30)
	KenneyUI.apply_heading(audio_title, 18)
	KenneyUI.apply_heading(display_title, 18)
	KenneyUI.apply_heading(gameplay_title, 18)
	KenneyUI.apply_heading(controls_title, 18)
	KenneyUI.apply_scene_labels($Margin/VBox)
	KenneyUI.apply_slider(master_slider, "Blue")
	KenneyUI.apply_slider(music_slider, "Blue")
	KenneyUI.apply_slider(sfx_slider, "Blue")
	KenneyUI.apply_checkbox(fullscreen_check, "Green")
	KenneyUI.apply_primary_button(tutorial_button)
	KenneyUI.apply_secondary_button(reset_button)
	KenneyUI.apply_secondary_button(close_button)
	KenneyUI.apply_body_label(status_label, 15)
