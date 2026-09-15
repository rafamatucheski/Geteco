extends SceneTree
class TestTransit extends "res://world/harbor/urban_transit/UrbanTransit.gd":
	func _ready() -> void: pass
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(25,true,false,true).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var fleet := TestTransit.new()
	world.add_child(fleet)
	var bus := preload("res://cars/traffic/TrafficVehicle.tscn").instantiate() as CharacterBody2D
	bus.set_script(preload("res://world/harbor/urban_transit/UrbanBus.gd"))
	bus.system = fleet
	world.add_child(bus)
	bus._detached_from_lane = true
	bus.is_driven_by_player = true
	bus._drive_input_armed = true
	await physics_frame
	Input.action_press("move_up")
	await create_timer(1.0).timeout
	Input.action_release("move_up")
	check(bus.global_position.x>10,"articulated accelerates")
	check(bus.sections[0].global_position.x > -129,"rear follows acceleration")
	Input.action_press("move_right")
	Input.action_press("move_up")
	await create_timer(1.0).timeout
	Input.action_release("move_right")
	Input.action_release("move_up")
	check(absf(bus.rotation)>.05,"steering turns front body")
	check(absf(angle_difference(bus.rotation,bus.sections[0].rotation))>.01,"front articulation bends")
	bus.velocity = Vector2.ZERO
	var reverse_start := bus.global_transform
	Input.action_press("move_down")
	await create_timer(.5).timeout
	Input.action_release("move_down")

	check((bus.global_position-reverse_start.origin).dot(reverse_start.x)<-.1,"reverse applies backward motion")
	check(bus.sections[0].global_position.distance_to(bus.global_position)<145,"reverse retains coupled sections")
	var hulls: Array[PackedVector2Array] = []
	for body in bus.get_traffic_bodies():
		var hull := preload("res://cars/traffic/TrafficBodySweep.gd").rectangle(body,body.global_transform)
		for other in hulls:
			check(Geometry2D.intersect_polygons(hull,other).is_empty(),"reverse cannot fold sections through each other")
		hulls.append(hull)
	bus.is_driven_by_player = false
	bus.velocity = Vector2.ZERO
	await create_timer(.2).timeout
	print("ARTICULATED failures=",failures)
	quit(0 if failures.is_empty() else 1)
