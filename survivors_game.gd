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
const REMOTE_ENTITY_DESPAWN_GRACE_SNAPSHOTS := 3

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
var remote_projectiles: Dictionary = {}
var remote_mob_target_positions: Dictionary = {}
var remote_projectile_target_positions: Dictionary = {}
var remote_projectile_target_rotations: Dictionary = {}
var remote_missing_mobs: Dictionary = {}
var remote_missing_foods: Dictionary = {}
var remote_missing_projectiles: Dictionary = {}
var host_mob_net_ids: Dictionary = {}
var host_food_net_ids: Dictionary = {}
var host_projectile_net_ids: Dictionary = {}
var host_next_mob_net_id: int = 1
var host_next_food_net_id: int = 1
var host_next_projectile_net_id: int = 1
var host_snapshot_seq: int = 0
var latest_snapshot_seq: int = -1
var stale_snapshot_count: int = 0
var mp_created_mobs: int = 0
var mp_updated_mobs: int = 0
var mp_removed_mobs: int = 0
var mp_created_projectiles: int = 0
var mp_updated_projectiles: int = 0
var mp_removed_projectiles: int = 0
var mp_last_debug_log_ms: int = 0
var remote_last_positions: Dictionary = {}
var remote_target_positions: Dictionary = {}
var remote_target_gun_rotations: Dictionary = {}
var snapshot_elapsed := 0.0
var local_input_tick: int = 0

