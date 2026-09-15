extends "res://tests/test_pedestrian_route_recovery.gd"

func run() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	seed(917)
	root.get_node("WantedManager").set_process(false)
	var crossing := preload("res://geodata/roads/safety/RoadCrossingArea2D.gd").new()
	crossing.configure({"id":"parked_crossing", "junction_id":"test", "position":Vector2.ZERO, "road_width":120.0})
	root.add_child(crossing)
	crossing.set_signal_state(false, true)
	var person := walker(PackedVector2Array([Vector2(0,-82), Vector2(0,82)]), Vector2(0,-82))
	var space := WALK_SPACE.new()
	var network := Node2D.new()
	root.add_child(network)
	space.configure(network, {"roads":[{"points":PackedVector2Array([Vector2(-500,0),Vector2(500,0)]),"width":120.0}]})
	network.free()
	person.walk_space = space
	person._corridor_segment = -1
	var bike := CharacterBody2D.new()
	bike.collision_layer = 2
	bike.collision_mask = 0
	var hull := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20,40)
	hull.shape = shape
	bike.add_child(hull)
	root.add_child(bike)
	bike.add_to_group("vehicle")
	await frames(2)
	var routes := preload("res://world/harbor/HarborPedestrianRoutes.gd")
	check(not routes.crossing_wait(person, Vector2(0,82)), "Parked motorcycle allows planning a physical detour")
	bike.velocity = Vector2(50,0)
	check(routes.crossing_wait(person, Vector2(0,82)), "Moving vehicle still prevents entering crossing")
	bike.velocity = Vector2.ZERO
	crossing.set_signal_state(true, false)
	person.position.x = 24.0
	check(routes.crossing_wait(person, Vector2(0,82)), "Offset pedestrian still obeys red signal")
	person.position.x = 0.0
	crossing.set_signal_state(false, true)
	var reached := false
	var max_side := 0.0
	var largest_step := 0.0
	var overlaps := false
	for i in 660:
		var before := person.position
		await physics_frame
		max_side = maxf(max_side, absf(person.position.x))
		largest_step = maxf(largest_step, before.distance_to(person.position))
		var closest := person.position.clamp(Vector2(-10,-20), Vector2(10,20))
		overlaps = overlaps or person.position.distance_to(closest) < 10.9
		if person.position.y > 72.0:
			reached = true
			break
	check(reached, "Resident walks around motorcycle and finishes crossing: %s" % person.position)
	check(max_side > 21.0 and max_side <= 28.1, "Detour stays within bounded crossing corridor")
	check(not overlaps and largest_step < 1.2, "Detour preserves body clearance without teleporting")
	person.free()
	bike.free()
	crossing.free()
	await frames(2)
	quit(0 if failures == 0 else 1)
