extends Control

@onready var mode_option: OptionButton = $CenterContainer/Panel/Margin/VBox/ModeRow/ModeOption
@onready var host_row: HBoxContainer = $CenterContainer/Panel/Margin/VBox/HostRow
@onready var host_label: Label = $CenterContainer/Panel/Margin/VBox/HostRow/HostLabel
@onready var host_port_input: LineEdit = $CenterContainer/Panel/Margin/VBox/HostRow/HostPortInput
@onready var join_row: HBoxContainer = $CenterContainer/Panel/Margin/VBox/JoinRow
@onready var join_ip_input: LineEdit = $CenterContainer/Panel/Margin/VBox/JoinRow/JoinIpInput
@onready var join_port_input: LineEdit = $CenterContainer/Panel/Margin/VBox/JoinRow/JoinPortInput
@onready var relay_row: HBoxContainer = $CenterContainer/Panel/Margin/VBox/RelayRow
@onready var relay_url_input: LineEdit = $CenterContainer/Panel/Margin/VBox/RelayRow/RelayUrlInput
@onready var room_row: HBoxContainer = $CenterContainer/Panel/Margin/VBox/RoomRow
@onready var room_code_input: LineEdit = $CenterContainer/Panel/Margin/VBox/RoomRow/RoomCodeInput
@onready var session_label: Label = $CenterContainer/Panel/Margin/VBox/SessionLabel
@onready var players_list: ItemList = $CenterContainer/Panel/Margin/VBox/PlayersList
@onready var host_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonsRow/HostButton
@onready var join_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonsRow/JoinButton
@onready var start_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonsRow/StartButton
@onready var leave_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonsRow/LeaveButton
@onready var back_button: Button = $CenterContainer/Panel/Margin/VBox/BottomRow/BackButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/VBox/StatusLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	mode_option.clear()
	mode_option.add_item("Team")
	mode_option.add_item("PvP")
	host_port_input.text = str(MultiplayerSession.DEFAULT_PORT)
	join_ip_input.text = MultiplayerSession.DEFAULT_HOST
	join_port_input.text = str(MultiplayerSession.DEFAULT_PORT)
	if OS.has_feature("web"):
		relay_url_input.text = MultiplayerSession.DEFAULT_RELAY_URL
	else:
		relay_url_input.text = MultiplayerSession.LOCAL_DEBUG_RELAY_URL
	room_code_input.text = ""
	session_label.text = "Session: -"
	status_label.text = "Host a multiplayer session or join one."

	if OS.has_feature("web"):
		host_label.text = "Host Port"
		status_label.text = "Web mode uses a relay URL and room code."
		_show_web_inputs(true)
	else:
		host_label.text = "Host Port"
		_show_web_inputs(false)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	back_button.pressed.connect(_on_back_pressed)

	MultiplayerSession.status_changed.connect(_on_status_changed)
	MultiplayerSession.roster_updated.connect(_on_roster_updated)
	MultiplayerSession.room_changed.connect(_on_room_changed)
	MultiplayerSession.match_started.connect(_on_match_started)
	MultiplayerSession.host_disconnected.connect(_on_host_disconnected)

	_refresh_buttons()
	_update_roster_list(MultiplayerSession.players)


func _show_web_inputs(web_mode: bool) -> void:
	host_row.visible = not web_mode
	join_row.visible = not web_mode
	relay_row.visible = web_mode
	room_row.visible = web_mode


func _selected_mode() -> String:
	if mode_option.selected == 1:
		return "pvp"
	return "team"


func _parsed_port(input: LineEdit) -> int:
	var raw := input.text.strip_edges()
	if raw.is_empty():
		return MultiplayerSession.DEFAULT_PORT
	var parsed := int(raw)
	return clampi(parsed, 1, 65535)


func _normalized_room_code() -> String:
	return room_code_input.text.strip_edges().to_upper()


func _normalized_relay_url() -> String:
	return relay_url_input.text.strip_edges()


