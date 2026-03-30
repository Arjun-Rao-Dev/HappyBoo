extends Node

signal status_changed(message: String)
signal connection_changed(connected: bool)
signal roster_updated(players: Dictionary)
signal room_changed(room_code: String)
signal match_started(mode: String)
signal relay_input_received(peer_id: int, input_vector: Vector2)
signal relay_snapshot_received(snapshot: Dictionary)
signal relay_event_received(event_data: Dictionary)
signal host_disconnected(reason: String)

const MAX_PLAYERS := 4
const DEFAULT_SIGNALING_URL := "ws://localhost:8080"

var mode: String = "single"
var is_multiplayer: bool = false
var is_host: bool = false
var room_code: String = ""
var signaling_url: String = DEFAULT_SIGNALING_URL
var local_peer_id: int = -1
var players: Dictionary = {}

var _socket := WebSocketPeer.new()
var _connected := false


func _process(_delta: float) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			emit_signal("connection_changed", false)
		if is_multiplayer and room_code != "":
			emit_signal("status_changed", "Disconnected from signaling server.")
		return

	if _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_socket.poll()
		return

	_socket.poll()
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not _connected:
		_connected = true
		emit_signal("connection_changed", true)
		emit_signal("status_changed", "Connected to signaling server.")
		_send({
			"type": "hello",
			"username": _get_local_username()
		})

	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_handle_message(parsed)


func reset_to_single_player() -> void:
	_leave_room_internal(false)
	mode = "single"
	is_multiplayer = false
	is_host = false
	room_code = ""
	local_peer_id = -1
	players.clear()
	emit_signal("room_changed", room_code)
	emit_signal("roster_updated", players)


func set_mode(new_mode: String) -> void:
	if new_mode != "team" and new_mode != "pvp":
		mode = "single"
		return
	mode = new_mode


func connect_to_signaling(url: String) -> int:
	signaling_url = url.strip_edges()
	if signaling_url.is_empty():
		signaling_url = DEFAULT_SIGNALING_URL
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return OK
	if _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return OK
	var err := _socket.connect_to_url(signaling_url)
	if err != OK:
		emit_signal("status_changed", "Connect failed (%d)." % err)
	return err


func create_room(selected_mode: String) -> void:
	set_mode(selected_mode)
	is_multiplayer = true
	is_host = true
	_send({
		"type": "create_room",
		"mode": mode,
		"max_players": MAX_PLAYERS
	})


func join_room(code: String, selected_mode: String) -> void:
	set_mode(selected_mode)
	is_multiplayer = true
	is_host = false
	_send({
		"type": "join_room",
		"room_code": code.strip_edges().to_upper(),
		"mode": mode
	})


func leave_room() -> void:
	_leave_room_internal(true)


func start_match() -> void:
	if not is_host:
		return
	_send({"type": "start_match"})


func send_input(input_vector: Vector2) -> void:
	if not is_multiplayer or not _connected:
		return
	_send({
		"type": "relay_input",
		"input": {
			"x": input_vector.x,
			"y": input_vector.y
		}
	})


func send_host_snapshot(snapshot: Dictionary) -> void:
	if not is_multiplayer or not is_host or not _connected:
		return
	_send({
		"type": "relay_snapshot",
		"snapshot": snapshot
	})


func send_host_event(event_data: Dictionary) -> void:
	if not is_multiplayer or not is_host or not _connected:
		return
	_send({
		"type": "relay_event",
		"event": event_data
	})


func _leave_room_internal(notify_server: bool) -> void:
	if notify_server and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and room_code != "":
		_send({"type": "leave_room"})
	room_code = ""
	players.clear()
	is_host = false
	emit_signal("room_changed", room_code)
	emit_signal("roster_updated", players)


func _send(payload: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))


func _handle_message(msg: Dictionary) -> void:
	var message_type := String(msg.get("type", ""))
	match message_type:
		"welcome":
			local_peer_id = int(msg.get("peer_id", -1))
		"status":
			emit_signal("status_changed", String(msg.get("message", "")))
		"error":
			emit_signal("status_changed", "Error: %s" % String(msg.get("message", "unknown")))
		"room_created", "room_joined":
			room_code = String(msg.get("room_code", ""))
			is_multiplayer = true
			is_host = int(msg.get("host_peer_id", -1)) == local_peer_id
			players = _players_from_variant(msg.get("players", {}))
			emit_signal("room_changed", room_code)
			emit_signal("roster_updated", players)
			emit_signal("status_changed", "Room %s ready." % room_code)
		"roster":
			players = _players_from_variant(msg.get("players", {}))
			emit_signal("roster_updated", players)
		"start_match":
			mode = String(msg.get("mode", mode))
			is_multiplayer = true
			room_code = String(msg.get("room_code", room_code))
			emit_signal("match_started", mode)
		"relay_input":
			var sender := int(msg.get("from", -1))
			var input_data: Dictionary = msg.get("input", {})
			var input_vec := Vector2(float(input_data.get("x", 0.0)), float(input_data.get("y", 0.0)))
			emit_signal("relay_input_received", sender, input_vec)
		"relay_snapshot":
			var snapshot: Dictionary = msg.get("snapshot", {})
			emit_signal("relay_snapshot_received", snapshot)
		"relay_event":
			var event_data: Dictionary = msg.get("event", {})
			emit_signal("relay_event_received", event_data)
		"host_disconnected":
			emit_signal("host_disconnected", String(msg.get("reason", "Host disconnected.")))
			reset_to_single_player()


func _players_from_variant(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (value is Dictionary):
		return result
	for key in value.keys():
		var peer_id := int(String(key))
		var entry: Variant = value[key]
		if entry is Dictionary:
			result[peer_id] = {
				"username": String(entry.get("username", "Player"))
			}
	return result


func _get_local_username() -> String:
	if SettingsManager == null:
		return "Player"
	var username := SettingsManager.get_username().strip_edges()
	if username.is_empty():
		return "Player"
	return username
