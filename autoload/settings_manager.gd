extends Node

const SETTINGS_PATH := "user://settings.json"
const SETTINGS_VERSION := 1
const USERNAME_REGEX := "^[A-Za-z0-9_]{3,16}$"
const CONTROL_SCHEME_KEYBOARD_MOUSE := "keyboard_mouse"
const CONTROL_SCHEME_TOUCHSCREEN := "touchscreen"
const TRACKED_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_up",
	&"move_down",
	&"throw_bomb",
	&"pause"
]

var _settings_cache: Dictionary = {}
var _pending_start_scene_path := "res://survivors_game.tscn"
var _default_bindings: Dictionary = {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_up": KEY_W,
	"move_down": KEY_S,
	"throw_bomb": KEY_Z,
	"pause": KEY_ESCAPE
}


func _ready() -> void:
	_ensure_actions_exist()
	_settings_cache = load_settings()


func load_settings() -> Dictionary:
	var settings: Dictionary = _default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				settings = _merge_settings(settings, parsed)

	apply_settings(settings)
	_settings_cache = settings
	return settings.duplicate(true)


func apply_settings(settings: Dictionary) -> void:
	_apply_audio_settings(settings.get("audio", {}))
	_apply_display_settings(settings.get("display", {}))
	_apply_control_settings(settings.get("controls", {}))


func save_settings(settings: Dictionary) -> bool:
	var normalized := _merge_settings(_default_settings(), settings)
	normalized["version"] = SETTINGS_VERSION
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(normalized, "\t"))
	_settings_cache = normalized
	return true


func rebind_action(action: StringName, event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	if not TRACKED_ACTIONS.has(action):
		return false

	var key_event := event as InputEventKey
	if key_event.physical_keycode == KEY_NONE:
		return false

	for other_action in TRACKED_ACTIONS:
		if other_action == action:
			continue
		if get_first_physical_keycode(other_action) == key_event.physical_keycode:
			return false

	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)

	var new_event := InputEventKey.new()
	new_event.physical_keycode = key_event.physical_keycode
	new_event.keycode = key_event.keycode
	InputMap.action_add_event(action, new_event)

	_save_current_settings_snapshot()
	return true


func reset_bindings_to_default() -> void:
	for action_name in TRACKED_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)

		var event := InputEventKey.new()
		event.physical_keycode = _default_bindings.get(String(action_name), KEY_NONE)
		InputMap.action_add_event(action_name, event)

	_save_current_settings_snapshot()


func get_settings_snapshot() -> Dictionary:
	return {
		"version": SETTINGS_VERSION,
		"audio": {
			"master_db": _get_bus_volume("Master", 0.0),
			"music_db": _get_bus_volume("Music", 0.0),
			"sfx_db": _get_bus_volume("SFX", 0.0)
		},
		"display": {
			"fullscreen": DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		},
		"controls": _extract_controls_snapshot(),
		"profile": {
			"username": get_username(),
			"control_scheme": get_control_scheme()
		}
	}


func has_username() -> bool:
	return _is_valid_username(get_username())


func get_username() -> String:
	var profile: Dictionary = _settings_cache.get("profile", {})
	return String(profile.get("username", ""))


func get_control_scheme() -> String:
	var profile: Dictionary = _settings_cache.get("profile", {})
	var scheme := String(profile.get("control_scheme", CONTROL_SCHEME_KEYBOARD_MOUSE))
	if scheme != CONTROL_SCHEME_TOUCHSCREEN:
		return CONTROL_SCHEME_KEYBOARD_MOUSE
	return scheme


func is_touchscreen_controls_enabled() -> bool:
	return get_control_scheme() == CONTROL_SCHEME_TOUCHSCREEN


func set_control_scheme(scheme: String) -> bool:
	var normalized := CONTROL_SCHEME_TOUCHSCREEN if scheme == CONTROL_SCHEME_TOUCHSCREEN else CONTROL_SCHEME_KEYBOARD_MOUSE
	var snapshot := get_settings_snapshot()
	var profile: Dictionary = snapshot.get("profile", {})
	profile["control_scheme"] = normalized
	snapshot["profile"] = profile
	apply_settings(snapshot)
	return save_settings(snapshot)


