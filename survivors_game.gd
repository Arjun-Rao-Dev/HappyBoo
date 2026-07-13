extends Node2D

const REMOTE_PLAYER_SCENE: PackedScene = preload("res://multiplayer/remote_player.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://pistol/projectile.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
const RACE_CAR_PICKUP_SCENE: PackedScene = preload("res://powerups/race_car_pickup.tscn")
const MULTIPLAYER_STATE_SEND_INTERVAL := 0.05
const MULTIPLAYER_MOB_STATE_SEND_INTERVAL := 0.12
const ONLINE_MOB_SPAWN_CHANCE_PER_CHUNK := 0.75
const CHAT_MAX_LENGTH := 120
const CHAT_MAX_VISIBLE_MESSAGES := 6
const CHAT_MESSAGE_VISIBLE_SECONDS := 8.0
const CHAT_SEND_COOLDOWN_SECONDS := 0.5
const FAST_ENEMY_SPEED_MULTIPLIER := 1.5
const RACE_CAR_DURATION_SECONDS := 10.0
const RACE_CAR_RADIAL_FIRE_INTERVAL := 0.5
const RACE_CAR_RADIAL_SHOTS := 12
const RACE_CAR_PROJECTILE_DAMAGE := 1.0
const RACE_CAR_PROJECTILE_SPEED := 1350.0
const RACE_CAR_MIN_SCORE := 40

@export var tree_scene: PackedScene = preload("res://pine_tree.tscn")
@export var mob_scene: PackedScene = preload("res://slime.tscn")
@export var medium_monster_scene: PackedScene = preload("res://monsters/monster_bee.tscn")
@export var heavy_monster_scene: PackedScene = preload("res://monsters/monster_spike.tscn")
@export var food_scene: PackedScene = preload("res://food/food_pickup.tscn")
@export var race_car_spawn_chance_per_chunk: float = 0.015
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
@export var min_powerup_distance_from_player: float = 180.0
@export var spawn_attempts_per_tree: int = 8
@export var spawn_attempts_per_mob: int = 8
@export var spawn_attempts_per_food: int = 8
@export var spawn_attempts_per_powerup: int = 8
@export var score_for_medium_monsters: int = 12
@export var score_for_heavy_monsters: int = 35
const TREE_ROTATION_VARIATION := 0.08
const TUTORIAL_KEYBOARD_STEPS: Array[String] = [
	"Use WASD or the arrow keys to move around the map.",
	"Aim with the mouse. Your equipped weapon auto-fires once the headstart ends.",
	"Pick up food to heal 20 health. Staying healthy also lets you use bombs.",
	"Bombs only work at full health. Press Z to throw one toward your cursor.",
	"Goal: stay alive, clear slimes, and keep your score climbing."
]

var spawned_chunks: Dictionary = {}
var score: int = 0
var gun_score: int = 0
var run_start_time_ms: int = 0
var coins_awarded_this_run := false
var tutorial_active := false
var tutorial_steps: Array[String] = []
var tutorial_step_index := 0
var online_run := false
var online_is_host := false
var online_role_assigned := false
var multiplayer_send_accumulator := 0.0
var multiplayer_mob_send_accumulator := 0.0
var remote_players: Dictionary = {}
var network_mobs: Dictionary = {}
var network_foods: Dictionary = {}
var online_host_entity_chunks: Dictionary = {}
var next_network_mob_id := 1
var next_network_food_id := 1
var chat_messages: Array[Dictionary] = []
var chat_input_active := false
var chat_send_cooldown := 0.0
var active_modifiers: Dictionary = {}
var weapon_upgrade_level := 0
var next_weapon_upgrade_score := 10
var next_weapon_upgrade_gap := 20
var notification_seconds_left := 0.0
var race_car_seconds_left := 0.0
var race_car_fire_accumulator := 0.0
var chat_panel: PanelContainer
var chat_log_label: Label
var chat_input: LineEdit

@onready var player = $Player
@onready var game_over_ui: CanvasLayer = $GameOverUI
@onready var game_over_label: Label = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/GameOverLabel
@onready var game_over_rewards_label: Label = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/RewardsLabel
@onready var restart_button: Button = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/RestartButton
@onready var quit_to_title_button: Button = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/QuitToTitleButton
@onready var score_label: Label = $HUD/TopLeftPanel/Margin/VBox/ScoreLabel
@onready var weapon_label: Label = $HUD/TopLeftPanel/Margin/VBox/WeaponLabel
@onready var bomb_cooldown_ui = $HUD/TopLeftPanel/Margin/VBox/BombRow/BombCooldownUI
@onready var bomb_label: Label = $HUD/TopLeftPanel/Margin/VBox/BombRow/BombLabel
@onready var health_bar: ProgressBar = $HUD/TopLeftPanel/Margin/VBox/HealthBar
@onready var controls_hint_label: Label = $HUD/TopLeftPanel/Margin/VBox/ControlsHintLabel
@onready var modifier_summary_label: Label = $HUD/TopLeftPanel/Margin/VBox/ModifierSummaryLabel
@onready var multiplayer_status_label: Label = $HUD/TopLeftPanel/Margin/VBox/MultiplayerStatusLabel
@onready var pause_menu = $PauseMenu
@onready var crosshair = $Crosshair
@onready var game_music: AudioStreamPlayer = $GameMusic
@onready var tutorial_ui: CanvasLayer = $TutorialUI
@onready var tutorial_body_label: Label = $TutorialUI/TutorialPanel/CenterBox/Panel/Margin/VBox/Body
@onready var tutorial_progress_label: Label = $TutorialUI/TutorialPanel/CenterBox/Panel/Margin/VBox/Progress
@onready var tutorial_next_button: Button = $TutorialUI/TutorialPanel/CenterBox/Panel/Margin/VBox/ButtonRow/NextButton
@onready var tutorial_skip_button: Button = $TutorialUI/TutorialPanel/CenterBox/Panel/Margin/VBox/ButtonRow/SkipButton
@onready var notification_label: Label = $HUD/NotificationLabel
var hud_health_fill_style: StyleBoxFlat


func _ready() -> void:
	randomize()
	_ensure_scene_defaults()
	SettingsManager.load_settings()
	active_modifiers = SettingsManager.consume_pending_run_modifiers()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	game_over_ui.visible = false
	game_over_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	tutorial_ui.visible = false
	tutorial_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	game_over_label.text = "GAME OVER"
	restart_button.visible = true
	restart_button.text = "New Run"
	quit_to_title_button.text = "Quit to Title"
	crosshair.visible = true
	if game_music.stream is AudioStreamMP3:
		(game_music.stream as AudioStreamMP3).loop = true
	if not game_music.finished.is_connected(_on_game_music_finished):
		game_music.finished.connect(_on_game_music_finished)
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
	pause_menu.set_save_enabled(not _has_active_modifiers())
	tutorial_next_button.pressed.connect(_on_tutorial_next_pressed)
	tutorial_skip_button.pressed.connect(_on_tutorial_skip_pressed)
	_build_chat_ui()

	run_start_time_ms = Time.get_ticks_msec()
	_apply_run_modifiers()
	_apply_continue_state_if_present()
	_update_score_label()
	_update_weapon_label()
	_on_player_health_changed(player.get_current_health(), player.get_max_health())
	_update_controls_hint_label()
	_update_modifier_summary_label()
	_setup_multiplayer_if_requested()
	_maybe_start_first_run_tutorial()
	_spawn_trees_around_player()


func _maybe_start_first_run_tutorial() -> void:
	if SettingsManager.is_tutorial_completed():
		return
	tutorial_steps = TUTORIAL_KEYBOARD_STEPS
	tutorial_step_index = 0
	_show_tutorial_step()


func _show_tutorial_step() -> void:
	if tutorial_steps.is_empty():
		return
	tutorial_active = true
	get_tree().paused = true
	tutorial_ui.visible = true
	game_music.stream_paused = true
	tutorial_body_label.text = tutorial_steps[tutorial_step_index]
	tutorial_progress_label.text = "Tip %d of %d" % [tutorial_step_index + 1, tutorial_steps.size()]
	tutorial_next_button.text = "Finish" if tutorial_step_index == tutorial_steps.size() - 1 else "Next"
	tutorial_next_button.grab_focus()


func _close_tutorial(mark_complete: bool) -> void:
	tutorial_active = false
	tutorial_ui.visible = false
	get_tree().paused = false
	if mark_complete:
		SettingsManager.mark_tutorial_completed(true)
	crosshair.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	game_music.stream_paused = false


func _on_tutorial_next_pressed() -> void:
	if tutorial_step_index >= tutorial_steps.size() - 1:
		_close_tutorial(true)
		return
	tutorial_step_index += 1
	_show_tutorial_step()


func _on_tutorial_skip_pressed() -> void:
	_close_tutorial(true)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if online_run:
		if MultiplayerClient.remote_player_state_received.is_connected(_on_remote_player_state_received):
			MultiplayerClient.remote_player_state_received.disconnect(_on_remote_player_state_received)
		if MultiplayerClient.remote_player_left.is_connected(_on_remote_player_left):
			MultiplayerClient.remote_player_left.disconnect(_on_remote_player_left)
		if MultiplayerClient.connection_status_changed.is_connected(_on_multiplayer_connection_status_changed):
			MultiplayerClient.connection_status_changed.disconnect(_on_multiplayer_connection_status_changed)
		if MultiplayerClient.host_status_changed.is_connected(_on_multiplayer_host_status_changed):
			MultiplayerClient.host_status_changed.disconnect(_on_multiplayer_host_status_changed)
		if MultiplayerClient.world_message_received.is_connected(_on_multiplayer_world_message_received):
			MultiplayerClient.world_message_received.disconnect(_on_multiplayer_world_message_received)
		MultiplayerClient.disconnect_from_server()


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
	bomb_label.text = "Bombs disabled" if _is_modifier_enabled("disable_bombs") else "Bomb"
	_update_controls_hint_label()
	_process_notification(_delta)
	_process_race_car_mode(_delta)
	_process_multiplayer_state(_delta)
	_process_chat(_delta)


func _unhandled_input(event: InputEvent) -> void:
	if _handle_chat_input_event(event):
		get_viewport().set_input_as_handled()
		return
	if tutorial_active:
		return
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			if pause_menu.visible:
				_on_pause_resume_requested()
			return
		if game_over_ui.visible:
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _handle_chat_input_event(event: InputEvent) -> bool:
	if not online_run or not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	if chat_input_active:
		if key_event.keycode == KEY_ESCAPE:
			_set_chat_input_active(false)
			return true
		return false
	if tutorial_active or game_over_ui.visible or get_tree().paused:
		return false
	if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
		_set_chat_input_active(true)
		return true
	return false


func _apply_continue_state_if_present() -> void:
	var pending_state := SaveManager.consume_pending_continue_run()
	if pending_state.is_empty():
		return
	if not import_run_state(pending_state):
		score = 0
		gun_score = 0
		run_start_time_ms = Time.get_ticks_msec()


func _apply_run_modifiers() -> void:
	if active_modifiers.is_empty():
		return
	if _is_modifier_enabled("disable_bombs") and player.has_method("set_bombs_disabled"):
		player.set_bombs_disabled(true)
	if _is_modifier_enabled("disable_pistol") and player.has_method("set_pistol_disabled"):
		player.set_pistol_disabled(true)
	if _is_modifier_enabled("no_headstart"):
		if player.get("start_invulnerable_seconds") != null:
			player.set("start_invulnerable_seconds", 0.0)
	if _is_modifier_enabled("one_health"):
		player.restore_from_run_state(1.0, 1.0)


func _open_pause_menu() -> void:
	if tutorial_active:
		return
	get_tree().paused = true
	crosshair.visible = false
	game_music.stream_paused = true
	pause_menu.open_menu()


func _spawn_trees_around_player() -> void:
	if player == null:
		return
	if online_run and not online_role_assigned:
		return

	for center_position in _get_chunk_spawn_center_positions():
		var center_chunk := _world_to_chunk(center_position)
		for x in range(center_chunk.x - active_chunk_radius, center_chunk.x + active_chunk_radius + 1):
			for y in range(center_chunk.y - active_chunk_radius, center_chunk.y + active_chunk_radius + 1):
				var chunk := Vector2i(x, y)
				if spawned_chunks.has(chunk):
					continue
				_spawn_chunk(chunk)
				spawned_chunks[chunk] = true


func _get_chunk_spawn_center_positions() -> Array[Vector2]:
	var centers: Array[Vector2] = [player.global_position]
	if not online_run or not online_is_host:
		return centers
	for remote_player in remote_players.values():
		if remote_player is Node2D and is_instance_valid(remote_player):
			centers.append((remote_player as Node2D).global_position)
	return centers


func _is_far_enough_from_spawn_centers(spawn_position: Vector2, minimum_distance: float) -> bool:
	for center_position in _get_chunk_spawn_center_positions():
		if spawn_position.distance_to(center_position) < minimum_distance:
			return false
	return true


func _spawn_chunk(chunk: Vector2i) -> void:
	if tree_scene == null:
		return
	var chunk_origin := Vector2(chunk.x * chunk_size, chunk.y * chunk_size)
	var tree_rng := _chunk_rng(chunk, "trees")
	for _i in trees_per_chunk:
		var position_found := false
		var spawn_position := Vector2.ZERO
		for _attempt in spawn_attempts_per_tree:
			spawn_position = chunk_origin + Vector2(
				tree_rng.randf_range(0.0, chunk_size),
				tree_rng.randf_range(0.0, chunk_size)
			)
			if _is_far_enough_from_spawn_centers(spawn_position, min_tree_distance_from_player):
				position_found = true
				break
		if not position_found:
			continue
		var tree := tree_scene.instantiate()
		add_child(tree)
		tree.global_position = spawn_position
		if tree is Node2D:
			(tree as Node2D).rotation = tree_rng.randf_range(-TREE_ROTATION_VARIATION, TREE_ROTATION_VARIATION)
		var tree_sprite: Variant = tree.get_node_or_null("PineTree")
		if tree_sprite is Sprite2D:
			(tree_sprite as Sprite2D).flip_h = tree_rng.randf() < 0.5

	if online_run and not online_is_host:
		return
	_spawn_chunk_entities(chunk, chunk_origin)


func _spawn_chunk_entities(chunk: Vector2i, chunk_origin: Vector2) -> void:
	if online_run and online_is_host:
		if online_host_entity_chunks.has(chunk):
			return
		online_host_entity_chunks[chunk] = true

	var mob_spawn_chance := ONLINE_MOB_SPAWN_CHANCE_PER_CHUNK if online_run else mob_spawn_chance_per_chunk
	if mob_scene != null and medium_monster_scene != null and heavy_monster_scene != null and randf() <= mob_spawn_chance:
		var scaled_mob_count: int = mobs_per_chunk + min(int(score / 20), 4)
		if _is_modifier_enabled("double_enemy_spawns"):
			scaled_mob_count *= 2
		var mob_rng := _chunk_rng(chunk, "mobs")
		for _i in scaled_mob_count:
			var mob_position_found := false
			var mob_spawn_position := Vector2.ZERO
			for _attempt in spawn_attempts_per_mob:
				mob_spawn_position = chunk_origin + Vector2(
					mob_rng.randf_range(0.0, chunk_size),
					mob_rng.randf_range(0.0, chunk_size)
				)
				if _is_far_enough_from_spawn_centers(mob_spawn_position, min_mob_distance_from_player):
					mob_position_found = true
					break
			if not mob_position_found:
				continue
			var mob_kind := _pick_monster_kind_for_score(mob_rng)
			var mob := _instantiate_mob_kind(mob_kind)
			_apply_mob_modifiers(mob)
			add_child(mob)
			mob.global_position = mob_spawn_position
			if online_run and online_is_host:
				_register_host_mob(mob, mob_kind)

	if not _is_modifier_enabled("disable_food"):
		var food_rng := _chunk_rng(chunk, "foods")
		if food_scene != null and food_rng.randf() <= food_spawn_chance_per_chunk:
			for _i in foods_per_chunk:
				var food_position_found := false
				var food_spawn_position := Vector2.ZERO
				for _attempt in spawn_attempts_per_food:
					food_spawn_position = chunk_origin + Vector2(
						food_rng.randf_range(0.0, chunk_size),
						food_rng.randf_range(0.0, chunk_size)
					)
					if _is_far_enough_from_spawn_centers(food_spawn_position, min_food_distance_from_player):
						food_position_found = true
						break
				if not food_position_found:
					continue
				var food := food_scene.instantiate()
				add_child(food)
				food.global_position = food_spawn_position
				if online_run and online_is_host:
					var texture_index := food_rng.randi_range(0, 11)
					var visual_scale := food_rng.randf_range(1.6, 2.1)
					if food.has_method("apply_network_visual"):
						food.apply_network_visual(texture_index, visual_scale)
					_register_host_food(food, texture_index, visual_scale)

	var powerup_rng := _chunk_rng(chunk, "race_car")
	if score >= RACE_CAR_MIN_SCORE and RACE_CAR_PICKUP_SCENE != null and powerup_rng.randf() <= race_car_spawn_chance_per_chunk:
		var powerup_position_found := false
		var powerup_spawn_position := Vector2.ZERO
		for _attempt in spawn_attempts_per_powerup:
			powerup_spawn_position = chunk_origin + Vector2(
				powerup_rng.randf_range(0.0, chunk_size),
				powerup_rng.randf_range(0.0, chunk_size)
			)
			if _is_far_enough_from_spawn_centers(powerup_spawn_position, min_powerup_distance_from_player):
				powerup_position_found = true
				break
		if powerup_position_found:
			var powerup := RACE_CAR_PICKUP_SCENE.instantiate()
			add_child(powerup)
			powerup.global_position = powerup_spawn_position


func _world_to_chunk(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / chunk_size)),
		int(floor(world_position.y / chunk_size))
	)