@onready var player = $Player
@onready var player_scene: PackedScene = preload("res://player.tscn")
@onready var projectile_scene_mp: PackedScene = preload("res://pistol/projectile.tscn")
@onready var muzzle_flash_scene_mp: PackedScene = preload("res://pistol/muzzle_flash/muzzle_flash.tscn")
@onready var game_over_ui: CanvasLayer = $GameOverUI
@onready var game_over_label: Label = $GameOverUI/GameOverPanel/CenterBox/VBoxContainer/GameOverLabel
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
				remote_player.set_external_input_vector(move_input)
				if remote_player.has_method("set_external_aim_position"):
					remote_player.set_external_aim_position(aim_input)
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
		MultiplayerSession.send_input({
			"move": input_vec,
			"aim": aim_world,
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
	_mp_debug("input peer=%d tick=%d move=%s" % [peer_id, tick, str(input_frame.get("move", Vector2.ZERO))])


func _on_network_snapshot_received(snapshot: Dictionary) -> void:
	if is_host_session:
		return
	_mp_debug("snapshot received players=%d" % _snapshot_player_count(snapshot))
	_apply_host_snapshot(snapshot)


func _on_network_event_received(event_data: Dictionary) -> void:
	var event_type := String(event_data.get("type", ""))
	if event_type == "match_end":
		var message := String(event_data.get("message", "Match ended."))
		_show_pvp_winner_screen(message)
	elif event_type == "projectile_spawn":
		_spawn_network_muzzle_flash_visual(event_data)


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
	host_snapshot_seq += 1
	var players_snapshot: Dictionary = {}
	players_snapshot[str(MultiplayerSession.local_peer_id)] = _player_state(player)
	for peer_id in remote_players.keys():
		var node: Variant = remote_players[peer_id]
		if node and is_instance_valid(node):
			players_snapshot[str(peer_id)] = _player_state(node)

	var mobs_snapshot: Array = []
	var foods_snapshot: Array = []
	var projectiles_snapshot: Array = []
	var seen_host_mob_instances: Dictionary = {}
	var seen_host_food_instances: Dictionary = {}
	var seen_host_projectile_instances: Dictionary = {}
	if session_mode == "team":
		for mob in get_tree().get_nodes_in_group("mobs"):
			if mob is Node2D:
				var mob_node := mob as Node2D
				var mob_instance_id := int(mob_node.get_instance_id())
				seen_host_mob_instances[mob_instance_id] = true
				mobs_snapshot.append({
					"id": _host_entity_net_id(mob_node, true),
					"x": mob_node.global_position.x,
					"y": mob_node.global_position.y
				})
		for node in get_children():
			if node is Area2D and String(node.get_script()).contains("food_pickup.gd"):
				var food := node as Area2D
				var food_instance_id := int(food.get_instance_id())
				seen_host_food_instances[food_instance_id] = true
				foods_snapshot.append({
					"id": _host_entity_net_id(food, false),
					"x": food.global_position.x,
					"y": food.global_position.y
				})
	for projectile_node in get_tree().get_nodes_in_group("projectiles"):
		if not (projectile_node is Area2D):
			continue
		var projectile := projectile_node as Area2D
		if bool(projectile.get("network_visual_only")):
			continue
		var projectile_instance_id := int(projectile.get_instance_id())
		seen_host_projectile_instances[projectile_instance_id] = true
		var projectile_direction := Vector2.RIGHT
		var raw_direction: Variant = projectile.get("direction")
		if raw_direction is Vector2:
			projectile_direction = raw_direction as Vector2
		projectiles_snapshot.append({
			"id": _host_projectile_net_id(projectile),
			"x": projectile.global_position.x,
			"y": projectile.global_position.y,
			"rotation": projectile.global_rotation,
			"dx": projectile_direction.x,
			"dy": projectile_direction.y
		})
	_host_entity_net_id_gc(host_mob_net_ids, seen_host_mob_instances)
	_host_entity_net_id_gc(host_food_net_ids, seen_host_food_instances)
	_host_entity_net_id_gc(host_projectile_net_ids, seen_host_projectile_instances)

	return {
		"seq": host_snapshot_seq,
		"mode": session_mode,
		"score": score,
		"players": players_snapshot,
		"mobs": mobs_snapshot,
		"foods": foods_snapshot,
		"projectiles": projectiles_snapshot
	}


func _apply_host_snapshot(snapshot: Dictionary) -> void:
	var snapshot_seq := int(snapshot.get("seq", -1))
	if snapshot_seq >= 0 and snapshot_seq <= latest_snapshot_seq:
		stale_snapshot_count += 1
		return
	if snapshot_seq >= 0:
		latest_snapshot_seq = snapshot_seq

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

	if not is_host_session:
		_apply_remote_mobs_snapshot(snapshot.get("mobs", []))
		_apply_remote_foods_snapshot(snapshot.get("foods", []))
		_apply_remote_projectiles_snapshot(snapshot.get("projectiles", []))
		_maybe_log_mp_state()


func _host_entity_net_id(node: Node2D, is_mob: bool) -> String:
	var instance_id := int(node.get_instance_id())
	var table := host_mob_net_ids if is_mob else host_food_net_ids
	if table.has(instance_id):
		return String(table[instance_id])
	var next_id := host_next_mob_net_id if is_mob else host_next_food_net_id
	var generated := "%s%d" % ["m" if is_mob else "f", next_id]
	table[instance_id] = generated
	if is_mob:
		host_next_mob_net_id += 1
	else:
		host_next_food_net_id += 1
	return generated


func _host_projectile_net_id(projectile_node: Area2D) -> String:
	var instance_id := int(projectile_node.get_instance_id())
	if host_projectile_net_ids.has(instance_id):
		return String(host_projectile_net_ids[instance_id])
	var generated := "p%d" % host_next_projectile_net_id
	host_projectile_net_ids[instance_id] = generated
	host_next_projectile_net_id += 1
	return generated


func _host_entity_net_id_gc(table: Dictionary, seen_instances: Dictionary) -> void:
	var stale: Array = []
	for instance_id in table.keys():
		if seen_instances.has(instance_id):
			continue
		stale.append(instance_id)
	for instance_id in stale:
		table.erase(instance_id)


func _apply_remote_mobs_snapshot(mobs_payload: Variant) -> void:
	if not (mobs_payload is Array):
		return
	var snapshot_mobs := mobs_payload as Array
	var seen_ids: Dictionary = {}
	for entry_var in snapshot_mobs:
		if not (entry_var is Dictionary):
			continue
		var entry := entry_var as Dictionary
		var mob_id := String(entry.get("id", "")).strip_edges()
		if mob_id.is_empty():
			continue
		seen_ids[mob_id] = true
		var mob_node: Node2D = null
		var is_new := false
		var existing: Variant = remote_mobs.get(mob_id, null)
		if existing is Node2D and is_instance_valid(existing):
			mob_node = existing as Node2D
		else:
			if mob_scene == null:
				continue
			var created := mob_scene.instantiate()
			if not (created is Node2D):
				if created:
					created.queue_free()
				continue
			mob_node = created as Node2D
			_configure_remote_world_visual_entity(mob_node, true)
			add_child(mob_node)
			remote_mobs[mob_id] = mob_node
			is_new = true
			mp_created_mobs += 1
		var next_position := Vector2(float(entry.get("x", mob_node.global_position.x)), float(entry.get("y", mob_node.global_position.y)))
		remote_mob_target_positions[mob_id] = next_position
		if is_new:
			mob_node.global_position = next_position
		remote_missing_mobs.erase(mob_id)
		mp_updated_mobs += 1
		if mob_node.has_method("set_physics_process"):
			mob_node.set_physics_process(false)
		if mob_node.has_method("set_process"):
			mob_node.set_process(false)
	var to_remove: Array = []
	for mob_id in remote_mobs.keys():
		if seen_ids.has(mob_id):
			continue
		var missed := int(remote_missing_mobs.get(mob_id, 0)) + 1
		remote_missing_mobs[mob_id] = missed
		if missed < REMOTE_ENTITY_DESPAWN_GRACE_SNAPSHOTS:
			continue
		to_remove.append(mob_id)
	for mob_id in to_remove:
		var mob_var: Variant = remote_mobs[mob_id]
		if mob_var and is_instance_valid(mob_var):
			mob_var.queue_free()
		remote_mobs.erase(mob_id)
		remote_mob_target_positions.erase(mob_id)
		remote_missing_mobs.erase(mob_id)
		mp_removed_mobs += 1


func _apply_remote_foods_snapshot(foods_payload: Variant) -> void:
	if not (foods_payload is Array):
		return
	var snapshot_foods := foods_payload as Array
	var seen_ids: Dictionary = {}
	for entry_var in snapshot_foods:
		if not (entry_var is Dictionary):
			continue
		var entry := entry_var as Dictionary
		var food_id := String(entry.get("id", "")).strip_edges()
		if food_id.is_empty():
			continue
		seen_ids[food_id] = true
		var food_node: Node2D = null
		var existing: Variant = remote_foods.get(food_id, null)
		if existing is Node2D and is_instance_valid(existing):
			food_node = existing as Node2D
		else:
			if food_scene == null:
				continue
			var created := food_scene.instantiate()
			if not (created is Node2D):
				if created:
					created.queue_free()
				continue
			food_node = created as Node2D
			_configure_remote_world_visual_entity(food_node, false)
			add_child(food_node)
			remote_foods[food_id] = food_node
		food_node.global_position = Vector2(float(entry.get("x", food_node.global_position.x)), float(entry.get("y", food_node.global_position.y)))
		remote_missing_foods.erase(food_id)
	var to_remove: Array = []
	for food_id in remote_foods.keys():
		if seen_ids.has(food_id):
			continue
		var missed := int(remote_missing_foods.get(food_id, 0)) + 1
		remote_missing_foods[food_id] = missed
		if missed < REMOTE_ENTITY_DESPAWN_GRACE_SNAPSHOTS:
			continue
		to_remove.append(food_id)
	for food_id in to_remove:
		var food_var: Variant = remote_foods[food_id]
		if food_var and is_instance_valid(food_var):
			food_var.queue_free()
		remote_foods.erase(food_id)
		remote_missing_foods.erase(food_id)


func _apply_remote_projectiles_snapshot(projectiles_payload: Variant) -> void:
	if not (projectiles_payload is Array):
		return
	var snapshot_projectiles := projectiles_payload as Array
	var seen_ids: Dictionary = {}
	for entry_var in snapshot_projectiles:
		if not (entry_var is Dictionary):
			continue
		var entry := entry_var as Dictionary
		var projectile_id := String(entry.get("id", "")).strip_edges()
		if projectile_id.is_empty():
			continue
		seen_ids[projectile_id] = true
		var projectile_node: Area2D = null
		var is_new := false
		var existing: Variant = remote_projectiles.get(projectile_id, null)
		if existing is Area2D and is_instance_valid(existing):
			projectile_node = existing as Area2D
		else:
			if projectile_scene_mp == null:
				continue
			var created := projectile_scene_mp.instantiate()
			if not (created is Area2D):
				if created:
					created.queue_free()
				continue
			projectile_node = created as Area2D
			projectile_node.set("network_visual_only", true)
			_configure_remote_world_visual_entity(projectile_node, false)
			add_child(projectile_node)
			remote_projectiles[projectile_id] = projectile_node
			is_new = true
			mp_created_projectiles += 1
		var next_position := Vector2(
			float(entry.get("x", projectile_node.global_position.x)),
			float(entry.get("y", projectile_node.global_position.y))
		)
		remote_projectile_target_positions[projectile_id] = next_position
		var next_rotation := float(entry.get("rotation", projectile_node.global_rotation))
		remote_projectile_target_rotations[projectile_id] = next_rotation
		if is_new:
			projectile_node.global_position = next_position
			projectile_node.global_rotation = next_rotation
		projectile_node.set("direction", Vector2(
			float(entry.get("dx", 1.0)),
			float(entry.get("dy", 0.0))
		))
		remote_missing_projectiles.erase(projectile_id)
		mp_updated_projectiles += 1
		if projectile_node.has_method("set_physics_process"):
			projectile_node.set_physics_process(false)
		if projectile_node.has_method("set_process"):
			projectile_node.set_process(false)
	var to_remove: Array = []
	for projectile_id in remote_projectiles.keys():
		if seen_ids.has(projectile_id):
			continue
		var missed := int(remote_missing_projectiles.get(projectile_id, 0)) + 1
		remote_missing_projectiles[projectile_id] = missed
		if missed < REMOTE_ENTITY_DESPAWN_GRACE_SNAPSHOTS:
			continue
		to_remove.append(projectile_id)
	for projectile_id in to_remove:
		var projectile_var: Variant = remote_projectiles[projectile_id]
		if projectile_var and is_instance_valid(projectile_var):
			projectile_var.queue_free()
		remote_projectiles.erase(projectile_id)
		remote_projectile_target_positions.erase(projectile_id)
		remote_projectile_target_rotations.erase(projectile_id)
		remote_missing_projectiles.erase(projectile_id)
		mp_removed_projectiles += 1


func _configure_remote_world_visual_entity(node: Node, is_mob: bool) -> void:
	if node.has_method("set_physics_process"):
		node.set_physics_process(false)
	if node.has_method("set_process"):
		node.set_process(false)
	if is_mob and node.is_in_group("mobs"):
		node.remove_from_group("mobs")
	if not is_mob and node.is_in_group("foods"):
		node.remove_from_group("foods")
	var collision_object: CollisionObject2D = null
	if node is CollisionObject2D:
		collision_object = node as CollisionObject2D
	if collision_object != null:
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
		if collision_object is Area2D:
			var area := collision_object as Area2D
			area.monitoring = false
			area.monitorable = false
	for child in node.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true
		elif child is CollisionPolygon2D:
			(child as CollisionPolygon2D).disabled = true


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


func _maybe_log_mp_state() -> void:
	if not MULTIPLAYER_DEBUG_LOGS:
		return
	var now_ms := Time.get_ticks_msec()
	if now_ms - mp_last_debug_log_ms < 1000:
		return
	mp_last_debug_log_ms = now_ms
	print("[MP] seq=%d stale=%d mobs(c/u/r=%d/%d/%d live=%d) proj(c/u/r=%d/%d/%d live=%d)" % [
		latest_snapshot_seq,
		stale_snapshot_count,
		mp_created_mobs,
		mp_updated_mobs,
		mp_removed_mobs,
		remote_mobs.size(),
		mp_created_projectiles,
		mp_updated_projectiles,
		mp_removed_projectiles,
		remote_projectiles.size()
	])


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


func _interpolate_remote_world_entities(delta: float) -> void:
	var mob_alpha := clampf(delta * remote_position_lerp_speed, 0.0, 1.0)
	for mob_id in remote_mobs.keys():
		var mob_entry: Variant = remote_mobs[mob_id]
		if not (mob_entry is Node2D):
			continue
		var mob_node := mob_entry as Node2D
		var target_position: Vector2 = remote_mob_target_positions.get(mob_id, mob_node.global_position)
		mob_node.global_position = mob_node.global_position.lerp(target_position, mob_alpha)

	var projectile_pos_alpha := clampf(delta * (remote_position_lerp_speed * 1.2), 0.0, 1.0)
	var projectile_rot_alpha := clampf(delta * remote_rotation_lerp_speed, 0.0, 1.0)
	for projectile_id in remote_projectiles.keys():
		var projectile_entry: Variant = remote_projectiles[projectile_id]
		if not (projectile_entry is Area2D):
			continue
		var projectile_node := projectile_entry as Area2D
		var target_position: Vector2 = remote_projectile_target_positions.get(projectile_id, projectile_node.global_position)
		projectile_node.global_position = projectile_node.global_position.lerp(target_position, projectile_pos_alpha)
		var target_rotation := float(remote_projectile_target_rotations.get(projectile_id, projectile_node.global_rotation))
		projectile_node.global_rotation = lerp_angle(projectile_node.global_rotation, target_rotation, projectile_rot_alpha)


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


func _show_pvp_winner_screen(message: String) -> void:
	if not is_multiplayer_session:
		_show_multiplayer_end_and_return(message)
		return
	get_tree().paused = true
	crosshair.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	game_music.stream_paused = true
	game_over_ui.visible = true
	game_over_label.text = message
	restart_button.visible = false
	quit_to_title_button.text = "Back to Title"
	quit_to_title_button.grab_focus()


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


func _spawn_network_muzzle_flash_visual(event_data: Dictionary) -> void:
	if muzzle_flash_scene_mp == null:
		return
	var muzzle_payload: Dictionary = event_data.get("muzzle", {})
	var muzzle_flash := muzzle_flash_scene_mp.instantiate()
	if muzzle_flash == null:
		return
	muzzle_flash.global_position = Vector2(float(muzzle_payload.get("x", 0.0)), float(muzzle_payload.get("y", 0.0)))
	muzzle_flash.global_rotation = float(muzzle_payload.get("rotation", 0.0))
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
		message = "%s Wins!" % alive_names[0]
	MultiplayerSession.send_host_event({
		"type": "match_end",
		"message": message
	})
	_show_pvp_winner_screen(message)


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
			_interpolate_remote_world_entities(_delta)
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
