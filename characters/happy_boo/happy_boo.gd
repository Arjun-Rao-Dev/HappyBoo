extends Node2D

const CLASSIC_MODULATE := Color(1.0, 0.572549, 0.176471, 1.0)
const SKIN_TEXTURES := {
	"classic": {
		"body": "res://characters/happy_boo/square_body.png",
		"face": "res://characters/happy_boo/square_face.png",
		"foot": "res://characters/happy_boo/square_foot.png",
		"lower_leg": "res://characters/happy_boo/square_lower_leg.png",
		"upper_leg": "res://characters/happy_boo/square_upper_leg.png"
	},
	"berry": {
		"body": "res://characters/happy_boo/skins/berry/square_body.png",
		"face": "res://characters/happy_boo/skins/berry/square_face.png",
		"foot": "res://characters/happy_boo/skins/berry/square_foot.png",
		"lower_leg": "res://characters/happy_boo/skins/berry/square_lower_leg.png",
		"upper_leg": "res://characters/happy_boo/skins/berry/square_upper_leg.png"
	},
	"mint": {
		"body": "res://characters/happy_boo/skins/mint/square_body.png",
		"face": "res://characters/happy_boo/skins/mint/square_face.png",
		"foot": "res://characters/happy_boo/skins/mint/square_foot.png",
		"lower_leg": "res://characters/happy_boo/skins/mint/square_lower_leg.png",
		"upper_leg": "res://characters/happy_boo/skins/mint/square_upper_leg.png"
	},
	"gold": {
		"body": "res://characters/happy_boo/skins/gold/square_body.png",
		"face": "res://characters/happy_boo/skins/gold/square_face.png",
		"foot": "res://characters/happy_boo/skins/gold/square_foot.png",
		"lower_leg": "res://characters/happy_boo/skins/gold/square_lower_leg.png",
		"upper_leg": "res://characters/happy_boo/skins/gold/square_upper_leg.png"
	},
	"sappy": {
		"body": "res://characters/happy_boo/skins/sappy/square_body.png",
		"face": "res://characters/happy_boo/skins/sappy/square_face.png",
		"foot": "res://characters/happy_boo/skins/sappy/square_foot.png",
		"lower_leg": "res://characters/happy_boo/skins/sappy/square_lower_leg.png",
		"upper_leg": "res://characters/happy_boo/skins/sappy/square_upper_leg.png"
	}
}

@onready var colorizer: Node2D = $Colorizer
@onready var body: Sprite2D = $Colorizer/SquareBody
@onready var face: Sprite2D = $Colorizer/SquareBody/SquareFace
@onready var upper_leg_l: Sprite2D = $Colorizer/SquareUpperLegL
@onready var lower_leg_l: Sprite2D = $Colorizer/SquareUpperLegL/SquareLowerLegL
@onready var foot_l: Sprite2D = $Colorizer/SquareUpperLegL/SquareLowerLegL/SquareFootL
@onready var upper_leg_r: Sprite2D = $Colorizer/SquareUpperLegR
@onready var lower_leg_r: Sprite2D = $Colorizer/SquareUpperLegR/SquareLowerLegR
@onready var foot_r: Sprite2D = $Colorizer/SquareUpperLegR/SquareLowerLegR/SquareFootR


func _ready() -> void:
	apply_equipped_skin()


func apply_equipped_skin() -> void:
	var skin_id := SettingsManager.DEFAULT_SKIN_ID
	if has_node("/root/SettingsManager"):
		skin_id = SettingsManager.get_equipped_skin()
	_apply_skin(skin_id)


func play_idle_animation():
	%AnimationPlayer.play("idle")


func play_walk_animation():
	%AnimationPlayer.play("walk")


func _apply_skin(skin_id: String) -> void:
	var skin_textures: Dictionary = SKIN_TEXTURES.get(skin_id, SKIN_TEXTURES[SettingsManager.DEFAULT_SKIN_ID])
	if not _all_skin_textures_exist(skin_textures):
		skin_textures = SKIN_TEXTURES[SettingsManager.DEFAULT_SKIN_ID]
		skin_id = SettingsManager.DEFAULT_SKIN_ID

	body.texture = _load_texture(skin_textures["body"])
	face.texture = _load_texture(skin_textures["face"])
	upper_leg_l.texture = _load_texture(skin_textures["upper_leg"])
	upper_leg_r.texture = _load_texture(skin_textures["upper_leg"])
	lower_leg_l.texture = _load_texture(skin_textures["lower_leg"])
	lower_leg_r.texture = _load_texture(skin_textures["lower_leg"])
	foot_l.texture = _load_texture(skin_textures["foot"])
	foot_r.texture = _load_texture(skin_textures["foot"])
	colorizer.modulate = CLASSIC_MODULATE if skin_id == SettingsManager.DEFAULT_SKIN_ID else Color.WHITE


func _all_skin_textures_exist(skin_textures: Dictionary) -> bool:
	for path in skin_textures.values():
		if not ResourceLoader.exists(path):
			return false
	return true


func _load_texture(path: String) -> Texture2D:
	return load(path) as Texture2D
