extends PanelContainer

const KenneyUI = preload("res://ui/kenney_ui.gd")

signal closed

var _modifier_checks: Dictionary = {}

@onready var title_label: Label = $Margin/VBox/Title
@onready var intro_label: Label = $Margin/VBox/Intro
@onready var modifiers_container: VBoxContainer = $Margin/VBox/ModifiersContainer
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var reset_button: Button = $Margin/VBox/BottomRow/ResetButton
@onready var close_button: Button = $Margin/VBox/BottomRow/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_on_close_pressed)
	_build_modifier_rows()
	_apply_kenney_style()
	refresh()


func show_panel() -> void:
	refresh()
	status_label.text = ""
	visible = true
	close_button.grab_focus()


func hide_panel() -> void:
	visible = false
	status_label.text = ""


func refresh() -> void:
	var selected := SettingsManager.get_selected_modifiers()
	for modifier_id in _modifier_checks.keys():
		var checkbox: CheckBox = _modifier_checks[modifier_id]
		checkbox.set_pressed_no_signal(bool(selected.get(modifier_id, false)))
	_update_status()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _build_modifier_rows() -> void:
	for child in modifiers_container.get_children():
		child.queue_free()
	_modifier_checks.clear()

	for modifier in SettingsManager.get_modifier_catalog():
		var modifier_id := String(modifier.get("id", ""))
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 12)

		var checkbox := CheckBox.new()
		checkbox.custom_minimum_size = Vector2(220.0, 44.0)
		checkbox.text = String(modifier.get("name", modifier_id.capitalize()))
		checkbox.toggled.connect(_on_modifier_toggled.bind(modifier_id))
		row.add_child(checkbox)

		var description := Label.new()
		description.text = String(modifier.get("description", ""))
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(description)

		modifiers_container.add_child(row)
		_modifier_checks[modifier_id] = checkbox
		KenneyUI.apply_checkbox(checkbox, "Yellow")
		KenneyUI.apply_body_label(description, 15)


func _on_modifier_toggled(enabled: bool, modifier_id: String) -> void:
	SettingsManager.set_modifier_enabled(modifier_id, enabled)
	_update_status()


func _on_reset_pressed() -> void:
	SettingsManager.reset_selected_modifiers()
	refresh()
	status_label.text = "Modifiers reset."


func _on_close_pressed() -> void:
	hide_panel()
	emit_signal("closed")


func _update_status() -> void:
	var selected := SettingsManager.get_selected_modifiers()
	if selected.is_empty():
		status_label.text = "No modifiers selected. New runs use normal rules."
	else:
		status_label.text = "%d modifier%s selected. They apply to the next new single-player run." % [
			selected.size(),
			"" if selected.size() == 1 else "s"
		]


func _apply_kenney_style() -> void:
	KenneyUI.apply_panel(self, "Blue")
	KenneyUI.apply_title_label(title_label, 30)
	KenneyUI.apply_body_label(intro_label, 16)
	KenneyUI.apply_body_label(status_label, 15)
	KenneyUI.apply_secondary_button(reset_button)
	KenneyUI.apply_primary_button(close_button)
