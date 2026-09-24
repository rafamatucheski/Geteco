class_name MountainBunkerFacade
extends Node2D

var entrance: BuildingEntrance
var inline_room: Node2D
var door_leaf: Polygon2D
var door_collision: CollisionShape2D
var _door_amount := 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(entrance) or not is_instance_valid(inline_room): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var near := false
	if is_instance_valid(actor) and actor.get("is_dead") != true and actor.visible:
		var local := entrance.to_local(actor.global_position)
		near = absf(local.x) < 38 and absf(local.y) < 76
		near = near or inline_room.contains_point(actor.global_position)
	var amount := move_toward(_door_amount, 1.0 if near else 0.0, delta / .22)
	if is_equal_approx(amount, _door_amount): return
	_door_amount = amount
	if is_instance_valid(door_leaf): door_leaf.position.x = -47.0 * amount
	if is_instance_valid(door_collision): door_collision.disabled = amount >= .55

func set_inline_occupied(active: bool) -> void:
	for child in get_children():
		if child is Polygon2D: child.visible = not active
	var shell := get_node_or_null("StationZeroFacadeCollision") as StaticBody2D
	if shell: shell.collision_layer = 0 if active else 1