func _chunk_rng(chunk: Vector2i, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [salt, chunk.x, chunk.y])
	return rng


func _on_player_died() -> void:
	_set_chat_input_active(false)
	tutorial_ui.visible = false
	tutorial_active = false
	var earned_coins := _award_death_coins()
	game_over_ui.visible = true
	var rewards_text := "Score: %d\nCoins earned: %d\nTotal coins: %d" % [
		score,
		earned_coins,
		SettingsManager.get_coin_balance()
	]
	if _is_modifier_enabled("disable_coins"):
		rewards_text = "Score: %d\nCoins disabled by modifier\nTotal coins: %d" % [
			score,
			SettingsManager.get_coin_balance()
		]
	if _has_active_modifiers():
		rewards_text += "\nModifiers: %s" % _get_modifier_summary_text()
	game_over_rewards_label.text = rewards_text
	crosshair.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_music.stream_paused = true
	get_tree().paused = true
	restart_button.grab_focus()


func _on_restart_button_pressed() -> void:
	get_tree().paused = false
	SaveManager.clear_pending_continue_run()
	get_tree().reload_current_scene()


func _on_quit_to_title_pressed() -> void:
	get_tree().paused = false
	_set_chat_input_active(false)
	if online_run:
		MultiplayerClient.disconnect_from_server()
	SaveManager.clear_pending_continue_run()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	crosshair.visible = false
	tutorial_ui.visible = false
	tutorial_active = false
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _on_pause_resume_requested() -> void:
	pause_menu.close_menu()
	get_tree().paused = false
	crosshair.visible = true
	game_music.stream_paused = false


