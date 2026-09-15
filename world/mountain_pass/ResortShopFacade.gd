class_name ResortShopFacade
extends "res://world/mountain_pass/MountainProjectedExterior.gd"
var entrance: BuildingEntrance
var shop_body: StaticBody2D

func _ready() -> void:
	z_index = 5
	build_view(preload("res://world/mountain_pass/ResortShop3D.gd"),10.5,18.0,Vector3(0,1.9,0),Vector3(0,13,11),Vector2i(640,560))
	depth_bounds = Rect2(-4.5,-3.5,9.0,7.3)
	install_projected_solids()
	shop_body = solid_body

func install_entrance(manager: MountainInteriorManager) -> void:
	if is_instance_valid(entrance):
		return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "BoutiqueEntrance"
	entrance.position = project_floor(Vector2(0,2.55))
	entrance.display_name = "BOUTIQUE ALPINA"
	entrance.destination_id = &"mountain_outfitters"
	entrance.custom_prompt_text = "E"
	entrance.entrance_kind = BuildingEntrance.EntranceKind.SHOP
	add_child(entrance)
	entrance.get_node("Facade").hide()

	if manager != null:
		manager.register_exterior_entrance(entrance, &"mountain_outfitters", to_global(project_floor(Vector2(0,3.4))))
