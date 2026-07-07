extends Node

signal connection_status_changed(status: String)
signal host_status_changed(is_host: bool)
signal remote_player_state_received(player_id: String, state: Dictionary)
signal remote_player_left(player_id: String)
signal world_message_received(message: Dictionary)

const DEFAULT_URL := "wss://sixtyfold-unhappily-brilliant.ngrok-free.dev"
const DEFAULT_ROOM := "lobby"

var server_url := DEFAULT_URL
var room_id := DEFAULT_ROOM
var local_player_id := ""
var connection_status := "Disconnected"
var is_host := false

var _socket := WebSocketPeer.new()
var _online_run_requested := false
var _has_joined_room := false
var _room_full := false


func _process(_delta: float) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return

	_socket.poll()
	_update_socket_status()

	while _socket.get_available_packet_count() > 0:
		_handle_packet(_socket.get_packet().get_string_from_utf8())


func request_online_run(url: String = DEFAULT_URL, room: String = DEFAULT_ROOM) -> void:
	server_url = url
	room_id = room
	_online_run_requested = true


func consume_online_run_requested() -> bool:
	var requested := _online_run_requested
	_online_run_requested = false
	return requested


func connect_to_server(url: String = server_url, room: String = room_id) -> void:
	disconnect_from_server()
	server_url = url
	room_id = room
	local_player_id = ""
	is_host = false
	_has_joined_room = false
	_room_full = false
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url(server_url)
	if error != OK:
		_set_connection_status("Disconnected")
		return
	_set_connection_status("Connecting")


func disconnect_from_server() -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	local_player_id = ""
	is_host = false
	_has_joined_room = false
	_room_full = false
	emit_signal("host_status_changed", is_host)
	_set_connection_status("Disconnected")


func send_player_state(state: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var payload := state.duplicate(true)
	payload["type"] = "player_state"
	_send_json(payload)


func send_world_message(message_type: String, payload: Dictionary = {}) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var message := payload.duplicate(true)
	message["type"] = message_type
	_send_json(message)


func _update_socket_status() -> void:
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_set_connection_status("Connecting")
		WebSocketPeer.STATE_OPEN:
			if not _has_joined_room:
				_set_connection_status("Connecting")
				_send_json({
					"type": "join",
					"room_id": room_id
				})
				_has_joined_room = true
			else:
				_set_connection_status("Online")
		WebSocketPeer.STATE_CLOSING:
			_set_connection_status("Disconnected")
		WebSocketPeer.STATE_CLOSED:
			if _room_full:
				_set_connection_status(connection_status)
			else:
				_set_connection_status("Disconnected")


func _handle_packet(raw_text: String) -> void:
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		return
	var message := parsed as Dictionary
	var message_type := String(message.get("type", ""))

	match message_type:
		"welcome":
			local_player_id = String(message.get("player_id", ""))
		"host_assigned":
			is_host = bool(message.get("is_host", false))
			emit_signal("host_status_changed", is_host)
		"joined":
			_set_connection_status("Online")
		"room_full":
			_room_full = true
			_set_connection_status("Room Full (%d max)" % int(message.get("max_players", 4)))
		"player_state":
			var player_id := String(message.get("from_player_id", ""))
			if player_id.is_empty() or player_id == local_player_id:
				return
			emit_signal("remote_player_state_received", player_id, message)
		"player_left":
			var player_id := String(message.get("player_id", ""))
			if not player_id.is_empty() and player_id != local_player_id:
				emit_signal("remote_player_left", player_id)
		"world_spawn", "world_snapshot", "mob_state", "mob_died", "food_collect", "food_collected", "projectile_hit", "projectile_fired", "bomb_exploded", "player_joined":
			emit_signal("world_message_received", message)


func _send_json(payload: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(payload))


func _set_connection_status(next_status: String) -> void:
	if connection_status == next_status:
		return
	connection_status = next_status
	emit_signal("connection_status_changed", connection_status)