func _on_game_music_finished() -> void:
	if game_music == null:
		return
	if game_music.stream_paused:
		return
	game_music.play()


func _on_pause_save_requested() -> void:
	if _has_active_modifiers():
		return
	SaveManager.save_run(export_run_state())


func _on_player_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	_update_hud_health_bar_color(current, maximum)


func add_score(points: int = 1, counts_for_coins: bool = true) -> void:
	var earned := maxi(points, 0)
	score += earned
	if counts_for_coins:
		gun_score += earned
	if earned > 0:
		_check_weapon_upgrades()
	_update_score_label()


func _award_death_coins() -> int:
	if coins_awarded_this_run:
		return 0
	coins_awarded_this_run = true
	if _is_modifier_enabled("disable_coins"):
		return 0
	var earned := maxi(gun_score, 0)
	SettingsManager.add_coins(earned)
	return earned


func _update_score_label() -> void:
	score_label.text = "Score: %d" % score


func _update_weapon_label() -> void:
	if weapon_label == null:
		return
	var mode_text := " | Car: %.0fs" % ceil(race_car_seconds_left) if race_car_seconds_left > 0.0 else ""
	weapon_label.text = "Weapon: %s Lv. %d%s" % [
		player.get_weapon_display_name(),
		weapon_upgrade_level + 1,
		mode_text
	]


