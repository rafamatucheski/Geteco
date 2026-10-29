extends Node3D
## Fachada pintada do escritório da Serra Bruta com a porta de verdade.
##
## Como no Sede (PaintedBarFacade): a folha pintada do vão da frente é girada pela
## WeaponShopEntrance (`set_open_amount`), não pela proximidade, e a colisão é refeita em
## paredes com o vão da porta no lugar do casco de caixa cheia do kit.
const OFFICE := preload("res://world/mining/MiningOffice.gd")
const PAINTED := preload("res://world/places/bars/PaintedBarFacade.gd")
var leaves: Array[Node3D] = []
var open_amount := 0.0

func _ready() -> void:
	name = "MiningOffice"
	set_meta("place_id", OFFICE.ID)
	add_to_group("v2_walkin_facade")
	leaves = PAINTED.build(self, OFFICE.STYLE, OFFICE.DEPTH)
	set_process(false)
	set_physics_process(false)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount, 0, 1)
	for leaf in leaves: leaf.set_open_amount(open_amount)
