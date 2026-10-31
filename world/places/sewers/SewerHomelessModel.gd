extends "res://assets/CivilianModel.gd"
## Morador de rua dos esgotos de Harbor: o pedestre articulado comum, com roupa gasta.
## `OriginalResidents.create_model` define `character_name` e as cores de `appearance`.
var character_name := ""
## Os dados autorados usam is_female. Passa isso ao guarda-roupa real do corpo antes de
## o CivilianModel montar o rig; definir uma propriedade desconhecida nunca fez isso.
var is_female := false

func _ready() -> void:
	appearance_locked = true
	wardrobe_overrides["female"] = is_female
	# Corpo de pedestre comum, sujo e gasto: o catálogo de função nunca dá terno a quem mora na rua.
	preload("res://assets/civilians/RoleBodyCatalog.gd").apply(self, "homeless", hash(character_name), is_female, true)
	super._ready()