func _check_weapon_upgrades() -> void:
	while score >= next_weapon_upgrade_score:
		weapon_upgrade_level += 1
		next_weapon_upgrade_score += next_weapon_upgrade_gap
		next_weapon_upgrade_gap += 10
		if player.has_method("apply_weapon_upgrade"):
			player.apply_weapon_upgrade(weapon_upgrade_level)
		_show_notification("Weapon upgrade! Lv. %d" % (weapon_upgrade_level + 1))
	_update_weapon_label()


func _sync_weapon_upgrades_for_score() -> void:
	weapon_upgrade_level = 0
	next_weapon_upgrade_score = 10
	next_weapon_upgrade_gap = 20
	while score >= next_weapon_upgrade_score:
		weapon_upgrade_level += 1
		next_weapon_upgrade_score += next_weapon_upgrade_gap
		next_weapon_upgrade_gap += 10
	if player.has_method("apply_weapon_upgrade"):
		player.apply_weapon_upgrade(weapon_upgrade_level)
	_update_weapon_label()


func _show_notification(text: String) -> void:
	notification_label.text = text
	notification_label.visible = true
	notification_seconds_left = 2.4


func _process_notification(delta: float) -> void:
	if notification_seconds_left <= 0.0:
		notification_label.visible = false
		return
	notification_seconds_left = maxf(notification_seconds_left - delta, 0.0)
	notification_label.visible = notification_seconds_left > 0.0


func _update_controls_hint_label() -> void:
	var bomb_key := SettingsManager.get_action_binding_text(&"throw_bomb")
	var pause_key := SettingsManager.get_action_binding_text(&"pause")
	var parts: Array[String] = ["Aim: Mouse"]
	if _is_modifier_enabled("disable_pistol"):
		parts.append("Pistol disabled")
	if _is_modifier_enabled("disable_bombs"):
		parts.append("Bombs disabled")
	else:
		parts.append("Bomb: %s" % bomb_key)
	parts.append("Pause: %s" % pause_key)
	controls_hint_label.text = " | ".join(parts)


