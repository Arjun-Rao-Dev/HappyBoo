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
@export var network_snapshot_interval: float = 0.10
@export var remote_position_lerp_speed: float = 14.0
@export var remote_rotation_lerp_speed: float = 16.0
const TREE_ROTATION_VARIATION := 0.08
const MULTIPLAYER_DEBUG_LOGS := false

var spawned_chunks: Dictionary = {}
var score: int = 0
var run_start_time_ms: int = 0
var is_multiplayer_session := false
var is_host_session := false
var session_mode := "single"
var remote_players: Dictionary = {}
var remote_inputs: Dictionary = {}
var remote_input_ticks: Dictionary = {}
var remote_mobs: Dictionary = {}
var remote_foods: Dictionary = {}
var remote_last_positions: Dictionary = {}
var remote_target_positions: Dictionary = {}
var remote_target_gun_rotations: Dictionary = {}
var snapshot_elapsed := 0.0
var local_input_tick: int = 0
var local_fire_was_pressed := false

@onready var player = $Player
@onready var player_scene: PackedScene = preload("res://player.tscn")
@onready var projectile_scene_mp: PackedScene = preload("res://pistol/projectile.tscn")
@onready var muzzle_flash_scene_mp: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
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
	_ensure_scene_defaults()
	SettingsManager.load_settings()
	_configure_session_state()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	game_over_ui.visible = false
	game_over_ui.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
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
	pause_menu.set_save_enabled(not is_multiplayer_session)

	run_start_time_ms = Time.get_ticks_msec()
	if not is_multiplayer_session:
		_apply_continue_state_if_present()
	else:
		SaveManager.clear_pending_continue_run()
		_setup_multiplayer_match()
	_update_score_label()
	_on_player_health_changed(player.get_current_health(), player.get_max_health())
	_update_controls_hint_label()
	if session_mode == "pvp":
		_cleanup_pvp_mode_entities()
	_spawn_trees_around_player()


func _configure_session_state() -> void:
	is_multiplayer_session = MultiplayerSession != null and MultiplayerSession.is_multiplayer
	is_host_session = not is_multiplayer_session or MultiplayerSession.is_host
	session_mode = "single"
	if is_multiplayer_session:
		session_mode = MultiplayerSession.mode


func _setup_multiplayer_match() -> void:
	if not is_multiplayer_session:
		return
	if player.has_method("set_display_name"):
		player.set_display_name(_username_for_peer(MultiplayerSession.local_peer_id))
	player.set_actions_enabled(true)
	_set_player_gun_firing_enabled(player, is_host_session)

	if not MultiplayerSession.relay_input_received.is_connected(_on_network_input_received):
		MultiplayerSession.relay_input_received.connect(_on_network_input_received)
	if not MultiplayerSession.relay_snapshot_received.is_connected(_on_network_snapshot_received):
		MultiplayerSession.relay_snapshot_received.connect(_on_network_snapshot_received)
	if not MultiplayerSession.relay_event_received.is_connected(_on_network_event_received):
		MultiplayerSession.relay_event_received.connect(_on_network_event_received)
	if not MultiplayerSession.roster_updated.is_connected(_on_session_roster_updated):
		MultiplayerSession.roster_updated.connect(_on_session_roster_updated)
	if not MultiplayerSession.host_disconnected.is_connected(_on_session_host_disconnected):
		MultiplayerSession.host_disconnected.connect(_on_session_host_disconnected)
	if is_host_session:
		_register_player_projectile_events(player, MultiplayerSession.local_peer_id)

	_sync_remote_players_from_roster()


