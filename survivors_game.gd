extends Node2D

@export var tree_scene: PackedScene = preload("res://pine_tree.tscn")
@export var mob_scene: PackedScene = preload("res://slime.tscn")
@export var medium_monster_scene: PackedScene = preload("res://monsters/monster_bee.tscn")
@export var heavy_monster_scene: PackedScene = preload("res://monsters/monster_spike.tscn")
@export var food_scene: PackedScene = preload("res://food/food_pickup.tscn")
@export var chunk_size: float = 900.0
@export var active_chunk_radius: int = 2
@export var trees_per_chunk: int = 10
@export var mobs_per_chunk: int = 1
@export var foods_per_chunk: int = 2
@export var mob_spawn_chance_per_chunk: float = 0.35
@export var food_spawn_chance_per_chunk: float = 0.45
@export var min_tree_distance_from_player: float = 160.0
@export var min_mob_distance_from_player: float = 300.0
@export var min_food_distance_from_player: float = 140.0
@export var spawn_attempts_per_tree: int = 8
@export var spawn_attempts_per_mob: int = 8
@export var spawn_attempts_per_food: int = 8
@export var score_for_medium_monsters: int = 12
@export var score_for_heavy_monsters: int = 35

var spawned_chunks: Dictionary = {}
var score: int = 0
var run_start_time_ms: int = 0

@onready var player = $Player
@onready var game_over_ui: CanvasLayer = $GameOverUI
@onready var restart_button: Button = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/RestartButton
@onready var quit_to_title_button: Button = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/QuitToTitleButton
@onready var score_label: Label = $HUD/TopLeftPanel/Margin/VBox/ScoreLabel
@onready var bomb_cooldown_ui = $HUD/TopLeftPanel/Margin/VBox/BombRow/BombCooldownUI
@onready var health_bar: ProgressBar = $HUD/TopLeftPanel/Margin/VBox/HealthBar
@onready var controls_hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/ControlsHintLabel
@onready var pause_menu = $PauseMenu
@onready var crosshair = $Crosshair
@onready var game_music: AudioStreamPlayer = $GameMusic
var hud_health_fill_style: StyleBoxFlat


func _ready() -> void:
	randomize()
	SettingsManager.load_settings()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	game_over_ui.visible = false
	game_over_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	crosshair.visible = true
	if game_music.stream is AudioStreamMP3:
		(game_music.stream as AudioStreamMP3).loop = true
	if not game_music.playing:
		game_music.play()
	var existing_fill: StyleBox = health_bar.get_theme_stylebox("fill")
	if existing_fill is StyleBoxFlat:
		hud_health_fill_style = (existing_fill as StyleBoxFlat).duplicate()
	else:
		hud_health_fill_style = StyleBoxFlat.new()
	health_bar.add_theme_stylebox_override("fill", hud_health_fill_style)

	player.died.connect(_on_player_died)
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_player_health_changed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	quit_to_title_button.pressed.connect(_on_quit_to_title_pressed)
	pause_menu.resume_requested.connect(_on_pause_resume_requested)
	pause_menu.save_requested.connect(_on_pause_save_requested)
	pause_menu.quit_to_title_requested.connect(_on_quit_to_title_pressed)

	run_start_time_ms = Time.get_ticks_msec()
	_apply_continue_state_if_present()
	_update_score_label()
	_on_player_health_changed(player.get_current_health(), player.get_max_health())
	_update_controls_hint_label()
	_spawn_trees_around_player()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(_delta: float) -> void:
	_spawn_trees_around_player()


func _process(_delta: float) -> void:
	if player == null:
		return
	bomb_cooldown_ui.set_state(
		player.get_bomb_cooldown_remaining(),
		player.get_bomb_cooldown_total(),
		player.can_throw_bomb(),
		player.is_full_health()
	)
	_update_controls_hint_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			if pause_menu.visible:
				_on_pause_resume_requested()
			return
		if game_over_ui.visible:
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _apply_continue_state_if_present() -> void:
	var pending_state := SaveManager.consume_pending_continue_run()
	if pending_state.is_empty():
		return
	if not import_run_state(pending_state):
		score = 0
		run_start_time_ms = Time.get_ticks_msec()


func _open_pause_menu() -> void:
	get_tree().paused = true
	crosshair.visible = false
	game_music.stream_paused = true
	pause_menu.open_menu()


func _spawn_trees_around_player() -> void:
	if player == null:
		return

	var center_chunk := _world_to_chunk(player.global_position)
	for x in range(center_chunk.x - active_chunk_radius, center_chunk.x + active_chunk_radius + 1):
		for y in range(center_chunk.y - active_chunk_radius, center_chunk.y + active_chunk_radius + 1):
			var chunk := Vector2i(x, y)
			if spawned_chunks.has(chunk):
				continue
			_spawn_chunk(chunk)
			spawned_chunks[chunk] = true


