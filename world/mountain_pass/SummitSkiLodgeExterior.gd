extends "res://world/mountain_pass/MountainProjectedExterior.gd"

var entrance: BuildingEntrance
var slope_entrance: BuildingEntrance
var inline_room: Node2D
var front_leaf: CollisionPolygon2D
var rear_leaf: CollisionPolygon2D
var _front_open := 0.0
var _rear_open := 0.0
var _ski_notice_clock := 0.0

func _ready() -> void:
	name = "SummitSkiLodge"
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/SummitSkiLodge3D.gd"), 19.0, 18.0, Vector3(0, 1.8, 0), Vector3(0, 25, 21), Vector2i(1024, 832))
	depth_bounds = Rect2(-8.2,-6.8,16.4,13.6)
	install_projected_solids()
	for entry in [
		["WestWall", Rect2(-6.80, -4.10, .20, 8.20)],
		["EastWall", Rect2(6.60, -4.10, .20, 8.20)],
		["FrontWest", Rect2(-6.80, 3.94, 6.05, .20)],
		["FrontEast", Rect2(.75, 3.94, 6.05, .20)],
		["RearWest", Rect2(-6.80, -4.14, 6.05, .20)],
		["RearEast", Rect2(.75, -4.14, 6.05, .20)],
		["FrontLeaf", Rect2(-.75, 3.94, 1.50, .20)],
		["RearLeaf", Rect2(-.75, -4.14, 1.50, .20)],
	]:
		var shape := CollisionPolygon2D.new()
		shape.name = entry[0]
		var rect: Rect2 = entry[1]
		shape.polygon = PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
		solid_body.add_child(shape)
		if entry[0] == "FrontLeaf": front_leaf = shape
		if entry[0] == "RearLeaf": rear_leaf = shape

func install_entrance(manager: MountainInteriorManager) -> void:
	if is_instance_valid(entrance): return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "SkiLodgeEntrance"
	entrance.position = project_floor(Vector2(0, 4.75))
	entrance.display_name = "CUME BRANCO"
	entrance.destination_id = &"ski_lodge"
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	add_child(entrance)
	entrance.get_node("Facade").hide()
	slope_entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	slope_entrance.name = "SkiLodgeSlopeEntrance"
	slope_entrance.position = project_floor(Vector2(0, -4.75))
	slope_entrance.destination_id = &"ski_lodge"
	slope_entrance.handle_input_locally = false
	slope_entrance.show_entrance_marker = false
	slope_entrance.show_interaction_prompt = false
	add_child(slope_entrance)
	slope_entrance.get_node("Facade").hide()
	inline_room = manager.get_interior(&"ski_lodge")
	inline_room.attach_inline_facade(self, entrance, manager)

func _process(delta: float) -> void:
	super._process(delta)
	_ski_notice_clock = maxf(0.0, _ski_notice_clock - delta)
	if not is_instance_valid(entrance) or not is_instance_valid(inline_room): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var front_near := false
	var rear_near := false
	if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
		front_near = absf(entrance.to_local(actor.global_position).x) < 36 and absf(entrance.to_local(actor.global_position).y) < 65
		rear_near = absf(slope_entrance.to_local(actor.global_position).x) < 36 and absf(slope_entrance.to_local(actor.global_position).y) < 65
		if inline_room.contains_point(actor.global_position):
			front_near = front_near or actor.global_position.distance_to(entrance.global_position) < 95
			rear_near = rear_near or actor.global_position.distance_to(slope_entrance.global_position) < 95
			if rear_near and actor.get("ski_equipment_ready") != true:
				rear_near = false
				if _ski_notice_clock <= 0.0 and actor.global_position.distance_to(slope_entrance.global_position) < 49 and actor.has_method("_show_weapon_notice"):
					actor.call("_show_weapon_notice", "RETIRE OS SKIS NO RACK ANTES DE IR ÀS PISTAS")
					_ski_notice_clock = 3.0
	var front := move_toward(_front_open, 1.0 if front_near else 0.0, delta / .10)
	var rear := move_toward(_rear_open, 1.0 if rear_near else 0.0, delta / .10)
	if is_equal_approx(front, _front_open) and is_equal_approx(rear, _rear_open): return
	_front_open = front
	_rear_open = rear
	model.set_lodge_open_amount(front, rear)
	front_leaf.disabled = front >= .30
	rear_leaf.disabled = rear >= .30
	if sprite_3d.visible: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_inline_occupied(active: bool) -> void:
	sprite_3d.visible = not active
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED if active else SubViewport.UPDATE_ONCE
	if is_instance_valid(solid_body): solid_body.collision_layer = 0 if active else 1