func _process_multiplayer(delta: float) -> void:
	if not is_multiplayer_session:
		return
	if is_host_session:
		for peer_id in remote_players.keys():
			var remote_player_entry: Variant = remote_players[peer_id]
			if remote_player_entry and is_instance_valid(remote_player_entry) and remote_player_entry is Node2D:
				var remote_player: Node2D = remote_player_entry as Node2D
				var input_frame: Dictionary = remote_inputs.get(peer_id, {})
				var move_input: Vector2 = input_frame.get("move", Vector2.ZERO)
				var aim_input: Vector2 = input_frame.get("aim", remote_player.global_position + Vector2.RIGHT)
				var fire_pressed: bool = bool(input_frame.get("fire_pressed", false))
				remote_player.set_external_input_vector(move_input)
				if remote_player.has_method("set_external_aim_position"):
					remote_player.set_external_aim_position(aim_input)
				if remote_player.has_method("set_external_fire_pressed"):
					remote_player.set_external_fire_pressed(fire_pressed)
				if fire_pressed:
					input_frame["fire_pressed"] = false
					remote_inputs[peer_id] = input_frame
		snapshot_elapsed += delta
		if snapshot_elapsed >= network_snapshot_interval:
			snapshot_elapsed = 0.0
			var snapshot := _build_host_snapshot()
			MultiplayerSession.send_host_snapshot(snapshot)
			_mp_debug("snapshot sent players=%d" % _snapshot_player_count(snapshot))
		_check_pvp_winner()
	else:
		local_input_tick += 1
		var input_vec := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var aim_world := get_global_mouse_position()
		var fire_now := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var fire_pressed_edge := fire_now and not local_fire_was_pressed
		local_fire_was_pressed = fire_now
		MultiplayerSession.send_input({
			"move": input_vec,
			"aim": aim_world,
			"fire_pressed": fire_pressed_edge,
			"tick": local_input_tick
		})


func _on_network_input_received(peer_id: int, input_frame: Dictionary) -> void:
	if not is_host_session:
		return
	var tick := int(input_frame.get("tick", 0))
	var previous_tick := int(remote_input_ticks.get(peer_id, -1))
	if tick <= previous_tick:
		return
	remote_input_ticks[peer_id] = tick
	remote_inputs[peer_id] = input_frame
	_mp_debug("input peer=%d tick=%d move=%s fire=%s" % [peer_id, tick, str(input_frame.get("move", Vector2.ZERO)), str(input_frame.get("fire_pressed", false))])


func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	if is_host_session:
		return
	_mp_debug("snapshot received players=%d" % _snapshot_player_count(snapshot))
	_apply_host_snapshot(snapshot)


func _on_network_event_received(event_data: Dictionary) -> void:
	var event_type := String(event_data.get("type", ""))
	if event_type == "match_end":
		var message := String(event_data.get("message", "Match ended."))
		_show_multiplayer_end_and_return(message)
	elif event_type == "projectile_spawn":
		_spawn_network_projectile_visual(event_data)


func _on_session_roster_updated(_players: Dictionary) -> void:
	_sync_remote_players_from_roster()


func _on_session_host_disconnected(reason: String) -> void:
	_show_multiplayer_end_and_return(reason)


func _sync_remote_players_from_roster() -> void:
	if not is_multiplayer_session:
		return
	var roster := MultiplayerSession.players
	for peer_id in roster.keys():
		if peer_id == MultiplayerSession.local_peer_id:
			continue
		if remote_players.has(peer_id):
			continue
		var remote := player_scene.instantiate()
		add_child(remote)
		remote.set_use_external_input(true)
		remote.set_actions_enabled(is_host_session)
		_set_player_gun_firing_enabled(remote, is_host_session)
		remote.set_display_name(_username_for_peer(peer_id))
		if not is_host_session:
			remote.set_physics_process(false)
			remote.set_process(false)
		remote.global_position = player.global_position + Vector2(randf_range(-120.0, 120.0), randf_range(-120.0, 120.0))
		remote_players[peer_id] = remote
		remote_last_positions[peer_id] = remote.global_position
		remote_target_positions[peer_id] = remote.global_position
		remote_target_gun_rotations[peer_id] = _get_player_gun_rotation(remote)
		if is_host_session:
			_register_player_projectile_events(remote, peer_id)

	var to_remove: Array = []
	for peer_id in remote_players.keys():
		if roster.has(peer_id):
			continue
		to_remove.append(peer_id)
	for peer_id in to_remove:
		var node: Variant = remote_players[peer_id]
		if node and is_instance_valid(node):
			node.queue_free()
		remote_players.erase(peer_id)
		remote_inputs.erase(peer_id)
		remote_input_ticks.erase(peer_id)
		remote_last_positions.erase(peer_id)
		remote_target_positions.erase(peer_id)
		remote_target_gun_rotations.erase(peer_id)


