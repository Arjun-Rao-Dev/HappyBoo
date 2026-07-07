class_name KenneyUI
extends RefCounted

const PNG_ROOT := "res://ui/kenney_ui_pack/extracted/PNG"
const DEFAULT_SLICE := 18
const INPUT_SLICE := 16
const SKY_BLUE := Color(0.235, 0.627, 0.917, 1.0)
const TEXT_DARK := Color(0.12, 0.13, 0.18, 1.0)
const TEXT_MID := Color(0.18, 0.19, 0.25, 1.0)
const TEXT_LIGHT := Color(0.09, 0.1, 0.14, 1.0)
const TEXT_LIGHT_DISABLED := Color(0.28, 0.3, 0.38, 0.92)
const TEXT_PLACEHOLDER := Color(0.3, 0.32, 0.41, 0.95)

static var _textures: Dictionary = {}


static func texture(relative_path: String) -> Texture2D:
	var path := "%s/%s" % [PNG_ROOT, relative_path]
	if not _textures.has(path):
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) != OK:
			return null
		_textures[path] = ImageTexture.create_from_image(image)
	return _textures.get(path)


static func stylebox(relative_path: String, slice: int = DEFAULT_SLICE, content_margin: float = 16.0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture(relative_path)
	box.texture_margin_left = slice
	box.texture_margin_top = slice
	box.texture_margin_right = slice
	box.texture_margin_bottom = slice
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	box.content_margin_left = content_margin
	box.content_margin_top = content_margin * 0.8
	box.content_margin_right = content_margin
	box.content_margin_bottom = content_margin * 0.8
	return box


static func apply_background(rect: ColorRect) -> void:
	rect.color = SKY_BLUE


static func apply_title_label(label: Label, size: int = 36) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_DARK)


static func apply_heading(label: Label, size: int = 20) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_DARK)


static func apply_body_label(label: Label, size: int = 16) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", TEXT_MID)


static func apply_panel(panel: PanelContainer, color_name: String) -> void:
	panel.add_theme_stylebox_override("panel", stylebox("%s/Double/button_rectangle_depth_gradient.png" % color_name))


static func apply_card(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", stylebox("Grey/Double/button_rectangle_depth_gradient.png"))


static func apply_primary_button(button: Button) -> void:
	_apply_button_styles(button, "Green")


static func apply_secondary_button(button: Button) -> void:
	_apply_button_styles(button, "Grey")


static func apply_danger_button(button: Button) -> void:
	_apply_button_styles(button, "Red")


static func apply_info_button(button: Button) -> void:
	_apply_button_styles(button, "Blue")


static func apply_yellow_button(button: Button) -> void:
	_apply_button_styles(button, "Yellow")


static func _apply_button_styles(button: Button, color_name: String) -> void:
	button.custom_minimum_size.y = max(button.custom_minimum_size.y, 52.0)
	button.add_theme_stylebox_override("normal", stylebox("%s/Default/button_rectangle_depth_gradient.png" % color_name))
	button.add_theme_stylebox_override("hover", stylebox("%s/Double/button_rectangle_depth_gradient.png" % color_name))
	button.add_theme_stylebox_override("pressed", stylebox("%s/Default/button_rectangle_depth_flat.png" % color_name))
	button.add_theme_stylebox_override("disabled", stylebox("Grey/Default/button_rectangle_depth_flat.png"))
	button.add_theme_stylebox_override("focus", stylebox("%s/Double/button_rectangle_depth_border.png" % color_name))
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT_LIGHT)
	button.add_theme_color_override("font_hover_color", TEXT_LIGHT)
	button.add_theme_color_override("font_pressed_color", TEXT_LIGHT)
	button.add_theme_color_override("font_disabled_color", TEXT_LIGHT_DISABLED)
	button.add_theme_constant_override("h_separation", 8)


static func apply_input(control: Control) -> void:
	control.custom_minimum_size.y = max(control.custom_minimum_size.y, 48.0)
	control.add_theme_font_size_override("font_size", 16)
	control.add_theme_color_override("font_color", TEXT_DARK)
	if control is LineEdit:
		control.add_theme_color_override("font_placeholder_color", TEXT_PLACEHOLDER)
	control.add_theme_stylebox_override("normal", stylebox("Extra/Default/input_rectangle.png", INPUT_SLICE, 18.0))
	control.add_theme_stylebox_override("focus", stylebox("Extra/Default/input_outline_rectangle.png", INPUT_SLICE, 18.0))
	control.add_theme_stylebox_override("read_only", stylebox("Extra/Default/input_rectangle.png", INPUT_SLICE, 18.0))
	if control is OptionButton:
		var option := control as OptionButton
		option.add_theme_color_override("font_color", TEXT_DARK)
		option.add_theme_color_override("font_hover_color", TEXT_DARK)
		option.add_theme_color_override("font_pressed_color", TEXT_DARK)
		option.add_theme_color_override("font_focus_color", TEXT_DARK)
		option.add_theme_color_override("font_disabled_color", TEXT_LIGHT_DISABLED)
		option.add_theme_icon_override("arrow", texture("Extra/Default/icon_arrow_down_dark.png"))


