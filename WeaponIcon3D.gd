class_name WeaponIcon3D
extends Control

var weapon_id: String = "pistol"
var icon_textures: Dictionary = {}

func _ready() -> void:
	_load_textures()

func _load_textures() -> void:
	var paths := {
		"pistol": "res://city_demo/art/weapons/icon_pistol.png",
		"magnum": "res://city_demo/art/weapons/icon_magnum.png",
		"smg": "res://city_demo/art/weapons/icon_smg.png",
		"shotgun": "res://city_demo/art/weapons/icon_shotgun.png",
		"sawed_off": "res://city_demo/art/weapons/icon_sawed_off.png",
		"ak47": "res://city_demo/art/weapons/icon_ak47.png",
		"m4a1": "res://city_demo/art/weapons/icon_m4a1.png",
		"rpg": "res://city_demo/art/weapons/icon_rpg.png",
		"flamethrower": "res://city_demo/art/weapons/icon_flamethrower.png",
		"grenade": "res://city_demo/art/weapons/icon_grenade.png"
	}
	for id in paths:
		if ResourceLoader.exists(paths[id]):
			icon_textures[id] = load(paths[id])

func set_weapon(id: String) -> void:
	weapon_id = id
	if icon_textures.is_empty():
		_load_textures()
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var tex: Texture2D = icon_textures.get(weapon_id, null)
	
	if tex:
		draw_texture_rect(tex, rect, false)
	else:
		draw_rect(rect, Color(0.06, 0.08, 0.11, 0.85), true)
		draw_rect(rect, Color(0.35, 0.45, 0.55, 0.90), false, 1.5)