func _build_host_snapshot() -> Dictionary:
	var players_snapshot: Dictionary = {}
	players_snapshot[str(MultiplayerSession.local_peer_id)] = _player_state(player)
	for peer_id in remote_players.keys():
		var node: Variant = remote_players[peer_id]
		if node and is_instance_valid(node):
			players_snapshot[str(peer_id)] = _player_state(node)

	var mobs_snapshot: Array = []
	var foods_snapshot: Array = []
	if session_mode == "team":
		for mob in get_tree().get_nodes_in_group("mobs"):
			if mob is Node2D:
				mobs_snapshot.append({
					"id": int(mob.get_instance_id()),
					"x": (mob as Node2D).global_position.x,
					"y": (mob as Node2D).global_position.y
				})
		for node in get_children():
			if node is Area2D and String(node.get_script()).contains("food_pickup.gd"):
				var food := node as Area2D
				foods_snapshot.append({
					"id": int(food.get_instance_id()),
					"x": food.global_position.x,
					"y": food.global_position.y
				})

	return {
		"mode": session_mode,
		"score": score,
		"players": players_snapshot,
		"mobs": mobs_snapshot,
		"foods": foods_snapshot
	}


func _apply_host_snapshot(snapshot: Dictionary) -> void:
	score = int(snapshot.get("score", score))
	_update_score_label()

	var players_snapshot: Dictionary = snapshot.get("players", {})
	for key in players_snapshot.keys():
		var peer_id := int(String(key))
		var state: Dictionary = players_snapshot[key]
		var target_player: Node2D = null
		if peer_id == MultiplayerSession.local_peer_id:
			target_player = player
		else:
			var remote_entry: Variant = remote_players.get(peer_id, null)
			if remote_entry is Node2D:
				target_player = remote_entry as Node2D
		if target_player == null:
			if peer_id != MultiplayerSession.local_peer_id:
				_sync_remote_players_from_roster()
				var retry_entry: Variant = remote_players.get(peer_id, null)
				if retry_entry is Node2D:
					target_player = retry_entry as Node2D
		if target_player == null:
			continue
		var previous_position: Vector2 = target_player.global_position
		var next_position: Vector2 = Vector2(
			float(state.get("x", target_player.global_position.x)),
			float(state.get("y", target_player.global_position.y))
		)
		var next_gun_rotation := float(state.get("gun_rotation", _get_player_gun_rotation(target_player)))
		if peer_id == MultiplayerSession.local_peer_id or is_host_session:
			target_player.global_position = next_position
			_set_player_gun_rotation(target_player, next_gun_rotation)
		else:
			remote_target_positions[peer_id] = next_position
			remote_target_gun_rotations[peer_id] = next_gun_rotation
		if target_player.has_method("restore_from_run_state"):
			target_player.restore_from_run_state(float(state.get("health", 100.0)), float(state.get("max_health", 100.0)))
		if peer_id != MultiplayerSession.local_peer_id:
			_update_remote_player_animation(target_player, previous_position, next_position)


func _player_state(player_node: Node) -> Dictionary:
	if not (player_node is Node2D):
		return {}
	var node2d := player_node as Node2D
	return {
		"x": node2d.global_position.x,
		"y": node2d.global_position.y,
		"health": float(player_node.get_current_health()),
		"max_health": float(player_node.get_max_health()),
		"dead": bool(player_node.is_dead_state()),
		"gun_rotation": _get_player_gun_rotation(player_node)
	}


func _get_player_gun_rotation(player_node: Node) -> float:
	var gun := player_node.get_node_or_null("Gun")
	if gun is Node2D:
		return (gun as Node2D).global_rotation
	return 0.0