static func apply_checkbox(checkbox: CheckBox, color_name: String = "Green") -> void:
	checkbox.add_theme_font_size_override("font_size", 16)
	checkbox.add_theme_color_override("font_color", TEXT_DARK)
	checkbox.add_theme_color_override("font_pressed_color", TEXT_DARK)
	checkbox.add_theme_color_override("font_hover_color", TEXT_DARK)
	checkbox.add_theme_color_override("font_hover_pressed_color", TEXT_DARK)
	checkbox.add_theme_color_override("font_disabled_color", TEXT_LIGHT_DISABLED)
	checkbox.add_theme_icon_override("checked", texture("%s/Default/check_square_color_checkmark.png" % color_name))
	checkbox.add_theme_icon_override("unchecked", texture("Grey/Default/check_square_grey_square.png"))
	checkbox.add_theme_icon_override("checked_disabled", texture("%s/Default/check_square_color_checkmark.png" % color_name))
	checkbox.add_theme_icon_override("unchecked_disabled", texture("Grey/Default/check_square_grey_square.png"))
	checkbox.add_theme_constant_override("check_v_offset", 0)


static func apply_slider(slider: HSlider, color_name: String = "Blue") -> void:
	slider.custom_minimum_size.y = max(slider.custom_minimum_size.y, 28.0)
	slider.add_theme_icon_override("grabber", texture("%s/Default/slide_hangle.png" % color_name))
	slider.add_theme_icon_override("grabber_highlight", texture("%s/Default/slide_hangle.png" % color_name))
	slider.add_theme_icon_override("grabber_disabled", texture("Grey/Default/slide_hangle.png"))
	slider.add_theme_stylebox_override("slider", stylebox("%s/Default/slide_horizontal_grey_section_wide.png" % color_name, 12, 0.0))
	slider.add_theme_stylebox_override("grabber_area", stylebox("%s/Default/slide_horizontal_color_section_wide.png" % color_name, 12, 0.0))
	slider.add_theme_stylebox_override("grabber_area_highlight", stylebox("%s/Default/slide_horizontal_color_section_wide.png" % color_name, 12, 0.0))


static func apply_list(item_list: ItemList) -> void:
	item_list.add_theme_font_size_override("font_size", 16)
	item_list.add_theme_color_override("font_color", TEXT_DARK)
	item_list.add_theme_color_override("font_selected_color", TEXT_DARK)
	item_list.add_theme_color_override("guide_color", Color(0, 0, 0, 0))
	item_list.add_theme_stylebox_override("panel", stylebox("Extra/Default/input_rectangle.png", INPUT_SLICE, 18.0))
	item_list.add_theme_stylebox_override("focus", stylebox("Extra/Default/input_outline_rectangle.png", INPUT_SLICE, 18.0))
	item_list.add_theme_stylebox_override("selected", stylebox("Blue/Default/button_rectangle_depth_gradient.png"))
	item_list.add_theme_stylebox_override("selected_focus", stylebox("Blue/Double/button_rectangle_depth_gradient.png"))


static func apply_scene_labels(root: Node) -> void:
	for child in root.get_children():
		if child is Label:
			var label := child as Label
			if label.has_theme_color_override("font_color"):
				pass
			elif label.name.to_lower().contains("title"):
				apply_title_label(label, 34)
			elif label.name.to_lower().contains("subtitle") or label.name.to_lower().contains("body") or label.name.to_lower().contains("status"):
				apply_body_label(label)
			else:
				apply_heading(label)
		elif child is LineEdit or child is OptionButton:
			apply_input(child)
		elif child is CheckBox:
			apply_checkbox(child)
		elif child is HSlider:
			apply_slider(child)
		elif child is ItemList:
			apply_list(child)
		elif child is Button:
			apply_primary_button(child)
		if child.get_child_count() > 0:
			apply_scene_labels(child)
