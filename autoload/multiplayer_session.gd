extends Node

signal status_changed(message: String)
signal connection_changed(connected: bool)
signal roster_updated(players: Dictionary)
signal room_changed(room_code: String)
signal match_started(mode: String)
signal relay_input_received(peer_id: int, input_frame: Dictionary)
signal relay_snapshot_received(snapshot: Dictionary)
signal relay_event_received(event_data: Dictionary)
signal host_disconnected(reason: String)

const MAX_PLAYERS := 4
const DEFAULT_PORT := 7000
const DEFAULT_HOST := "127.0.0.1"
const HOST_PORT_SCAN_SPAN := 50

var mode: String = "single"
var is_multiplayer: bool = false
var is_host: bool = false
var room_code: String = ""
var local_peer_id: int = 1
var players: Dictionary = {}
var active_port: int = -1

var _enet_peer: ENetMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func reset_to_single_player() -> void:
	leave_session()
	mode = "single"
	is_multiplayer = false
	is_host = false
	room_code = ""
	local_peer_id = 1
	active_port = -1
	players.clear()
	emit_signal("room_changed", room_code)
	emit_signal("roster_updated", players)


func set_mode(new_mode: String) -> void:
	if new_mode != "team" and new_mode != "pvp":
		mode = "single"
		return
	mode = new_mode


func host_lan(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> int:
	leave_session()
	if OS.has_feature("web"):
		emit_signal("status_changed", "LAN host is not supported in browser builds.")
		return ERR_UNAVAILABLE

	var start_port := clampi(port, 1, 65535)
	var normalized_max := clampi(max_players, 2, MAX_PLAYERS)
	var selected_port := -1
	var last_err := OK
	for offset in range(HOST_PORT_SCAN_SPAN + 1):
		var try_port := start_port + offset
		if try_port > 65535:
			break
		_enet_peer = ENetMultiplayerPeer.new()
		var err := _enet_peer.create_server(try_port, normalized_max)
		if err == OK:
			selected_port = try_port
			break
		last_err = err
		_enet_peer = null
	if selected_port == -1:
		emit_signal("status_changed", "No free LAN port in range %d-%d (last error %d)." % [start_port, min(start_port + HOST_PORT_SCAN_SPAN, 65535), last_err])
		return last_err

	multiplayer.multiplayer_peer = _enet_peer
	is_multiplayer = true
	is_host = true
	local_peer_id = multiplayer.get_unique_id()
	active_port = selected_port
	room_code = "LAN"
	players = {
		local_peer_id: {"username": _get_local_username()}
	}
	emit_signal("connection_changed", true)
	emit_signal("status_changed", "Hosting LAN on port %d." % selected_port)
	emit_signal("room_changed", room_code)
	emit_signal("roster_updated", players)
	return OK


func join_lan(host_ip: String, port: int = DEFAULT_PORT) -> int:
	leave_session()
	if OS.has_feature("web"):
		emit_signal("status_changed", "LAN join is not supported in browser builds.")
		return ERR_UNAVAILABLE

	var target_host := host_ip.strip_edges()
	if target_host.is_empty():
		target_host = DEFAULT_HOST
	var normalized_port := clampi(port, 1, 65535)
	_enet_peer = ENetMultiplayerPeer.new()
	var err := _enet_peer.create_client(target_host, normalized_port)
	if err != OK:
		emit_signal("status_changed", "Join failed (%d)." % err)
		return err

	multiplayer.multiplayer_peer = _enet_peer
	is_multiplayer = true
	is_host = false
	room_code = "LAN"
	active_port = normalized_port
	players.clear()
	emit_signal("status_changed", "Joining %s:%d..." % [target_host, normalized_port])
	emit_signal("room_changed", room_code)
	return OK


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_enet_peer = null
	is_multiplayer = false
	is_host = false
	room_code = ""
	active_port = -1
	players.clear()
	emit_signal("connection_changed", false)
	emit_signal("room_changed", room_code)
	emit_signal("roster_updated", players)


func leave_room() -> void:
	leave_session()


func start_match() -> void:
	if not is_multiplayer or not is_host:
		return
	if players.size() < 1:
		emit_signal("status_changed", "Need at least 1 player to start.")
		return
	_rpc_start_match.rpc(mode)
	_on_match_started(mode)


func send_input(input_frame: Dictionary) -> void:
	if not is_multiplayer:
		return
	if is_host:
		return
	_rpc_relay_input.rpc_id(1, input_frame)


func send_host_snapshot(snapshot: Dictionary) -> void:
	if not is_multiplayer or not is_host:
		return
	_rpc_relay_snapshot.rpc(snapshot)


func send_host_event(event_data: Dictionary) -> void:
	if not is_multiplayer or not is_host:
		return
	_rpc_relay_event.rpc(event_data)


func _on_peer_connected(peer_id: int) -> void:
	if not is_multiplayer:
		return
	if is_host:
		if not players.has(peer_id):
			players[peer_id] = {"username": "Player%d" % peer_id}
		_broadcast_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_multiplayer:
		return
	players.erase(peer_id)
	emit_signal("roster_updated", players)
	if is_host:
		_broadcast_roster()


func _on_connected_to_server() -> void:
	is_multiplayer = true
	is_host = false
	local_peer_id = multiplayer.get_unique_id()
	emit_signal("connection_changed", true)
	emit_signal("status_changed", "Connected to LAN host.")
	_rpc_set_username.rpc_id(1, _get_local_username())


func _on_connection_failed() -> void:
	emit_signal("status_changed", "Could not connect to LAN host.")
	leave_session()


func _on_server_disconnected() -> void:
	emit_signal("host_disconnected", "Host disconnected.")
	leave_session()


func _broadcast_roster() -> void:
	_rpc_receive_roster.rpc(players)
	emit_signal("roster_updated", players)


func _on_match_started(start_mode: String) -> void:
	mode = start_mode
	is_multiplayer = true
	emit_signal("match_started", mode)


@rpc("authority", "reliable")
func _rpc_start_match(start_mode: String) -> void:
	_on_match_started(start_mode)


@rpc("any_peer", "reliable")
func _rpc_set_username(username: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	var clean_name := username.strip_edges()
	if clean_name.is_empty():
		clean_name = "Player%d" % sender
	players[sender] = {"username": clean_name}
	_broadcast_roster()


@rpc("authority", "reliable")
func _rpc_receive_roster(roster: Dictionary) -> void:
	players = {}
	for key in roster.keys():
		var peer_id := int(key)
		var entry: Variant = roster[key]
		if entry is Dictionary:
			players[peer_id] = {"username": String(entry.get("username", "Player"))}
	emit_signal("roster_updated", players)


@rpc("any_peer", "unreliable")
func _rpc_relay_input(input_frame: Dictionary) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	emit_signal("relay_input_received", sender, input_frame)


@rpc("authority", "unreliable")
func _rpc_relay_snapshot(snapshot: Dictionary) -> void:
	if is_host:
		return
	emit_signal("relay_snapshot_received", snapshot)


@rpc("authority", "reliable")
func _rpc_relay_event(event_data: Dictionary) -> void:
	if is_host:
		return
	emit_signal("relay_event_received", event_data)


func _get_local_username() -> String:
	if SettingsManager == null:
		return "Player"
	var username := SettingsManager.get_username().strip_edges()
	if username.is_empty():
		return "Player"
	return username
