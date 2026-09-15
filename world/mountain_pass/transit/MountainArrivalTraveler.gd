extends "res://world/mountain_pass/WinterResident.gd"

var winter_outfit := true
var itinerary := PackedVector2Array()
var route_index := 0
var routine := "onboard"
var walk_speed := 35.0
var pause_left := 0.0
var purchased_winter_clothes := false
var cabin_index := 0
var trip_id := 0
signal reached_destination(traveler: Node)

func _ready() -> void:
	super._ready()
	# The path from a bench may go around its back and a nearby chalet corner.
	_navigation.search_budget=128

func _create_model() -> Node3D:
	var rig := preload("res://world/mountain_pass/transit/MountainArrivalTravelerModel.gd").new()
	rig.winter_outfit = winter_outfit
	return rig

func walk_route(points: PackedVector2Array, next_routine: String) -> void:
	itinerary = points
	route_index = 0
	routine = next_routine
	show()
	collision_layer = 4

func go_inside(next_routine: String) -> void:
	routine = next_routine
	velocity = Vector2.ZERO
	hide()
	collision_layer = 0

func buy_winter_clothes() -> void:
	winter_outfit = true
	purchased_winter_clothes = true
	model.put_on_winter_clothes()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _physics_process(delta: float) -> void:
	if is_dead:
		fall_presentation.update(delta)
		return
	if not visible: return
	if _process_bench_rest(delta):return
	if _process_danger(delta): return
	if route_index >= itinerary.size(): return
	var target := itinerary[route_index]
	# Align physically with each corridor before turning: the chalet eaves leave
	# little room for a five-pixel lateral shortcut at the preceding corner.
	if global_position.distance_to(target) <= 0.75:
		route_index += 1
		if route_index >= itinerary.size():
			velocity = Vector2.ZERO
			model.walking = false
			reached_destination.emit(self)
			return
		target = itinerary[route_index]
	velocity = _navigation.movement(self, target, walk_speed, delta)
	move_and_slide()
	model.walking = velocity.length() > 1.0
	if model.walking: model.rotation.y = -velocity.angle() + PI * 0.5
	render_clock += delta
	if render_clock >= 0.083:
		model._process(render_clock)
		render_clock = 0.0
		var player := get_tree().get_first_node_in_group("player") as Node2D
		if player == null or global_position.distance_to(player.global_position) < 1100:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
