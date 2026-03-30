extends Control

@onready var mode_option: OptionButton = $CenterContainer/Panel/Margin/VBox/ModeRow/ModeOption
@onready var signaling_input: LineEdit = $CenterContainer/Panel/Margin/VBox/SignalingRow/SignalingInput
@onready var room_code_input: LineEdit = $CenterContainer/Panel/Margin/VBox/RoomRow/RoomCodeInput
@onready var room_code_label: Label = $CenterContainer/Panel/Margin/VBox/RoomCodeLabel
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
	signaling_input.text = MultiplayerSession.DEFAULT_SIGNALING_URL
	room_code_input.text = ""
	room_code_label.text = "Room Code: -"
	status_label.text = "Create or join a room to play."

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


func _selected_mode() -> String:
	if mode_option.selected == 1:
		return "pvp"
	return "team"


func _ensure_connected() -> bool:
	var err := MultiplayerSession.connect_to_signaling(signaling_input.text)
	if err != OK:
		status_label.text = "Could not connect (error %d)." % err
		return false
	return true


func _on_host_pressed() -> void:
	if not _ensure_connected():
		return
	MultiplayerSession.create_room(_selected_mode())
	status_label.text = "Creating room..."
	_refresh_buttons()


func _on_join_pressed() -> void:
	if not _ensure_connected():
		return
	var room_code := room_code_input.text.strip_edges().to_upper()
	if room_code.is_empty():
		status_label.text = "Enter a room code first."
		return
	MultiplayerSession.join_room(room_code, _selected_mode())
	status_label.text = "Joining room..."
	_refresh_buttons()


func _on_start_pressed() -> void:
	MultiplayerSession.start_match()


func _on_leave_pressed() -> void:
	MultiplayerSession.leave_room()
	status_label.text = "Left room."
	_refresh_buttons()


func _on_back_pressed() -> void:
	MultiplayerSession.reset_to_single_player()
	get_tree().change_scene_to_file("res://ui/title_menu.tscn")


func _on_status_changed(message: String) -> void:
	status_label.text = message
	_refresh_buttons()


func _on_room_changed(code: String) -> void:
	if code.is_empty():
		room_code_label.text = "Room Code: -"
	else:
		room_code_label.text = "Room Code: %s" % code
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
	var in_room := not MultiplayerSession.room_code.is_empty()
	host_button.disabled = in_room
	join_button.disabled = in_room
	start_button.disabled = (not in_room) or (not MultiplayerSession.is_host)
	leave_button.disabled = not in_room
	mode_option.disabled = in_room
	signaling_input.editable = not in_room
	room_code_input.editable = not in_room


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
