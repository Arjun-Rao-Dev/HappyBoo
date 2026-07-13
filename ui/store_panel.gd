extends PanelContainer

const KenneyUI = preload("res://ui/kenney_ui.gd")
const PREVIEW_SIZE := Vector2(70.0, 70.0)
const STORE_URL := "https://store.arjunrao.dev"
const SKIN_CATALOG: Array[Dictionary] = [
	{"id": "classic", "name": "Classic Boo", "price": 0, "preview": "res://characters/happy_boo/square_ref.png"},
	{"id": "berry", "name": "Berry Boo", "price": 75, "preview": "res://characters/happy_boo/skins/berry/preview.png"},
	{"id": "mint", "name": "Mint Boo", "price": 125, "preview": "res://characters/happy_boo/skins/mint/preview.png"},
	{"id": "gold", "name": "Gold Boo", "price": 250, "preview": "res://characters/happy_boo/skins/gold/preview.png"},
	{"id": "sappy", "name": "Sappy Boo", "price": 350, "preview": "res://characters/happy_boo/skins/sappy/preview.png"}
]

signal closed

@onready var title_label: Label = $Margin/VBox/HeaderRow/Title
@onready var coins_label: Label = $Margin/VBox/HeaderRow/CoinsLabel
@onready var catalog_container: VBoxContainer = $Margin/VBox/Scroll/CatalogContainer
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var store_message_label: Label = $Margin/VBox/BottomRow/StoreMessageLabel
@onready var store_button: Button = $Margin/VBox/BottomRow/StoreButton
@onready var close_button: Button = $Margin/VBox/BottomRow/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	store_button.pressed.connect(_on_store_pressed)
	close_button.pressed.connect(_on_close_pressed)
	_apply_kenney_style()
	refresh()


func show_panel() -> void:
	refresh()
	status_label.text = ""
	visible = true
	close_button.grab_focus()


func hide_panel() -> void:
	visible = false
	status_label.text = ""


func refresh() -> void:
	coins_label.text = "Coins: %d" % SettingsManager.get_coin_balance()
	for child in catalog_container.get_children():
		child.queue_free()

	_add_section_heading("Skins")
	for skin in SKIN_CATALOG:
		_add_skin_row(skin)
	_add_section_heading("Weapons")
	for weapon in SettingsManager.get_weapon_catalog():
		_add_weapon_row(weapon)


func _add_section_heading(text: String) -> void:
	var heading := Label.new()
	heading.text = text
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_container.add_child(heading)
	KenneyUI.apply_title_label(heading, 22)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _add_skin_row(skin: Dictionary) -> void:
	var skin_id := String(skin.get("id", "")).strip_edges()
	var skin_name := String(skin.get("name", "Skin"))
	var price := maxi(int(skin.get("price", 0)), 0)
	var owned := SettingsManager.is_skin_owned(skin_id)
	var equipped := SettingsManager.get_equipped_skin() == skin_id

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var preview := TextureRect.new()
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = _load_preview_texture(String(skin.get("preview", "")))
	row.add_child(preview)

	var name_label := Label.new()
	name_label.text = skin_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var price_label := Label.new()
	price_label.custom_minimum_size = Vector2(120.0, 0.0)
	price_label.text = "Owned" if owned else "%d coins" % price
	row.add_child(price_label)

	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(150.0, 42.0)
	if equipped:
		action_button.text = "Equipped"
		action_button.disabled = true
	elif owned:
		action_button.text = "Equip"
		action_button.pressed.connect(_on_equip_pressed.bind(skin_id))
	else:
		action_button.text = "Buy"
		action_button.disabled = SettingsManager.get_coin_balance() < price
		action_button.pressed.connect(_on_buy_pressed.bind(skin_id, price))
	row.add_child(action_button)

	catalog_container.add_child(row)
	KenneyUI.apply_heading(name_label, 16)
	KenneyUI.apply_body_label(price_label, 15)
	KenneyUI.apply_secondary_button(action_button)


func _add_weapon_row(weapon: Dictionary) -> void:
	var weapon_id := String(weapon.get("id", "")).strip_edges()
	var weapon_name := String(weapon.get("name", "Weapon"))
	var price := maxi(int(weapon.get("price", 0)), 0)
	var owned := SettingsManager.is_weapon_owned(weapon_id)
	var equipped := SettingsManager.get_equipped_weapon() == weapon_id

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var preview := TextureRect.new()
	preview.custom_minimum_size = PREVIEW_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = _load_preview_texture(String(weapon.get("preview", "")))
	row.add_child(preview)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_box)

	var name_label := Label.new()
	name_label.text = weapon_name
	text_box.add_child(name_label)

	var description_label := Label.new()
	description_label.text = String(weapon.get("description", ""))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(description_label)

	var price_label := Label.new()
	price_label.custom_minimum_size = Vector2(120.0, 0.0)
	price_label.text = "Owned" if owned else "%d coins" % price
	row.add_child(price_label)

	var action_button := Button.new()
	action_button.custom_minimum_size = Vector2(150.0, 42.0)
	if equipped:
		action_button.text = "Equipped"
		action_button.disabled = true
	elif owned:
		action_button.text = "Equip"
		action_button.pressed.connect(_on_weapon_equip_pressed.bind(weapon_id))
	else:
		action_button.text = "Buy"
		action_button.disabled = SettingsManager.get_coin_balance() < price
		action_button.pressed.connect(_on_weapon_buy_pressed.bind(weapon_id, price))
	row.add_child(action_button)

	catalog_container.add_child(row)
	KenneyUI.apply_heading(name_label, 16)
	KenneyUI.apply_body_label(description_label, 14)
	KenneyUI.apply_body_label(price_label, 15)
	KenneyUI.apply_secondary_button(action_button)


func _load_preview_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return load("res://characters/happy_boo/square_ref.png") as Texture2D
	return load(path) as Texture2D


func _on_buy_pressed(skin_id: String, price: int) -> void:
	var result := SettingsManager.buy_skin(skin_id, price)
	if bool(result.get("ok", false)):
		status_label.text = "Skin bought and equipped."
	else:
		status_label.text = "Not enough coins."
	refresh()


func _on_equip_pressed(skin_id: String) -> void:
	if SettingsManager.equip_skin(skin_id):
		status_label.text = "Skin equipped."
	else:
		status_label.text = "Buy this skin first."
	refresh()


func _on_weapon_buy_pressed(weapon_id: String, price: int) -> void:
	var result := SettingsManager.buy_weapon(weapon_id, price)
	if bool(result.get("ok", false)):
		status_label.text = "Weapon bought and equipped."
	else:
		status_label.text = "Not enough coins."
	refresh()


func _on_weapon_equip_pressed(weapon_id: String) -> void:
	if SettingsManager.equip_weapon(weapon_id):
		status_label.text = "Weapon equipped."
	else:
		status_label.text = "Buy this weapon first."
	refresh()


func _on_store_pressed() -> void:
	var error := OS.shell_open(STORE_URL)
	if error != OK:
		status_label.text = "Could not open store."


func _on_close_pressed() -> void:
	hide_panel()
	emit_signal("closed")


func _apply_kenney_style() -> void:
	KenneyUI.apply_panel(self, "Yellow")
	KenneyUI.apply_title_label(title_label, 30)
	KenneyUI.apply_heading(coins_label, 18)
	KenneyUI.apply_body_label(status_label, 15)
	KenneyUI.apply_body_label(store_message_label, 15)
	KenneyUI.apply_yellow_button(store_button)
	KenneyUI.apply_secondary_button(close_button)
