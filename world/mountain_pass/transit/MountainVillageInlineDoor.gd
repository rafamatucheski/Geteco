class_name MountainVillageInlineDoor
extends Node2D

var mountain: Node2D
var village: Node2D
var entrance: BuildingEntrance
var interior_id: StringName
var inline_room: Node2D
var _door_amount := 0.0
var _occupied := false
var _passable := false

func _ready() -> void:
	if not is_instance_valid(mountain) or not is_instance_valid(entrance): return
	inline_room = mountain.interior_manager.get_interior(interior_id)
	if is_instance_valid(inline_room):
		inline_room.attach_inline_facade(self, entrance, mountain.interior_manager)

func _process(delta: float) -> void:
	if not is_instance_valid(entrance) or not is_instance_valid(village): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var near := false
	if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
		var local := entrance.to_local(actor.global_position)
		var reach := Vector2(60, 82) if interior_id == &"mountain_village_outfitters" else Vector2(34, 68)
		near = absf(local.x) < reach.x and absf(local.y) < reach.y
		near = near or (is_instance_valid(inline_room) and inline_room.contains_point(actor.global_position))
	var amount := move_toward(_door_amount, 1.0 if entrance.enabled and near else 0.0, delta / .22)
	if not is_equal_approx(amount, _door_amount):
		_door_amount = amount
		village.set_building_door_amount(interior_id, amount)
	var passable := amount >= .55 or _occupied
	if passable != _passable:
		_passable = passable
		village.set_building_passable(interior_id, passable)

func set_inline_occupied(active: bool) -> void:
	if _occupied == active: return
	_occupied = active
	if is_instance_valid(village): village.set_building_open(interior_id, active)
