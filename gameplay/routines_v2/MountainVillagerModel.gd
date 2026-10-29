extends "res://assets/CivilianModel.gd"
## Corpo dos moradores de fora da serra: pedestre articulado com corpo Meshy de
## inverno (`RoleBodyCatalog` "mountain_villager"), no lugar do `WinterResidentModel`
## da V1. Sem catálogo ou arquivo, cai no corpo procedural do kit.
var is_female := false

func _ready() -> void:
	appearance_locked = true
	# Sem corpo Meshy, o kit veste o mesmo frio do pedestre da serra (casaco, calça, bota e gorro).
	wardrobe_overrides = {"female": is_female, "top": 3, "bottom": 0, "shoe": 1, "hat": 2,
		"backpack": false, "bag": 0, "height": 1.0}
	preload("res://assets/civilians/RoleBodyCatalog.gd").apply(self, "mountain_villager", appearance_variant, is_female, true)
	super._ready()
