class_name MountainOutfittersFacade
extends Node2D

var mountain: Node2D
var model: Node2D
var sprite_3d: Sprite2D
var entrance: BuildingEntrance
var inline_room: Node2D
var door_blocker: CollisionPolygon2D
var _door_amount := 0.0

func _ready() -> void:
	z_index = 5
	model = preload("res://world/mountain_pass/MountainOutfitters3D.gd").new()
	add_child(model)
	sprite_3d = model.sprite
	var walls := StaticBody2D.new()
	walls.name = "OutfittersStructure"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for entry in [
		["BackWall", Rect2(-3.0, -1.82, 6.0, .18)],
		["WestWall", Rect2(-3.0, -1.82, .18, 2.82)],
		["EastWall", Rect2(2.82, -1.82, .18, 2.82)],
		["WestFront", Rect2(-3.0, .86, 2.46, .18)],
		["EastFront", Rect2(.54, .86, 2.46, .18)],
		["DoorLeaf", Rect2(-.54, .86, 1.08, .18)],
	]:
		var shape := CollisionPolygon2D.new()
		shape.name = entry[0]
		var rect: Rect2 = entry[1]
		shape.polygon = PackedVector2Array([
			model.project_floor(rect.position),
			model.project_floor(Vector2(rect.end.x, rect.position.y)),
			model.project_floor(rect.end),
			model.project_floor(Vector2(rect.position.x, rect.end.y)),
		])
		walls.add_child(shape)
		if entry[0] == "DoorLeaf": door_blocker = shape
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate() as BuildingEntrance
	entrance.name = "OutfittersEntrance"
	entrance.position = model.project_floor(Vector2(0, 2.2))
	entrance.display_name = "ÚLTIMO ABRIGO"
	entrance.destination_id = &"mountain_outfitters"
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	entrance.add_to_group("clothing_shop")
	add_child(entrance)
	entrance.get_node("Facade").hide()
	if is_instance_valid(mountain) and is_instance_valid(mountain.interior_manager):
		inline_room = mountain.interior_manager.get_interior(&"mountain_outfitters")
		inline_room.attach_inline_facade(self, entrance, mountain.interior_manager)
	var heater := Node2D.new()
	heater.position = Vector2(0, 65)
	heater.add_to_group("heat_source")
	add_child(heater)
	var recovery := Marker2D.new()
	recovery.name = "MountainRecoverySpawn"
	recovery.position = Vector2(0, 105)
	recovery.add_to_group("hospital_spawn")
	add_child(recovery)

func _process(delta: float) -> void:
	if not is_instance_valid(entrance): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var near := false
	if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
		var local := entrance.to_local(actor.global_position)
		near = absf(local.x) < 38.0 and absf(local.y) < 74.0
		near = near or (is_instance_valid(inline_room) and inline_room.contains_point(actor.global_position))
	var amount := move_toward(_door_amount, 1.0 if entrance.enabled and near else 0.0, delta / .22)
	if is_equal_approx(amount, _door_amount): return
	_door_amount = amount
	model.set_open_amount(amount)
	if is_instance_valid(door_blocker): door_blocker.disabled = amount >= .55

func set_inline_occupied(active: bool) -> void:
	if not is_instance_valid(sprite_3d): return
	sprite_3d.visible = not active
	model.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED if active else SubViewport.UPDATE_ONCE