func queue_start_scene(path: String) -> void:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		_pending_start_scene_path = "res://survivors_game.tscn"
		return
	_pending_start_scene_path = trimmed


func consume_start_scene() -> String:
	var scene_path := _pending_start_scene_path
	_pending_start_scene_path = "res://survivors_game.tscn"
	return scene_path


func set_username(name: String) -> bool:
	var trimmed := name.strip_edges()
	if not _is_valid_username(trimmed):
		return false
	var snapshot := get_settings_snapshot()
	var profile: Dictionary = snapshot.get("profile", {})
	profile["username"] = trimmed
	snapshot["profile"] = profile
	apply_settings(snapshot)
	return save_settings(snapshot)


func get_action_binding_text(action: StringName) -> String:
	var keycode := get_first_physical_keycode(action)
	if keycode == KEY_NONE:
		return "Unbound"
	return OS.get_keycode_string(keycode)


func get_first_physical_keycode(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


func _ensure_actions_exist() -> void:
	for action_name in TRACKED_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

	for action_name in TRACKED_ACTIONS:
		if InputMap.action_get_events(action_name).is_empty():
			var event := InputEventKey.new()
			event.physical_keycode = _default_bindings.get(String(action_name), KEY_NONE)
			InputMap.action_add_event(action_name, event)

	for action_name in TRACKED_ACTIONS:
		var detected := get_first_physical_keycode(action_name)
		if detected != KEY_NONE:
			_default_bindings[String(action_name)] = detected


func _default_settings() -> Dictionary:
	return {
		"version": SETTINGS_VERSION,
		"audio": {
			"master_db": 0.0,
			"music_db": -2.0,
			"sfx_db": 0.0
		},
		"display": {
			"fullscreen": false
		},
		"profile": {
			"username": "",
			"control_scheme": CONTROL_SCHEME_KEYBOARD_MOUSE
		},
		"controls": _default_bindings.duplicate(true)
	}


func _merge_settings(base: Dictionary, incoming: Dictionary) -> Dictionary:
	var merged: Dictionary = base.duplicate(true)
	for section in ["audio", "display", "controls", "profile"]:
		var base_section: Dictionary = merged.get(section, {})
		var incoming_section: Variant = incoming.get(section, {})
		if incoming_section is Dictionary:
			for key in incoming_section.keys():
				base_section[key] = incoming_section[key]
		merged[section] = base_section
	return merged


func _apply_audio_settings(audio_settings: Dictionary) -> void:
	_set_bus_volume("Master", float(audio_settings.get("master_db", 0.0)))
	_set_bus_volume("Music", float(audio_settings.get("music_db", -2.0)))
	_set_bus_volume("SFX", float(audio_settings.get("sfx_db", 0.0)))


func _apply_display_settings(display_settings: Dictionary) -> void:
	var wants_fullscreen := bool(display_settings.get("fullscreen", false))
	if wants_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _apply_control_settings(control_settings: Dictionary) -> void:
	for action_name in TRACKED_ACTIONS:
		var action_key := String(action_name)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)

		var keycode := int(control_settings.get(action_key, _default_bindings.get(action_key, KEY_NONE)))
		if keycode == KEY_NONE:
			continue
		var key_event := InputEventKey.new()
		key_event.physical_keycode = keycode
		InputMap.action_add_event(action_name, key_event)


func _extract_controls_snapshot() -> Dictionary:
	var controls := {}
	for action_name in TRACKED_ACTIONS:
		controls[String(action_name)] = int(get_first_physical_keycode(action_name))
	return controls


func _save_current_settings_snapshot() -> void:
	var snapshot := get_settings_snapshot()
	apply_settings(snapshot)
	save_settings(snapshot)


func _is_valid_username(name: String) -> bool:
	if name != name.strip_edges():
		return false
	if name.length() < 3 or name.length() > 16:
		return false
	var regex := RegEx.new()
	if regex.compile(USERNAME_REGEX) != OK:
		return false
	return regex.search(name) != null


func _set_bus_volume(bus_name: String, db: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		return
	AudioServer.set_bus_volume_db(bus_idx, db)


func _get_bus_volume(bus_name: String, fallback: float) -> float:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		return fallback
	return AudioServer.get_bus_volume_db(bus_idx)