func _on_host_pressed() -> void:
	MultiplayerSession.set_mode(_selected_mode())
	var err := MultiplayerSession.host_session(_parsed_port(host_port_input), _normalized_relay_url(), MultiplayerSession.MAX_PLAYERS)
	if err != OK:
		status_label.text = "Could not host multiplayer (error %d)." % err
	else:
		if OS.has_feature("web"):
			status_label.text = "Connecting to relay..."
		else:
			var port := MultiplayerSession.active_port
			if port > 0:
				session_label.text = "Session: LAN (%d)" % port
				status_label.text = "Hosting LAN on port %d." % port
	_refresh_buttons()


func _on_join_pressed() -> void:
	MultiplayerSession.set_mode(_selected_mode())
	var err := OK
	if OS.has_feature("web"):
		var room := _normalized_room_code()
		err = MultiplayerSession.join_session(room, MultiplayerSession.DEFAULT_PORT, _normalized_relay_url())
	else:
		var host_ip := join_ip_input.text.strip_edges()
		if host_ip.is_empty():
			host_ip = MultiplayerSession.DEFAULT_HOST
		err = MultiplayerSession.join_session(host_ip, _parsed_port(join_port_input), _normalized_relay_url())
	if err != OK:
		status_label.text = "Could not join multiplayer (error %d)." % err
	_refresh_buttons()


func _on_start_pressed() -> void:
	MultiplayerSession.start_match()


func _on_leave_pressed() -> void:
	MultiplayerSession.leave_session()
	status_label.text = "Left multiplayer session."
	_refresh_buttons()


func _on_back_pressed() -> void:
	MultiplayerSession.reset_to_single_player()
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _on_status_changed(message: String) -> void:
	status_label.text = message
	_refresh_buttons()


func _on_room_changed(code: String) -> void:
	if code.is_empty():
		session_label.text = "Session: -"
	else:
		if MultiplayerSession.transport_mode == MultiplayerSession.TransportMode.WEB_RELAY:
			session_label.text = "Session: RELAY (%s)" % code
		else:
			var port := MultiplayerSession.active_port
			if port > 0:
				session_label.text = "Session: %s (%d)" % [code, port]
			else:
				session_label.text = "Session: %s" % code
	_refresh_buttons()


func _on_roster_updated(players: Dictionary) -> void:
	_update_roster_list(players)
	_refresh_buttons()


func _update_roster_list(players: Dictionary) -> void:
	players_list.clear()
	for peer_id in players.keys():
		var entry: Dictionary = players[peer_id]
		var username := String(entry.get("username", "Player"))
		var marker := ""
		if peer_id == MultiplayerSession.local_peer_id:
			marker = " (You)"
		players_list.add_item("%s [%d]%s" % [username, peer_id, marker])


func _on_match_started(_mode: String) -> void:
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_host_disconnected(reason: String) -> void:
	status_label.text = reason
	_refresh_buttons()


func _refresh_buttons() -> void:
	var in_session := MultiplayerSession.is_multiplayer
	host_button.disabled = in_session
	join_button.disabled = in_session
	start_button.disabled = (not in_session) or (not MultiplayerSession.is_host)
	leave_button.disabled = not in_session
	mode_option.disabled = in_session
	host_port_input.editable = not in_session
	join_ip_input.editable = not in_session
	join_port_input.editable = not in_session
	relay_url_input.editable = not in_session
	room_code_input.editable = not in_session


func _exit_tree() -> void:
	if MultiplayerSession.status_changed.is_connected(_on_status_changed):
		MultiplayerSession.status_changed.disconnect(_on_status_changed)
	if MultiplayerSession.roster_updated.is_connected(_on_roster_updated):
		MultiplayerSession.roster_updated.disconnect(_on_roster_updated)
	if MultiplayerSession.room_changed.is_connected(_on_room_changed):
		MultiplayerSession.room_changed.disconnect(_on_room_changed)
	if MultiplayerSession.match_started.is_connected(_on_match_started):
		MultiplayerSession.match_started.disconnect(_on_match_started)
	if MultiplayerSession.host_disconnected.is_connected(_on_host_disconnected):
		MultiplayerSession.host_disconnected.disconnect(_on_host_disconnected)
