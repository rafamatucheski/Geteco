extends "res://assets/CivilianModel.gd"
## Shop staff use the current articulated pedestrian directly, without a
## second hidden legacy body or the old resident scale multipliers.
var character_name := "Atendente"
var is_female := false

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 8200 + posmod(hash(character_name), 997)
	wardrobe_overrides = {"female": is_female, "build": 0, "height": 1.0,
		"top": 2, "bottom": 0, "shoe": 1, "hat": 0,
		"backpack": false, "bag": 0, "beard": 0,
		"inner": Color("e3d9c6"), "accent": Color("a18b61")}
	# Corpo do Meshy de pedestre comum (mesmo sexo do atendente); sem catálogo, segue o corpo do kit.
	preload("res://assets/civilians/RoleBodyCatalog.gd").apply(self, "pedestrian", appearance_variant, is_female, true)
	super._ready()
