class_name WeaponIcon3D
extends Control

var weapon_id: String = "fists"
var icon_textures: Dictionary = {}
var _silhouette_material: ShaderMaterial
@export var frameless := false

const FRAMELESS_SHADER = preload("res://ui/WeaponSilhouette.gdshader")

func _ready() -> void:
	_load_textures()
	if frameless:
		var silhouette := ShaderMaterial.new()
		silhouette.shader = FRAMELESS_SHADER
		_silhouette_material = silhouette
		material = null if weapon_id == "fists" else _silhouette_material
	resized.connect(queue_redraw)

func _load_textures() -> void:
	var paths := {
		"fists": "res://assets/art/weapons/icon_fists.svg",
		"knife": "res://assets/art/weapons/icon_knife.svg",
		"axe": "res://assets/art/weapons/icon_axe.svg",
		"knuckles": "res://assets/art/weapons/icon_knuckles.svg",
		"bat": "res://assets/art/weapons/icon_bat.svg",
		"pistol": "res://assets/art/weapons/icon_pistol.png",
		"magnum": "res://assets/art/weapons/icon_magnum.png",
		"smg": "res://assets/art/weapons/icon_smg.png",
		"shotgun": "res://assets/art/weapons/icon_shotgun.png",
		"hunting_rifle": "res://assets/art/weapons/icon_hunting_rifle.svg",
		"sawed_off": "res://assets/art/weapons/icon_sawed_off.png",
		"ak47": "res://assets/art/weapons/icon_ak47.png",
		"m4a1": "res://assets/art/weapons/icon_m4a1.png",
		"rpg": "res://assets/art/weapons/icon_rpg.png",
		"flamethrower": "res://assets/art/weapons/icon_flamethrower.png",
		"grenade": "res://assets/art/weapons/icon_grenade.png"
	}
	for id in paths:
		if ResourceLoader.exists(paths[id]):
			icon_textures[id] = load(paths[id])

func set_weapon(id: String) -> void:
	weapon_id = id
	if frameless:
		material = null if id == "fists" else _silhouette_material
	if icon_textures.is_empty():
		_load_textures()
	queue_redraw()

func _draw() -> void:
	var tex: Texture2D = icon_textures.get(weapon_id, null)
	if tex:
		var texture_size := tex.get_size()
		var fit := minf(size.x / texture_size.x, size.y / texture_size.y)
		var fitted_size := texture_size * fit
		var rect := Rect2((size - fitted_size) * 0.5, fitted_size)
		draw_texture_rect(tex, rect, false)
