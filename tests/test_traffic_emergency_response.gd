extends SceneTree

const RULES := preload("res://cars/traffic/TrafficEmergencyYield.gd")
const BUDGET := preload("res://cars/traffic/TrafficSimulationBudget.gd")
const LIFE := preload("res://world/harbor/HarborLife.gd")
class Responder extends Node2D:
	var responding := true
	func has_emergency_priority() -> bool: return responding

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var path := Path2D.new()
	path.curve = Curve2D.new()
	path.curve.add_point(Vector2.ZERO)
	path.curve.add_point(Vector2(2200, 0))
	path.set_meta("traffic_road_width", 120.0)
	path.set_meta("traffic_lane_offset", 30.0)
	path.set_meta("traffic_direction", 1)
	world.add_child(path)
	var car := ModernTrafficFactory.spawn_moving_vehicle(path, "Civilian", "union_sedan", 0.4, 80.0, 1)
	car.set_process(false)
	car.set_physics_process(false)
	var unit := Responder.new()
	world.add_child(unit)
	unit.add_to_group("emergency_vehicle")
	unit.position = car.global_position - Vector2(120, 0)
	check(RULES.approaching(car, RULES.responders(self)) == unit, "Civilian notices an active responder approaching from behind")
	unit.rotation = PI
	check(RULES.approaching(car, RULES.responders(self)) == null, "Opposite direction does not make unrelated traffic pull over")
	unit.rotation = 0.0
	unit.responding = false
	check(RULES.responders(self).is_empty(), "Off-duty responder has no road priority")
	unit.responding = true
	check(BUDGET.active_conflict_actors(self).has(car.get_instance_id()), "Off-camera ambulance keeps its civilian queue awake")
	await physics_frame
	await physics_frame
	# Curved pull-over and merge are covered with a real ambulance in
	# test_siren_passage. Here exercise permission and obstacle refusal.
	path.set_meta("traffic_sidewalk_width",42.0)
	path.add_to_group("unified_lane_connector")
	check(not car._siren_maneuver.tick(car,path,car.get_parent(),.3),"Driver clears a connector instead of pulling over inside the intersection")
	path.remove_from_group("unified_lane_connector")
	car._siren_maneuver.retry = 0
	car._last_lane_motion_contract = {"reservation_granted":true}
	check(not car._siren_maneuver.tick(car,path,car.get_parent(),.3),"Committed junction owner keeps its crossing route")
	car._last_lane_motion_contract = {"controlled":true,"reservation_granted":false}
	check(not car._siren_maneuver.tick(car,path,car.get_parent(),.3),"Yielding never drives a civilian past an ungranted junction stop")
	car._last_lane_motion_contract = {}
	car._siren_maneuver.state = "idle"
	car._siren_maneuver.retry = 0
	car._siren_maneuver.tick(car,path,car.get_parent(),.3)
	check(car._siren_maneuver.offsets.size() == 1 and car._siren_maneuver.offsets[0] < 0.0,
		"Yielding plans the authored outside road edge, never across opposing lanes")
	car._siren_maneuver.state = "idle"
	car._siren_maneuver.route = null
	var barriers: Array[StaticBody2D] = []
	for side in [-1,1]:
		var person := StaticBody2D.new()
		person.collision_layer = 4
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(800,8)
		person.add_child(shape)
		world.add_child(person)
		person.position = car.global_position+Vector2(150,side*(car.collision.shape.size.y*.5+6))
		barriers.append(person)
	await physics_frame
	await physics_frame
	var start := car.global_position
	for frame in 120:
		car._siren_maneuver.tick(car,path,car.get_parent(),1.0/60)
		await physics_frame
	check(car.global_position.distance_to(start)<.01,"Both occupied shoulders prevent a pull-over through people")
	check(car._siren_maneuver.state != "pull_over","Unsafe trajectories are refused before the car starts steering")
	unit.position.x = car.global_position.x+200
	car._siren_maneuver.tick(car,path,car.get_parent(),.3)
	check(not car._emergency_yield_active,"A blocked driver resumes ordinary behavior after the responder passes")
	path.set_meta("traffic_road_width",64.0)
	path.set_meta("traffic_lane_offset",16.0)
	var life := LIFE.new()
	# Pure fleet selection does not need to instantiate the district population.
	var all_light := true
	for index in 120:
		all_light = all_light and life._traffic_archetype(path, index) != "cargo_flatbed_truck"
	check(all_light, "Narrow lanes use light city fleet across 120 spawn decisions")
	path.set_meta("traffic_road_width", 160.0)
	check(life._traffic_archetype(path, 0) == "cargo_flatbed_truck", "Wide long avenue can carry a delivery truck")
	life.free()
	world.queue_free()
	await process_frame
	print("TRAFFIC_EMERGENCY_RESPONSE failures=", failures)
	quit(1 if failures else 0)
