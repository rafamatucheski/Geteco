class_name ResortShopFacade
extends "res://world/mountain_pass/MountainProjectedExterior.gd"
var entrance: BuildingEntrance
var shop_body: StaticBody2D
var inline_room: Node2D
var door_blocker: CollisionPolygon2D
var _door_amount := 0.0

func _ready() -> void:
	z_index = 5
	build_view(preload("res://world/mountain_pass/ResortShop3D.gd"),10.5,18.0,Vector3(0,1.9,0),Vector3(0,13,11),Vector2i(640,560))
	depth_bounds = Rect2(-4.5,-3.5,9.0,7.3)
	install_projected_solids()
	shop_body = solid_body
	var leaves := add_solid(Rect2(-.56, 1.72, 1.12, .2), "BoutiqueDoorLeaves")
	door_blocker = leaves.get_child(0) as CollisionPolygon2D

func install_entrance(manager: MountainInteriorManager) -> void:
	if is_instance_valid(entrance):
		return
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "BoutiqueEntrance"
	entrance.position = project_floor(Vector2(0,2.55))
	entrance.display_name = "BOUTIQUE ALPINA"
	entrance.destination_id = &"mountain_boutique"
	entrance.entrance_kind = BuildingEntrance.EntranceKind.SHOP
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	add_child(entrance)
	entrance.get_node("Facade").hide()

	if manager != null:
		inline_room = manager.get_interior(&"mountain_boutique")
		inline_room.attach_inline_facade(self, entrance, manager)

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(entrance): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var near_threshold := false
	var actor_inside := false
	if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
		var local := entrance.to_local(actor.global_position)
		near_threshold = absf(local.x) < 42.0 and absf(local.y) < 70.0
		actor_inside = is_instance_valid(inline_room) and inline_room.contains_point(actor.global_position)
	var target := 1.0 if entrance.enabled and (entrance.get_nearest_actor() != null or near_threshold or actor_inside) else 0.0
	var amount := move_toward(_door_amount, target, delta / .22)
	if is_equal_approx(amount, _door_amount): return
	_door_amount = amount
	model.set_open_amount(amount)
	if is_instance_valid(door_blocker): door_blocker.disabled = amount >= .55
	if sprite_3d.visible: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
