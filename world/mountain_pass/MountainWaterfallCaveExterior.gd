extends "res://world/mountain_pass/MountainProjectedExterior.gd"

var entrance: BuildingEntrance
var _visibility_clock := 0.0
var _rendering := true

func _ready() -> void:
	name = "WaterfallCaveExterior"
	z_as_relative = false
	z_index = 4
	build_view(preload("res://world/mountain_pass/MountainWaterfallCave3D.gd"), 13.5, 16.5, Vector3(0, 2.2, 0.5), Vector3(0, 18, 21), Vector2i(1024, 896))
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	depth_bounds = Rect2(-7.5,-5.0,15.0,10.0)
	install_projected_solids()

func _process(delta: float) -> void:
	super._process(delta)
	_visibility_clock -= delta
	if _visibility_clock > 0.0: return
	_visibility_clock = 0.2
	var camera := get_viewport().get_camera_2d()
	var player := get_tree().get_first_node_in_group("player")
	var active := camera != null and not (player != null and bool(player.get_meta("mountain_interior", false)))
	if active:
		var half := get_viewport_rect().size / camera.zoom * 0.5
		active = Rect2(camera.get_screen_center_position()-half, half*2.0).grow(300.0).has_point(global_position)
	if active == _rendering: return
	_rendering = active
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	model.set_process(active)

func install_entrance(manager: MountainInteriorManager) -> void:
	if is_instance_valid(entrance): return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "WaterfallCaveEntrance"
	entrance.position = project_floor(Vector2(0, 2.15))
	entrance.destination_id = &"mountain_mystery_cave"
	entrance.display_name = "CAVERNA DA QUEDA"
	entrance.custom_prompt_text = "E"
	add_child(entrance)
	entrance.get_node("Facade").hide()
	manager.register_exterior_entrance(entrance, &"mountain_mystery_cave", to_global(project_floor(Vector2(0, 3.15))))
