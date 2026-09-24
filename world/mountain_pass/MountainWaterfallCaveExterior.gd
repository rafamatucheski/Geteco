extends "res://world/mountain_pass/MountainProjectedExterior.gd"

var entrance: BuildingEntrance
var inline_room: Node2D
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
	for shape in solid_body.get_children():
		if shape.name == "TunnelBack": shape.queue_free()

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
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	add_child(entrance)
	entrance.get_node("Facade").hide()
	inline_room = manager.get_interior(&"mountain_mystery_cave")
	inline_room.attach_inline_facade(self, entrance, manager)
	inline_room.global_position = entrance.global_position - inline_room.project_floor(Vector2(0, 5.5))

func set_inline_occupied(active: bool) -> void:
	sprite_3d.visible = not active
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED if active else SubViewport.UPDATE_ONCE
	if is_instance_valid(solid_body): solid_body.collision_layer = 0 if active else 1
