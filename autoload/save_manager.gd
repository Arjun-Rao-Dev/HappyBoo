extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var _pending_continue_run: Dictionary = {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_run(run_state: Dictionary) -> bool:
	if run_state.is_empty():
		return false

	var payload := {
		"version": SAVE_VERSION,
		"saved_at_unix": Time.get_unix_time_from_system(),
		"run_state": run_state,
		"settings": SettingsManager.get_settings_snapshot()
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	return true


func load_run() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {
			"ok": false,
			"status": "missing",
			"run_state": {}
		}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"status": "open_failed",
			"run_state": {}
		}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {
			"ok": false,
			"status": "invalid_json",
			"run_state": {}
		}

	var data := parsed as Dictionary
	if int(data.get("version", -1)) != SAVE_VERSION:
		return {
			"ok": false,
			"status": "version_mismatch",
			"run_state": {}
		}

	var run_state: Variant = data.get("run_state", {})
	if not (run_state is Dictionary):
		return {
			"ok": false,
			"status": "invalid_run_state",
			"run_state": {}
		}

	var validated := _validate_run_state(run_state)
	if validated.is_empty():
		return {
			"ok": false,
			"status": "invalid_run_state",
			"run_state": {}
		}

	var settings: Variant = data.get("settings", {})
	if settings is Dictionary:
		SettingsManager.apply_settings(SettingsManager.load_settings())
		SettingsManager.apply_settings(settings)
		SettingsManager.save_settings(settings)

	return {
		"ok": true,
		"status": "ok",
		"run_state": validated
	}


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func queue_continue_run(run_state: Dictionary) -> void:
	_pending_continue_run = run_state.duplicate(true)


func consume_pending_continue_run() -> Dictionary:
	var copied := _pending_continue_run.duplicate(true)
	_pending_continue_run.clear()
	return copied


func clear_pending_continue_run() -> void:
	_pending_continue_run.clear()


func _validate_run_state(run_state: Dictionary) -> Dictionary:
	var result := {}

	if not run_state.has("score"):
		return {}
	if not run_state.has("current_health"):
		return {}
	if not run_state.has("max_health"):
		return {}
	if not run_state.has("player_position"):
		return {}
	if not run_state.has("elapsed_run_time_sec"):
		return {}

	var position = run_state.get("player_position", {})
	if not (position is Dictionary):
		return {}
	if not position.has("x") or not position.has("y"):
		return {}

	result["score"] = int(run_state.get("score", 0))
	result["current_health"] = float(run_state.get("current_health", 0.0))
	result["max_health"] = float(run_state.get("max_health", 100.0))
	result["player_position"] = {
		"x": float(position.get("x", 0.0)),
		"y": float(position.get("y", 0.0))
	}
	result["elapsed_run_time_sec"] = float(run_state.get("elapsed_run_time_sec", 0.0))

	if result["max_health"] <= 0.0:
		return {}
	result["current_health"] = clampf(result["current_health"], 0.0, result["max_health"])
	result["elapsed_run_time_sec"] = maxf(result["elapsed_run_time_sec"], 0.0)
	return result
