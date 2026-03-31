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
const DEFAULT_RELAY_URL := "ws://127.0.0.1:8080"

enum TransportMode {
	NONE,
	LAN_ENET,
	WEB_RELAY
}

var mode: String = "single"
var is_multiplayer: bool = false
var is_host: bool = false
var room_code: String = ""
var local_peer_id: int = 1
var players: Dictionary = {}
var active_port: int = -1
var transport_mode: TransportMode = TransportMode.NONE
var active_relay_url: String = DEFAULT_RELAY_URL

var _enet_peer: ENetMultiplayerPeer
var _relay_peer: WebSocketPeer
var _relay_was_connected := false
var _relay_join_pending := false
var _relay_create_pending := false
var _relay_outbox: Array[String] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if transport_mode == TransportMode.WEB_RELAY:
		_poll_relay()


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


func host_session(port: int = DEFAULT_PORT, relay_url: String = DEFAULT_RELAY_URL, max_players: int = MAX_PLAYERS) -> int:
	if OS.has_feature("web"):
		return host_web_relay(relay_url, max_players)
	return host_lan(port, max_players)


func join_session(host_or_room: String, port: int = DEFAULT_PORT, relay_url: String = DEFAULT_RELAY_URL) -> int:
	if OS.has_feature("web"):
		return join_web_relay(relay_url, host_or_room)
	return join_lan(host_or_room, port)


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
	transport_mode = TransportMode.LAN_ENET
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
	transport_mode = TransportMode.LAN_ENET
	is_multiplayer = true
	is_host = false
	room_code = "LAN"
	active_port = normalized_port
	players.clear()
	emit_signal("status_changed", "Joining %s:%d..." % [target_host, normalized_port])
	emit_signal("room_changed", room_code)
	return OK


func host_web_relay(relay_url: String, max_players: int = MAX_PLAYERS) -> int:
	leave_session()
	var normalized_url := _normalized_relay_url(relay_url)
	if normalized_url.is_empty():
		emit_signal("status_changed", "Relay URL is required.")
		return ERR_INVALID_PARAMETER

	_relay_peer = WebSocketPeer.new()
	var err := _relay_peer.connect_to_url(normalized_url)
	if err != OK:
		_relay_peer = null
		emit_signal("status_changed", "Relay connection failed (%d)." % err)
		return err

	transport_mode = TransportMode.WEB_RELAY
	active_relay_url = normalized_url
	active_port = -1
	room_code = ""
	is_multiplayer = true
	is_host = true
	local_peer_id = 1
	players.clear()
	_relay_create_pending = true
	_relay_join_pending = false
	_relay_was_connected = false
	var normalized_max := clampi(max_players, 2, MAX_PLAYERS)
	emit_signal("status_changed", "Connecting to relay host...")
	_queue_relay_message({
		"type": "create_room",
		"max_players": normalized_max,
		"username": _get_local_username(),
		"mode": mode
	})
	return OK


func join_web_relay(relay_url: String, target_room_code: String) -> int:
	leave_session()
	var normalized_url := _normalized_relay_url(relay_url)
	if normalized_url.is_empty():
		emit_signal("status_changed", "Relay URL is required.")
		return ERR_INVALID_PARAMETER
	var normalized_room := target_room_code.strip_edges().to_upper()
	if normalized_room.is_empty():
		emit_signal("status_changed", "Room code is required.")
		return ERR_INVALID_PARAMETER

	_relay_peer = WebSocketPeer.new()
	var err := _relay_peer.connect_to_url(normalized_url)
	if err != OK:
		_relay_peer = null
		emit_signal("status_changed", "Relay connection failed (%d)." % err)
		return err

	transport_mode = TransportMode.WEB_RELAY
	active_relay_url = normalized_url
	active_port = -1
	room_code = normalized_room
	is_multiplayer = true
	is_host = false
	local_peer_id = 0
	players.clear()
	_relay_create_pending = false
	_relay_join_pending = true
	_relay_was_connected = false
	emit_signal("status_changed", "Connecting to relay and joining %s..." % room_code)
	_queue_relay_message({
		"type": "join_room",
		"room_code": room_code,
		"username": _get_local_username()
	})
	return OK


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if _relay_peer != null:
		if _relay_peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_queue_relay_message({"type": "leave"})
			_flush_relay_outbox()
		_relay_peer.close()
	_relay_peer = null
	_relay_create_pending = false
	_relay_join_pending = false
	_relay_was_connected = false
	_relay_outbox.clear()
	_enet_peer = null
	transport_mode = TransportMode.NONE
	is_multiplayer = false
	is_host = false
	room_code = ""
	active_port = -1
	local_peer_id = 1
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
	if transport_mode == TransportMode.WEB_RELAY:
		_queue_relay_message({"type": "start_match", "mode": mode})
		_flush_relay_outbox()
		return
	_rpc_start_match.rpc(mode)
	_on_match_started(mode)


func send_input(input_frame: Dictionary) -> void:
	if not is_multiplayer:
		return
	if is_host:
		return
	if transport_mode == TransportMode.WEB_RELAY:
		_queue_relay_message({"type": "input", "payload": input_frame})
		_flush_relay_outbox()
		return
	_rpc_relay_input.rpc_id(1, input_frame)


func send_host_snapshot(snapshot: Dictionary) -> void:
	if not is_multiplayer or not is_host:
		return
	if transport_mode == TransportMode.WEB_RELAY:
		_queue_relay_message({"type": "snapshot", "payload": snapshot})
		_flush_relay_outbox()
		return
	_rpc_relay_snapshot.rpc(snapshot)