func _spawn_chunk(chunk: Vector2i) -> void:
	var chunk_origin := Vector2(chunk.x * chunk_size, chunk.y * chunk_size)
	for _i in trees_per_chunk:
		var position_found := false
		var spawn_position := Vector2.ZERO
		for _attempt in spawn_attempts_per_tree:
			spawn_position = chunk_origin + Vector2(
				randf_range(0.0, chunk_size),
				randf_range(0.0, chunk_size)
			)
			if spawn_position.distance_to(player.global_position) >= min_tree_distance_from_player:
				position_found = true
				break
		if not position_found:
			continue
		var tree := tree_scene.instantiate()
		add_child(tree)
		tree.global_position = spawn_position

	if randf() <= mob_spawn_chance_per_chunk:
		var scaled_mob_count: int = mobs_per_chunk + min(int(score / 20), 4)
		for _i in scaled_mob_count:
			var mob_position_found := false
			var mob_spawn_position := Vector2.ZERO
			for _attempt in spawn_attempts_per_mob:
				mob_spawn_position = chunk_origin + Vector2(
					randf_range(0.0, chunk_size),
					randf_range(0.0, chunk_size)
				)
				if mob_spawn_position.distance_to(player.global_position) >= min_mob_distance_from_player:
					mob_position_found = true
					break
			if not mob_position_found:
				continue
			var mob := _pick_monster_scene_for_score().instantiate()
			add_child(mob)
			mob.global_position = mob_spawn_position

	if randf() <= food_spawn_chance_per_chunk:
		for _i in foods_per_chunk:
			var food_position_found := false
			var food_spawn_position := Vector2.ZERO
			for _attempt in spawn_attempts_per_food:
				food_spawn_position = chunk_origin + Vector2(
					randf_range(0.0, chunk_size),
					randf_range(0.0, chunk_size)
				)
				if food_spawn_position.distance_to(player.global_position) >= min_food_distance_from_player:
					food_position_found = true
					break
			if not food_position_found:
				continue
			var food := food_scene.instantiate()
			add_child(food)
			food.global_position = food_spawn_position


func _world_to_chunk(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / chunk_size)),
		int(floor(world_position.y / chunk_size))
	)


func _on_player_died() -> void:
	game_over_ui.visible = true
	crosshair.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_music.stream_paused = true
	get_tree().paused = true
	restart_button.grab_focus()


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	SaveManager.clear_pending_continue_run()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	crosshair.visible = true
	get_tree().reload_current_scene()


func _on_quit_to_title_pressed() -> void:
	get_tree().paused = false
	SaveManager.clear_pending_continue_run()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	crosshair.visible = false
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _on_pause_resume_requested() -> void:
	pause_menu.close_menu()
	get_tree().paused = false
	crosshair.visible = true
	game_music.stream_paused = false


func _on_pause_save_requested() -> void:
	SaveManager.save_run(export_run_state())


func _on_player_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	_update_hud_health_bar_color(current, maximum)


func add_score(points: int = 1) -> void:
	score += points
	_update_score_label()


func _update_score_label() -> void:
	score_label.text = "Score: %d" % score


func _update_controls_hint_label() -> void:
	var bomb_key := SettingsManager.get_action_binding_text(&"throw_bomb")
	var pause_key := SettingsManager.get_action_binding_text(&"pause")
	controls_hint_label.text = "Bomb: %s | Pause: %s" % [bomb_key, pause_key]


func _update_hud_health_bar_color(current: float, maximum: float) -> void:
	if hud_health_fill_style == null or maximum <= 0.0:
		return
	var health_ratio := clampf(current / maximum, 0.0, 1.0)
	var green := Color(0.55, 0.85, 0.33, 1.0)
	var yellow := Color(0.97, 0.88, 0.25, 1.0)
	var orange := Color(0.98, 0.58, 0.20, 1.0)
	var red := Color(0.90, 0.20, 0.20, 1.0)
	var health_color: Color

	if health_ratio >= 0.66:
		var t_high := inverse_lerp(0.66, 1.0, health_ratio)
		health_color = yellow.lerp(green, t_high)
	elif health_ratio >= 0.33:
		var t_mid := inverse_lerp(0.33, 0.66, health_ratio)
		health_color = orange.lerp(yellow, t_mid)
	else:
		var t_low := inverse_lerp(0.0, 0.33, health_ratio)
		health_color = red.lerp(orange, t_low)

	hud_health_fill_style.bg_color = health_color


func export_run_state() -> Dictionary:
	var elapsed := float(Time.get_ticks_msec() - run_start_time_ms) / 1000.0
	return {
		"score": score,
		"current_health": player.get_current_health(),
		"max_health": player.get_max_health(),
		"player_position": {
			"x": player.global_position.x,
			"y": player.global_position.y
		},
		"elapsed_run_time_sec": elapsed
	}


func import_run_state(state: Dictionary) -> bool:
	if not state.has("player_position"):
		return false
	var position_data = state.get("player_position", {})
	if not (position_data is Dictionary):
		return false
	if not position_data.has("x") or not position_data.has("y"):
		return false

	score = int(state.get("score", 0))
	player.global_position = Vector2(
		float(position_data.get("x", player.global_position.x)),
		float(position_data.get("y", player.global_position.y))
	)
	player.restore_from_run_state(
		float(state.get("current_health", player.get_current_health())),
		float(state.get("max_health", player.get_max_health()))
	)
	var elapsed := maxf(float(state.get("elapsed_run_time_sec", 0.0)), 0.0)
	run_start_time_ms = Time.get_ticks_msec() - int(elapsed * 1000.0)
	_update_score_label()
	return true


func _pick_monster_scene_for_score() -> PackedScene:
	if score >= score_for_heavy_monsters and randf() < 0.55:
		return heavy_monster_scene
	if score >= score_for_medium_monsters and randf() < 0.45:
		return medium_monster_scene
	return mob_scene