func _build_chat_ui() -> void:
	chat_panel = PanelContainer.new()
	chat_panel.name = "ChatPanel"
	chat_panel.visible = false
	chat_panel.anchor_left = 0.0
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_right = 0.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 20.0
	chat_panel.offset_top = -230.0
	chat_panel.offset_right = 560.0
	chat_panel.offset_bottom = -20.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.02, 0.025, 0.72)
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.18)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	chat_panel.add_theme_stylebox_override("panel", panel_style)
	$HUD.add_child(chat_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	chat_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	chat_log_label = Label.new()
	chat_log_label.custom_minimum_size = Vector2(500, 138)
	chat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	chat_log_label.add_theme_font_size_override("font_size", 18)
	box.add_child(chat_log_label)

	chat_input = LineEdit.new()
	chat_input.visible = false
	chat_input.max_length = CHAT_MAX_LENGTH
	chat_input.caret_blink = true
	chat_input.text_submitted.connect(_on_chat_text_submitted)
	box.add_child(chat_input)


func _process_chat(delta: float) -> void:
	if chat_send_cooldown > 0.0:
		chat_send_cooldown = maxf(chat_send_cooldown - delta, 0.0)
	_prune_expired_chat_messages()
	_update_chat_ui()


func _set_chat_input_active(active: bool) -> void:
	if not online_run and active:
		return
	chat_input_active = active
	if player != null and player.has_method("set_controls_locked"):
		player.set_controls_locked(chat_input_active)
	if chat_input == null:
		return
	chat_input.visible = chat_input_active
	if chat_input_active:
		chat_input.text = ""
		chat_input.grab_focus()
	else:
		chat_input.release_focus()
	_update_chat_ui()


func _on_chat_text_submitted(text: String) -> void:
	var message_text := _sanitize_chat_text(text)
	if message_text.is_empty():
		_set_chat_input_active(false)
		return
	if chat_send_cooldown > 0.0:
		chat_input.text = message_text
		return
	chat_send_cooldown = CHAT_SEND_COOLDOWN_SECONDS
	var username := SettingsManager.get_username()
	if username.strip_edges().is_empty():
		username = "Player"
	_add_chat_message(username, message_text)
	MultiplayerClient.send_world_message("chat_message", {
		"username": username,
		"text": message_text
	})
	_set_chat_input_active(false)


func _sanitize_chat_text(text: String) -> String:
	var cleaned := text.replace("\n", " ").replace("\r", " ").strip_edges()
	if cleaned.length() > CHAT_MAX_LENGTH:
		cleaned = cleaned.substr(0, CHAT_MAX_LENGTH)
	return cleaned


func _add_chat_message(username: String, text: String) -> void:
	chat_messages.append({
		"username": username.strip_edges() if not username.strip_edges().is_empty() else "Player",
		"text": _sanitize_chat_text(text),
		"time": float(Time.get_ticks_msec()) / 1000.0
	})
	while chat_messages.size() > CHAT_MAX_VISIBLE_MESSAGES:
		chat_messages.pop_front()
	_update_chat_ui()


func _prune_expired_chat_messages() -> void:
	if chat_input_active:
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	while not chat_messages.is_empty():
		if now - float(chat_messages[0].get("time", now)) <= CHAT_MESSAGE_VISIBLE_SECONDS:
			return
		chat_messages.pop_front()


func _update_chat_ui() -> void:
	if chat_panel == null or chat_log_label == null:
		return
	var lines: Array[String] = []
	for message in chat_messages:
		lines.append("%s: %s" % [String(message.get("username", "Player")), String(message.get("text", ""))])
	chat_log_label.text = "\n".join(lines)
	chat_panel.visible = online_run and (chat_input_active or not chat_messages.is_empty())


func _setup_multiplayer_if_requested() -> void:
	online_run = MultiplayerClient.consume_online_run_requested()
	multiplayer_status_label.visible = online_run
	if not online_run:
		return
	online_is_host = false
	online_role_assigned = false

	MultiplayerClient.remote_player_state_received.connect(_on_remote_player_state_received)
	MultiplayerClient.remote_player_left.connect(_on_remote_player_left)
	MultiplayerClient.connection_status_changed.connect(_on_multiplayer_connection_status_changed)
	MultiplayerClient.host_status_changed.connect(_on_multiplayer_host_status_changed)
	MultiplayerClient.world_message_received.connect(_on_multiplayer_world_message_received)
	_on_multiplayer_connection_status_changed(MultiplayerClient.connection_status)
	MultiplayerClient.connect_to_server()


func _process_multiplayer_state(delta: float) -> void:
	if not online_run:
		return
	multiplayer_send_accumulator += delta
	if multiplayer_send_accumulator < MULTIPLAYER_STATE_SEND_INTERVAL:
		pass
	else:
		multiplayer_send_accumulator = 0.0
		MultiplayerClient.send_player_state(_build_local_player_state())

	if online_is_host:
		multiplayer_mob_send_accumulator += delta
		if multiplayer_mob_send_accumulator >= MULTIPLAYER_MOB_STATE_SEND_INTERVAL:
			multiplayer_mob_send_accumulator = 0.0
			_broadcast_mob_states()


func _build_local_player_state() -> Dictionary:
	var animation_state := "walk" if player.velocity.length() > 1.0 else "idle"
	return {
		"position": {
			"x": player.global_position.x,
			"y": player.global_position.y
		},
		"velocity": {
			"x": player.velocity.x,
			"y": player.velocity.y
		},
		"username": SettingsManager.get_username(),
		"skin_id": SettingsManager.get_equipped_skin(),
		"animation": animation_state,
		"aim_angle": player.get_gun_aim_angle(),
		"gun_active": player.is_gun_active()
	}


func _on_remote_player_state_received(player_id: String, state: Dictionary) -> void:
	var remote_player: Node2D = remote_players.get(player_id, null)
	if remote_player == null:
		remote_player = REMOTE_PLAYER_SCENE.instantiate()
		remote_player.name = "RemotePlayer_%s" % player_id.substr(0, 8)
		add_child(remote_player)
		remote_players[player_id] = remote_player
	if remote_player.has_method("apply_state"):
		remote_player.apply_state(state)


func _on_remote_player_left(player_id: String) -> void:
	var remote_player: Node = remote_players.get(player_id, null)
	if remote_player != null:
		remote_player.queue_free()
	remote_players.erase(player_id)


func _on_multiplayer_connection_status_changed(status: String) -> void:
	multiplayer_status_label.text = "Multiplayer: %s" % status


func _on_multiplayer_host_status_changed(is_host: bool) -> void:
	var was_host := online_is_host
	online_is_host = is_host
	online_role_assigned = true
	if online_run and online_is_host:
		if not was_host:
			_clear_network_rendered_entities()
			_spawn_missing_host_entities_for_spawned_chunks()
		multiplayer_status_label.text = "Multiplayer: Online (Host)"
	if online_run:
		_spawn_trees_around_player()


func _spawn_missing_host_entities_for_spawned_chunks() -> void:
	if not online_run or not online_is_host:
		return
	for chunk in spawned_chunks.keys():
		if chunk is Vector2i:
			_spawn_chunk_entities(chunk, Vector2(chunk.x * chunk_size, chunk.y * chunk_size))


func _on_multiplayer_world_message_received(message: Dictionary) -> void:
	var message_type := String(message.get("type", ""))
	match message_type:
		"player_joined":
			if online_is_host:
				_send_world_snapshot()
		"world_snapshot":
			if not online_is_host:
				_apply_world_snapshot(message)
		"world_spawn":
			if not online_is_host:
				_apply_world_spawn(message)
		"mob_state":
			if not online_is_host:
				_apply_mob_state(message)
		"mob_died":
			_apply_mob_died(message)
		"food_collect":
			if online_is_host:
				_apply_food_collected(String(message.get("food_id", "")), String(message.get("from_player_id", "")))
		"food_collected":
			_apply_food_collected(String(message.get("food_id", "")), String(message.get("collector_player_id", "")))
		"projectile_hit":
			if online_is_host:
				_apply_projectile_hit(message)
		"projectile_fired":
			_apply_remote_projectile_fired(message)
		"chat_message":
			_apply_chat_message(message)
		"bomb_exploded":
			if online_is_host:
				_apply_bomb_exploded(message)


func _apply_chat_message(message: Dictionary) -> void:
	var sender_id := String(message.get("from_player_id", ""))
	if not sender_id.is_empty() and sender_id == MultiplayerClient.local_player_id:
		return
	_add_chat_message(
		String(message.get("username", "Player")),
		String(message.get("text", ""))
	)


func handle_local_projectile_fired(position: Vector2, rotation: float, damage: float = 1.0, projectile_speed: float = 1200.0, projectile_scale: float = 1.0, projectile_color: Color = Color.WHITE) -> void:
	if not online_run:
		return
	MultiplayerClient.send_world_message("projectile_fired", {
		"position": _vector_to_payload(position),
		"rotation": rotation,
		"damage": damage,
		"speed": projectile_speed,
		"scale": projectile_scale,
		"color": _color_to_payload(projectile_color)
	})


func _apply_remote_projectile_fired(message: Dictionary) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	projectile.visual_only = true
	add_child(projectile)
	projectile.global_position = _payload_to_vector(message.get("position", {}))
	projectile.rotation = float(message.get("rotation", 0.0))
	projectile.direction = Vector2.RIGHT.rotated(projectile.rotation)
	projectile.damage = float(message.get("damage", 1.0))
	projectile.speed = float(message.get("speed", 1200.0))
	projectile.scale = Vector2.ONE * float(message.get("scale", 1.0))
	projectile.modulate = _payload_to_color(message.get("color", {}), Color.WHITE)

	var muzzle_flash := MUZZLE_FLASH_SCENE.instantiate()
	add_child(muzzle_flash)
	muzzle_flash.global_position = projectile.global_position
	muzzle_flash.global_rotation = projectile.rotation


func _register_host_mob(mob: Node, mob_kind: String) -> void:
	var mob_id := "mob_%d" % next_network_mob_id
	next_network_mob_id += 1
	mob.set_meta("network_id", mob_id)
	mob.set_meta("network_kind", mob_kind)
	network_mobs[mob_id] = mob
	MultiplayerClient.send_world_message("world_spawn", _build_mob_spawn_payload(mob_id, mob_kind, mob))


func _register_host_food(food: Node, texture_index: int, visual_scale: float) -> void:
	var food_id := "food_%d" % next_network_food_id
	next_network_food_id += 1
	food.set("network_id", food_id)
	food.set("network_mode", "host")
	food.set_meta("texture_index", texture_index)
	food.set_meta("visual_scale", visual_scale)
	network_foods[food_id] = food
	MultiplayerClient.send_world_message("world_spawn", {
		"entity_type": "food",
		"food_id": food_id,
		"texture_index": texture_index,
		"visual_scale": visual_scale,
		"position": _vector_to_payload((food as Node2D).global_position)
	})


func _build_mob_spawn_payload(mob_id: String, mob_kind: String, mob: Node) -> Dictionary:
	return {
		"entity_type": "mob",
		"mob_id": mob_id,
		"mob_kind": mob_kind,
		"position": _vector_to_payload((mob as Node2D).global_position),
		"health": float(mob.get("current_health"))
	}


func _send_world_snapshot() -> void:
	var mobs: Array[Dictionary] = []
	for mob_id in network_mobs.keys():
		var mob: Node = network_mobs[mob_id]
		if is_instance_valid(mob):
			mobs.append(_build_mob_spawn_payload(mob_id, String(mob.get_meta("network_kind", "slime")), mob))
	var foods: Array[Dictionary] = []
	for food_id in network_foods.keys():
		var food: Node = network_foods[food_id]
		if is_instance_valid(food):
			foods.append({
				"entity_type": "food",
				"food_id": food_id,
				"texture_index": int(food.get_meta("texture_index", 0)),
				"visual_scale": float(food.get_meta("visual_scale", 1.8)),
				"position": _vector_to_payload((food as Node2D).global_position)
			})
	MultiplayerClient.send_world_message("world_snapshot", {"mobs": mobs, "foods": foods})


func _apply_world_snapshot(message: Dictionary) -> void:
	_clear_network_rendered_entities()
	for mob_data in message.get("mobs", []):
		if mob_data is Dictionary:
			_spawn_network_mob_from_payload(mob_data)
	for food_data in message.get("foods", []):
		if food_data is Dictionary:
			_spawn_network_food_from_payload(food_data)


func _apply_world_spawn(message: Dictionary) -> void:
	if String(message.get("entity_type", "")) == "mob":
		_spawn_network_mob_from_payload(message)
	elif String(message.get("entity_type", "")) == "food":
		_spawn_network_food_from_payload(message)


func _spawn_network_mob_from_payload(payload: Dictionary) -> void:
	var mob_id := String(payload.get("mob_id", ""))
	if mob_id.is_empty() or network_mobs.has(mob_id):
		return
	var mob := _instantiate_mob_kind(String(payload.get("mob_kind", "slime")))
	add_child(mob)
	mob.global_position = _payload_to_vector(payload.get("position", {}))
	mob.set_meta("network_id", mob_id)
	mob.add_to_group("network_mobs")
	mob.remove_from_group("mobs")
	mob.set_physics_process(false)
	mob.set_process(false)
	if mob.get("current_health") != null:
		mob.set("current_health", float(payload.get("health", mob.get("current_health"))))
	network_mobs[mob_id] = mob


func _spawn_network_food_from_payload(payload: Dictionary) -> void:
	var food_id := String(payload.get("food_id", ""))
	if food_id.is_empty() or network_foods.has(food_id):
		return
	var food := food_scene.instantiate()
	add_child(food)
	food.global_position = _payload_to_vector(payload.get("position", {}))
	food.set("network_id", food_id)
	food.set("network_mode", "client")
	if food.has_method("apply_network_visual"):
		food.apply_network_visual(int(payload.get("texture_index", 0)), float(payload.get("visual_scale", 1.8)))
	network_foods[food_id] = food


func _apply_mob_state(message: Dictionary) -> void:
	var mob_id := String(message.get("mob_id", ""))
	var mob: Node2D = network_mobs.get(mob_id, null)
	if mob == null or not is_instance_valid(mob):
		return
	mob.global_position = mob.global_position.lerp(_payload_to_vector(message.get("position", {})), 0.45)
	if mob.get("current_health") != null:
		mob.set("current_health", float(message.get("health", mob.get("current_health"))))


func _broadcast_mob_states() -> void:
	for mob_id in network_mobs.keys():
		var mob: Node = network_mobs[mob_id]
		if not is_instance_valid(mob):
			network_mobs.erase(mob_id)
			continue
		MultiplayerClient.send_world_message("mob_state", {
			"mob_id": mob_id,
			"position": _vector_to_payload((mob as Node2D).global_position),
			"health": float(mob.get("current_health"))
		})


func apply_network_mob_damage(mob: Node, amount: float, counts_for_coins: bool, knockback_direction: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> bool:
	if not online_run:
		if mob.has_method("apply_knockback") and knockback_force > 0.0:
			mob.apply_knockback(knockback_direction, knockback_force)
		return mob.take_damage(amount) if mob.has_method("take_damage") else false
	if not online_is_host:
		return false
	var mob_id := String(mob.get_meta("network_id", ""))
	if mob_id.is_empty():
		if mob.has_method("apply_knockback") and knockback_force > 0.0:
			mob.apply_knockback(knockback_direction, knockback_force)
		return mob.take_damage(amount) if mob.has_method("take_damage") else false
	if mob.has_method("apply_knockback") and knockback_force > 0.0:
		mob.apply_knockback(knockback_direction, knockback_force)
	var killed: bool = mob.take_damage(amount) if mob.has_method("take_damage") else false
	if killed:
		network_mobs.erase(mob_id)
		MultiplayerClient.send_world_message("mob_died", {
			"mob_id": mob_id,
			"counts_for_coins": counts_for_coins
		})
	return killed


func request_network_projectile_hit(mob: Node, damage: float = 1.0, knockback_direction: Vector2 = Vector2.ZERO, knockback_force: float = 0.0) -> void:
	if not online_run:
		return
	var mob_id := String(mob.get_meta("network_id", ""))
	if mob_id.is_empty():
		return
	if online_is_host:
		if apply_network_mob_damage(mob, damage, true, knockback_direction, knockback_force):
			add_score(1)
	else:
		MultiplayerClient.send_world_message("projectile_hit", {
			"mob_id": mob_id,
			"damage": damage,
			"knockback_direction": _vector_to_payload(knockback_direction),
			"knockback_force": knockback_force
		})


func request_network_bomb_explosion(origin: Vector2, radius: float, damage: float) -> bool:
	if not online_run:
		return false
	if online_is_host:
		_apply_host_bomb_damage(origin, radius, damage)
	else:
		MultiplayerClient.send_world_message("bomb_exploded", {
			"position": _vector_to_payload(origin),
			"radius": radius,
			"damage": damage
		})
	return true


func _apply_projectile_hit(message: Dictionary) -> void:
	var mob_id := String(message.get("mob_id", ""))
	var mob: Node = network_mobs.get(mob_id, null)
	if mob != null and is_instance_valid(mob):
		if apply_network_mob_damage(
			mob,
			float(message.get("damage", 1.0)),
			true,
			_payload_to_vector(message.get("knockback_direction", {})),
			float(message.get("knockback_force", 0.0))
		):
			add_score(1)


func _apply_bomb_exploded(message: Dictionary) -> void:
	_apply_host_bomb_damage(
		_payload_to_vector(message.get("position", {})),
		float(message.get("radius", 0.0)),
		float(message.get("damage", 0.0))
	)


func _apply_host_bomb_damage(origin: Vector2, radius: float, damage: float) -> void:
	var kills := 0
	for mob_id in network_mobs.keys():
		var mob: Node = network_mobs[mob_id]
		if not is_instance_valid(mob) or not (mob is Node2D):
			continue
		if (mob as Node2D).global_position.distance_to(origin) > radius:
			continue
		if apply_network_mob_damage(mob, damage, false):
			kills += 1
	if kills > 0:
		add_score(kills, false)


func handle_food_pickup(food: Node, body: Node) -> void:
	if body.name != "Player":
		return
	if not online_run:
		if body.has_method("heal"):
			body.heal(float(food.get("heal_amount")))
		food.queue_free()
		return
	var food_id := String(food.get("network_id"))
	if online_is_host:
		_apply_food_collected(food_id, MultiplayerClient.local_player_id)
	else:
		MultiplayerClient.send_world_message("food_collect", {"food_id": food_id})


func handle_race_car_pickup(powerup: Node, body: Node) -> void:
	if body != player:
		return
	_start_race_car_mode()
	powerup.queue_free()


func _start_race_car_mode() -> void:
	race_car_seconds_left = RACE_CAR_DURATION_SECONDS
	race_car_fire_accumulator = RACE_CAR_RADIAL_FIRE_INTERVAL
	if player.has_method("set_car_mode_active"):
		player.set_car_mode_active(true)
	_show_notification("Race car mode! 10 seconds")
	_update_weapon_label()


func _process_race_car_mode(delta: float) -> void:
	if race_car_seconds_left <= 0.0:
		return
	race_car_seconds_left = maxf(race_car_seconds_left - delta, 0.0)
	race_car_fire_accumulator += delta
	while race_car_fire_accumulator >= RACE_CAR_RADIAL_FIRE_INTERVAL:
		race_car_fire_accumulator -= RACE_CAR_RADIAL_FIRE_INTERVAL
		_fire_race_car_radial_burst()
	if race_car_seconds_left <= 0.0:
		if player.has_method("set_car_mode_active"):
			player.set_car_mode_active(false)
		_show_notification("Race car power ended")
	_update_weapon_label()


func _fire_race_car_radial_burst() -> void:
	if player == null or player.is_dead_state():
		return
	if _is_modifier_enabled("disable_pistol"):
		return
	for index in range(RACE_CAR_RADIAL_SHOTS):
		var angle := TAU * float(index) / float(RACE_CAR_RADIAL_SHOTS)
		_spawn_local_projectile(
			player.global_position + Vector2.RIGHT.rotated(angle) * 60.0,
			angle,
			RACE_CAR_PROJECTILE_DAMAGE,
			RACE_CAR_PROJECTILE_SPEED,
			0.9,
			Color(1.0, 0.72, 0.18, 1.0)
		)


func _spawn_local_projectile(position: Vector2, rotation: float, damage: float, projectile_speed: float, projectile_scale: float, projectile_color: Color) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	add_child(projectile)
	projectile.shooter = player
	projectile.global_position = position
	projectile.rotation = rotation
	projectile.direction = Vector2.RIGHT.rotated(rotation)
	projectile.damage = damage
	projectile.speed = projectile_speed
	projectile.scale = Vector2.ONE * projectile_scale
	projectile.modulate = projectile_color
	handle_local_projectile_fired(position, rotation, damage, projectile_speed, projectile_scale, projectile_color)


func _apply_food_collected(food_id: String, collector_player_id: String) -> void:
	var food: Node = network_foods.get(food_id, null)
	if food == null or not is_instance_valid(food):
		return
	if collector_player_id == MultiplayerClient.local_player_id and player.has_method("heal"):
		player.heal(float(food.get("heal_amount")))
	network_foods.erase(food_id)
	food.queue_free()
	if online_is_host:
		MultiplayerClient.send_world_message("food_collected", {
			"food_id": food_id,
			"collector_player_id": collector_player_id
		})


func _apply_mob_died(message: Dictionary) -> void:
	var mob_id := String(message.get("mob_id", ""))
	var mob: Node = network_mobs.get(mob_id, null)
	if mob != null and is_instance_valid(mob):
		mob.queue_free()
	network_mobs.erase(mob_id)


func _clear_network_rendered_entities() -> void:
	for mob in network_mobs.values():
		if is_instance_valid(mob):
			(mob as Node).queue_free()
	for food in network_foods.values():
		if is_instance_valid(food):
			(food as Node).queue_free()
	network_mobs.clear()
	network_foods.clear()


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
		"gun_score": gun_score,
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
	gun_score = int(state.get("gun_score", score))
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
	_sync_weapon_upgrades_for_score()
	_update_score_label()
	return true


func _pick_monster_kind_for_score(rng: RandomNumberGenerator) -> String:
	if score >= score_for_heavy_monsters and rng.randf() < 0.55:
		return "heavy"
	if score >= score_for_medium_monsters and rng.randf() < 0.45:
		return "medium"
	return "slime"


func _instantiate_mob_kind(mob_kind: String) -> Node:
	match mob_kind:
		"heavy":
			return heavy_monster_scene.instantiate()
		"medium":
			return medium_monster_scene.instantiate()
		_:
			return mob_scene.instantiate()


func _apply_mob_modifiers(mob: Node) -> void:
	if _is_modifier_enabled("no_headstart") and mob.get("headstart_seconds") != null:
		mob.set("headstart_seconds", 0.0)
	if _is_modifier_enabled("fast_enemies") and mob.get("move_speed") != null:
		mob.set("move_speed", float(mob.get("move_speed")) * FAST_ENEMY_SPEED_MULTIPLIER)


func _is_modifier_enabled(modifier_id: String) -> bool:
	return bool(active_modifiers.get(modifier_id, false))


func _has_active_modifiers() -> bool:
	return not active_modifiers.is_empty()


func _get_active_modifier_names() -> Array[String]:
	var names: Array[String] = []
	for modifier in SettingsManager.get_modifier_catalog():
		var modifier_id := String(modifier.get("id", ""))
		if _is_modifier_enabled(modifier_id):
			names.append(String(modifier.get("name", SettingsManager.get_modifier_name(modifier_id))))
	return names


func _get_modifier_summary_text() -> String:
	var names := _get_active_modifier_names()
	if names.is_empty():
		return "None"
	return ", ".join(names)


func _update_modifier_summary_label() -> void:
	modifier_summary_label.visible = _has_active_modifiers()
	modifier_summary_label.text = "Modifiers: %s" % _get_modifier_summary_text()


func _vector_to_payload(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y
	}


func _color_to_payload(value: Color) -> Dictionary:
	return {
		"r": value.r,
		"g": value.g,
		"b": value.b,
		"a": value.a
	}


func _payload_to_color(value: Variant, fallback: Color) -> Color:
	if value is Dictionary:
		return Color(
			float(value.get("r", fallback.r)),
			float(value.get("g", fallback.g)),
			float(value.get("b", fallback.b)),
			float(value.get("a", fallback.a))
		)
	return fallback


func _payload_to_vector(value: Variant) -> Vector2:
	if value is Dictionary:
		return Vector2(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0))
		)
	return Vector2.ZERO


func _ensure_scene_defaults() -> void:
	if tree_scene == null:
		tree_scene = preload("res://pine_tree.tscn")
	if mob_scene == null:
		mob_scene = preload("res://slime.tscn")
	if medium_monster_scene == null:
		medium_monster_scene = preload("res://monsters/monster_bee.tscn")
	if heavy_monster_scene == null:
		heavy_monster_scene = preload("res://monsters/monster_spike.tscn")
	if food_scene == null:
		food_scene = preload("res://food/food_pickup.tscn")
