extends "res://assets/CivilianModel.gd"
## Os funcionários da loja usam direto o pedestre articulado atual, sem um
## segundo corpo legado escondido nem os antigos multiplicadores de escala de morador.
var character_name := "Atendente"
var is_female := false
## Lojas da serra (OriginalResidents): roupa de neve, como os moradores lá fora. O mercado Boa Praça do
## Harbor usa o mesmo modelo sem isto.
var winter := false

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 8200 + posmod(hash(character_name), 997)
	wardrobe_overrides = {"female": is_female, "build": 0, "height": 1.0,
		"top": 3 if winter else 2, "bottom": 0, "shoe": 1, "hat": 2 if winter else 0,
		"backpack": false, "bag": 0, "beard": 0,
		"inner": Color("e3d9c6"), "accent": Color("a18b61")}
	# Corpo do Meshy do mesmo sexo do atendente (pedestre comum, ou conjunto de neve na serra); sem catálogo,
	# segue o corpo do kit.
	preload("res://assets/civilians/RoleBodyCatalog.gd").apply(self, "mountain_villager" if winter else "pedestrian", appearance_variant, is_female, true)
	super._ready()