func _set_player_gun_rotation(player_node: Node, rotation_radians: float) -> void:
	var gun := player_node.get_node_or_null("Gun")
	if gun is Node2D:
		(gun as Node2D).global_rotation = rotation_radians


func _set_player_gun_firing_enabled(player_node: Node, enabled: bool) -> void:
	var gun := player_node.get_node_or_null("Gun")
	if gun and gun.has_method("set_firing_enabled"):
		gun.set_firing_enabled(enabled)


func _mp_debug(message: String) -> void:
	if MULTIPLAYER_DEBUG_LOGS:
		print("[MP] %s" % message)


func _snapshot_player_count(snapshot: Dictionary) -> int:
	var players_snapshot: Variant = snapshot.get("players", {})
	if players_snapshot is Dictionary:
		return (players_snapshot as Dictionary).size()
	return 0


func _interpolate_remote_players(delta: float) -> void:
	var pos_alpha := clampf(delta * remote_position_lerp_speed, 0.0, 1.0)
	var rot_alpha := clampf(delta * remote_rotation_lerp_speed, 0.0, 1.0)
	for peer_id in remote_players.keys():
		var remote_entry: Variant = remote_players[peer_id]
		if not (remote_entry is Node2D):
			continue
		var remote_player := remote_entry as Node2D
		var target_position: Vector2 = remote_target_positions.get(peer_id, remote_player.global_position)
		remote_player.global_position = remote_player.global_position.lerp(target_position, pos_alpha)
		var gun := remote_player.get_node_or_null("Gun")
		if gun is Node2D:
			var gun_node := gun as Node2D
			var target_rotation := float(remote_target_gun_rotations.get(peer_id, gun_node.global_rotation))
			gun_node.global_rotation = lerp_angle(gun_node.global_rotation, target_rotation, rot_alpha)


func _username_for_peer(peer_id: int) -> String:
	var entry: Dictionary = MultiplayerSession.players.get(peer_id, {})
	var username := String(entry.get("username", "Player"))
	if username.strip_edges().is_empty():
		return "Player"
	return username


func _show_multiplayer_end_and_return(message: String) -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	MultiplayerSession.reset_to_single_player()
	SaveManager.clear_pending_continue_run()
	push_warning(message)
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _register_player_projectile_events(player_node: Node, owner_peer_id: int) -> void:
	if player_node == null:
		return
	var gun := player_node.get_node_or_null("Gun")
	if gun == null:
		return
	if not gun.has_signal("projectile_fired"):
		return
	var callback := Callable(self, "_on_player_projectile_fired").bind(owner_peer_id)
	if gun.is_connected("projectile_fired", callback):
		return
	gun.connect("projectile_fired", callback)


func _on_player_projectile_fired(projectile_position: Vector2, projectile_rotation: float, projectile_direction: Vector2, muzzle_position: Vector2, muzzle_rotation: float, owner_peer_id: int) -> void:
	if not is_multiplayer_session or not is_host_session:
		return
	MultiplayerSession.send_host_event({
		"type": "projectile_spawn",
		"owner_peer_id": owner_peer_id,
		"projectile": {
			"x": projectile_position.x,
			"y": projectile_position.y,
			"rotation": projectile_rotation,
			"dx": projectile_direction.x,
			"dy": projectile_direction.y
		},
		"muzzle": {
			"x": muzzle_position.x,
			"y": muzzle_position.y,
			"rotation": muzzle_rotation
		}
	})


func _spawn_network_projectile_visual(event_data: Dictionary) -> void:
	if projectile_scene_mp == null or muzzle_flash_scene_mp == null:
		return
	var projectile_payload: Dictionary = event_data.get("projectile", {})
	var muzzle_payload: Dictionary = event_data.get("muzzle", {})
	var projectile := projectile_scene_mp.instantiate()
	if projectile == null:
		return
	projectile.network_visual_only = true
	projectile.global_position = Vector2(float(projectile_payload.get("x", 0.0)), float(projectile_payload.get("y", 0.0)))
	projectile.rotation = float(projectile_payload.get("rotation", 0.0))
	projectile.direction = Vector2(float(projectile_payload.get("dx", 1.0)), float(projectile_payload.get("dy", 0.0)))
	add_child(projectile)

	var muzzle_flash := muzzle_flash_scene_mp.instantiate()
	if muzzle_flash == null:
		return
	muzzle_flash.global_position = Vector2(float(muzzle_payload.get("x", projectile.global_position.x)), float(muzzle_payload.get("y", projectile.global_position.y)))
	muzzle_flash.global_rotation = float(muzzle_payload.get("rotation", projectile.rotation))
	add_child(muzzle_flash)