func send_host_event(event_data: Dictionary) -> void:
	if not is_multiplayer or not is_host:
		return
	if transport_mode == TransportMode.WEB_RELAY:
		_queue_relay_message({"type": "event", "payload": event_data})
		_flush_relay_outbox()
		return
	_rpc_relay_event.rpc(event_data)


func _poll_relay() -> void:
	if _relay_peer == null:
		return
	_relay_peer.poll()
	var state := _relay_peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _relay_was_connected:
			_relay_was_connected = true
			emit_signal("connection_changed", true)
			if _relay_create_pending:
				emit_signal("status_changed", "Creating relay room...")
			elif _relay_join_pending:
				emit_signal("status_changed", "Joining relay room %s..." % room_code)
		_flush_relay_outbox()
		while _relay_peer.get_available_packet_count() > 0:
			var packet := _relay_peer.get_packet()
			var text := packet.get_string_from_utf8()
			_handle_relay_packet(text)
		return
	if state == WebSocketPeer.STATE_CONNECTING:
		return
	if _relay_was_connected:
		_handle_relay_disconnect("Relay disconnected.")
	else:
		_handle_relay_disconnect("Could not connect to relay.")


func _handle_relay_packet(packet_text: String) -> void:
	var parsed: Variant = JSON.parse_string(packet_text)
	if not (parsed is Dictionary):
		return
	var message := parsed as Dictionary
	var message_type := String(message.get("type", ""))
	match message_type:
		"room_created":
			room_code = String(message.get("room_code", "")).to_upper()
			local_peer_id = int(message.get("peer_id", 1))
			is_host = true
			is_multiplayer = true
			_relay_create_pending = false
			emit_signal("room_changed", room_code)
			emit_signal("status_changed", "Relay room %s created." % room_code)
			if message.has("roster"):
				_apply_relay_roster(message.get("roster", {}))
		"join_ok":
			room_code = String(message.get("room_code", room_code)).to_upper()
			local_peer_id = int(message.get("peer_id", 0))
			is_host = bool(message.get("is_host", false))
			is_multiplayer = true
			_relay_join_pending = false
			emit_signal("room_changed", room_code)
			emit_signal("status_changed", "Joined relay room %s." % room_code)
			if message.has("roster"):
				_apply_relay_roster(message.get("roster", {}))
		"roster":
			_apply_relay_roster(message.get("players", {}))
		"match_started":
			_on_match_started(String(message.get("mode", mode)))
		"relay_input":
			var sender_id := int(message.get("peer_id", 0))
			var input_payload: Variant = message.get("payload", {})
			if input_payload is Dictionary and sender_id > 0:
				emit_signal("relay_input_received", sender_id, input_payload)
		"relay_snapshot":
			var snapshot_payload: Variant = message.get("payload", {})
			if snapshot_payload is Dictionary:
				emit_signal("relay_snapshot_received", snapshot_payload)
		"relay_event":
			var event_payload: Variant = message.get("payload", {})
			if event_payload is Dictionary:
				emit_signal("relay_event_received", event_payload)
		"host_disconnected":
			var reason := String(message.get("reason", "Host disconnected."))
			emit_signal("host_disconnected", reason)
			leave_session()
		"error":
			var err_message := String(message.get("message", "Relay error."))
			emit_signal("status_changed", err_message)
			if _relay_create_pending or _relay_join_pending:
				leave_session()


func _apply_relay_roster(roster_payload: Variant) -> void:
	var source: Dictionary = {}
	if roster_payload is Dictionary:
		source = roster_payload
	players.clear()
	for key in source.keys():
		var peer_id := int(key)
		if peer_id <= 0:
			continue
		var entry: Variant = source[key]
		if entry is Dictionary:
			players[peer_id] = {"username": String((entry as Dictionary).get("username", "Player"))}
	emit_signal("roster_updated", players)


func _queue_relay_message(payload: Dictionary) -> void:
	_relay_outbox.append(JSON.stringify(payload))


func _flush_relay_outbox() -> void:
	if _relay_peer == null:
		return
	if _relay_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while not _relay_outbox.is_empty():
		var payload := _relay_outbox.pop_front()
		_relay_peer.send_text(payload)


func _handle_relay_disconnect(reason: String) -> void:
	if not is_multiplayer:
		return
	emit_signal("host_disconnected", reason)
	leave_session()


func _normalized_relay_url(raw_url: String) -> String:
	var url := raw_url.strip_edges()
	if url.is_empty():
		url = DEFAULT_RELAY_URL
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://%s" % url
	return url


func _on_peer_connected(peer_id: int) -> void:
	if transport_mode != TransportMode.LAN_ENET:
		return
	if not is_multiplayer:
		return
	if is_host:
		if not players.has(peer_id):
			players[peer_id] = {"username": "Player%d" % peer_id}
		_broadcast_roster()


func _on_peer_disconnected(peer_id: int) -> void:
	if transport_mode != TransportMode.LAN_ENET:
		return
	if not is_multiplayer:
		return
	players.erase(peer_id)
	emit_signal("roster_updated", players)
	if is_host:
		_broadcast_roster()


func _on_connected_to_server() -> void:
	if transport_mode != TransportMode.LAN_ENET:
		return
	is_multiplayer = true
	is_host = false
	local_peer_id = multiplayer.get_unique_id()
	emit_signal("connection_changed", true)
	emit_signal("status_changed", "Connected to LAN host.")
	_rpc_set_username.rpc_id(1, _get_local_username())


func _on_connection_failed() -> void:
	if transport_mode != TransportMode.LAN_ENET:
		return
	emit_signal("status_changed", "Could not connect to LAN host.")
	leave_session()


func _on_server_disconnected() -> void:
	if transport_mode != TransportMode.LAN_ENET:
		return
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
