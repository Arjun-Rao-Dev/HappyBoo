extends Control

const KenneyUI = preload("res://ui/kenney_ui.gd")

@onready var background: ColorRect = $Background
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var game_title: Label = $CenterContainer/Panel/Margin/VBox/GameTitle
@onready var subtitle: Label = $CenterContainer/Panel/Margin/VBox/Subtitle
@onready var coins_label: Label = $CenterContainer/Panel/Margin/VBox/CoinsLabel
@onready var continue_button: Button = $CenterContainer/Panel/Margin/VBox/ContinueButton
@onready var multiplayer_button: Button = $CenterContainer/Panel/Margin/VBox/MultiplayerButton
@onready var store_button: Button = $CenterContainer/Panel/Margin/VBox/StoreButton
@onready var options_button: Button = $CenterContainer/Panel/Margin/VBox/OptionsButton
@onready var new_run_button: Button = $CenterContainer/Panel/Margin/VBox/NewRunButton
@onready var quit_button: Button = $CenterContainer/Panel/Margin/VBox/QuitButton
@onready var status_label: Label = $CenterContainer/Panel/Margin/VBox/StatusLabel
@onready var modal_overlay: ColorRect = $ModalOverlay
@onready var options_panel = $OptionsPanel
@onready var store_panel = $StorePanel


func _ready() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SettingsManager.load_settings()
	_apply_kenney_style()
	continue_button.pressed.connect(_on_continue_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	store_button.pressed.connect(_on_store_pressed)
	options_button.pressed.connect(_on_options_pressed)
	new_run_button.pressed.connect(_on_new_run_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	options_panel.closed.connect(_on_options_closed)
	store_panel.closed.connect(_on_store_closed)
	_refresh_continue_state()
	if continue_button.disabled:
		new_run_button.grab_focus()
	else:
		continue_button.grab_focus()


func _apply_kenney_style() -> void:
	KenneyUI.apply_background(background)
	KenneyUI.apply_panel(panel, "Red")
	KenneyUI.apply_title_label(game_title, 44)
	KenneyUI.apply_body_label(subtitle, 18)
	KenneyUI.apply_heading(coins_label, 18)
	KenneyUI.apply_primary_button(new_run_button)
	KenneyUI.apply_info_button(continue_button)
	KenneyUI.apply_info_button(multiplayer_button)
	KenneyUI.apply_yellow_button(store_button)
	KenneyUI.apply_secondary_button(options_button)
	KenneyUI.apply_danger_button(quit_button)
	KenneyUI.apply_body_label(status_label, 16)


func _refresh_continue_state() -> void:
	coins_label.text = "Coins: %d" % SettingsManager.get_coin_balance()
	var can_continue := SaveManager.has_save()
	continue_button.disabled = not can_continue
	if can_continue:
		status_label.text = ""
	else:
		status_label.text = "No save found. Start a new run."


func _on_new_run_pressed() -> void:
	MultiplayerClient.disconnect_from_server()
	SaveManager.clear_pending_continue_run()
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_continue_pressed() -> void:
	var result := SaveManager.load_run()
	if bool(result.get("ok", false)):
		SaveManager.queue_continue_run(result.get("run_state", {}))
		MultiplayerClient.disconnect_from_server()
		get_tree().change_scene_to_file("res://survivors_game.tscn")
		return

	status_label.text = "Continue failed (%s). Starting a new run." % String(result.get("status", "error"))
	SaveManager.clear_pending_continue_run()
	MultiplayerClient.disconnect_from_server()
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_multiplayer_pressed() -> void:
	SaveManager.clear_pending_continue_run()
	MultiplayerClient.request_online_run()
	get_tree().change_scene_to_file("res://survivors_game.tscn")


func _on_options_pressed() -> void:
	store_panel.hide_panel()
	modal_overlay.visible = true
	options_panel.show_panel()


func _on_store_pressed() -> void:
	options_panel.hide_panel()
	modal_overlay.visible = true
	store_panel.show_panel()


func _on_options_closed() -> void:
	options_panel.hide_panel()
	modal_overlay.visible = false
	_refresh_continue_state()


func _on_store_closed() -> void:
	store_panel.hide_panel()
	modal_overlay.visible = false
	_refresh_continue_state()


func _on_quit_pressed() -> void:
	get_tree().quit()