func _update_remote_player_animation(player_node: Node, previous_position: Vector2, current_position: Vector2) -> void:
	var visual := player_node.get_node_or_null("HappyBoo")
	if visual == null:
		return
	var distance := current_position.distance_to(previous_position)
	if distance > 0.5:
		if visual.has_method("play_walk_animation"):
			visual.play_walk_animation()
	else:
		if visual.has_method("play_idle_animation"):
			visual.play_idle_animation()


func _check_pvp_winner() -> void:
	if not is_multiplayer_session or not is_host_session or session_mode != "pvp":
		return
	var alive_names: Array[String] = []
	var local_name := _username_for_peer(MultiplayerSession.local_peer_id)
	if not player.is_dead_state():
		alive_names.append(local_name)
	for peer_id in remote_players.keys():
		var node: Variant = remote_players[peer_id]
		if node and is_instance_valid(node) and not node.is_dead_state():
			alive_names.append(_username_for_peer(peer_id))
	if alive_names.size() > 1:
		return
	var message := "PvP ended."
	if alive_names.size() == 1:
		message = "%s wins!" % alive_names[0]
	MultiplayerSession.send_host_event({
		"type": "match_end",
		"message": message
	})
	_show_multiplayer_end_and_return(message)


func _cleanup_pvp_mode_entities() -> void:
	for mob in get_tree().get_nodes_in_group("mobs"):
		if mob and is_instance_valid(mob):
			mob.queue_free()


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if MultiplayerSession != null:
		if MultiplayerSession.relay_input_received.is_connected(_on_network_input_received):
			MultiplayerSession.relay_input_received.disconnect(_on_network_input_received)
		if MultiplayerSession.relay_snapshot_received.is_connected(_on_network_snapshot_received):
			MultiplayerSession.relay_snapshot_received.disconnect(_on_network_snapshot_received)
		if MultiplayerSession.relay_event_received.is_connected(_on_network_event_received):
			MultiplayerSession.relay_event_received.disconnect(_on_network_event_received)
		if MultiplayerSession.roster_updated.is_connected(_on_session_roster_updated):
			MultiplayerSession.roster_updated.disconnect(_on_session_roster_updated)
		if MultiplayerSession.host_disconnected.is_connected(_on_session_host_disconnected):
			MultiplayerSession.host_disconnected.disconnect(_on_session_host_disconnected)


func _physics_process(_delta: float) -> void:
	if is_multiplayer_session:
		_process_multiplayer(_delta)
		if not is_host_session:
			_interpolate_remote_players(_delta)
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
			if is_multiplayer_session or spawn_position.distance_to(player.global_position) >= min_tree_distance_from_player:
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

	if is_multiplayer_session and not is_host_session:
		return

	var allow_mobs := session_mode != "pvp"
	if allow_mobs and mob_scene != null and medium_monster_scene != null and heavy_monster_scene != null and randf() <= mob_spawn_chance_per_chunk:
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

	if food_scene != null and randf() <= food_spawn_chance_per_chunk:
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


func _chunk_rng(chunk: Vector2i, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d:%d" % [salt, chunk.x, chunk.y])
	return rng


func _on_player_died() -> void:
	if is_multiplayer_session:
		if is_host_session:
			_check_pvp_winner()
		return
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
	if is_multiplayer_session:
		MultiplayerSession.leave_room()
		MultiplayerSession.reset_to_single_player()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	crosshair.visible = false
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
	if is_multiplayer_session:
		return
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
	if is_multiplayer_session:
		return {}
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
