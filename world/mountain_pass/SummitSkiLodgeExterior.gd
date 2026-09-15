extends "res://world/mountain_pass/MountainProjectedExterior.gd"

var entrance: BuildingEntrance

func _ready() -> void:
	name = "SummitSkiLodge"
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/SummitSkiLodge3D.gd"), 19.0, 18.0, Vector3(0, 1.8, 0), Vector3(0, 25, 21), Vector2i(1024, 832))
	depth_bounds = Rect2(-8.2,-6.8,16.4,13.6)
	install_projected_solids()

func install_entrance(manager: MountainInteriorManager) -> void:
	if is_instance_valid(entrance): return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "SkiLodgeEntrance"
	entrance.position = project_floor(Vector2(0, 4.75))
	entrance.display_name = "CUME BRANCO"
	entrance.destination_id = &"ski_lodge"
	entrance.custom_prompt_text = "E"
	add_child(entrance)
	entrance.get_node("Facade").hide()
	manager.register_exterior_entrance(entrance, &"ski_lodge", to_global(project_floor(Vector2(0, 6.0))))
	var interior: Node2D = manager._interiors.get(&"ski_lodge")
	if interior == null: return
	var front_exit := interior.get_node_or_null("FrontExit") as BuildingEntrance
	var slope_exit := interior.get_node_or_null("SlopeExit") as BuildingEntrance
	if front_exit:
		front_exit.set_meta("mountain_return_position", to_global(project_floor(Vector2(0, 6.0))))
	if slope_exit:
		slope_exit.set_meta("mountain_return_position", to_global(project_floor(Vector2(0, -6.1))))
		slope_exit.set_meta("starts_skiing", true)

