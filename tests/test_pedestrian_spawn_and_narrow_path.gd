extends "res://tests/test_pedestrian_route_recovery.gd"

func run() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	seed(915)
	root.get_node("WantedManager").set_process(false)
	var route := PackedVector2Array([Vector2.ZERO, Vector2(280, 0)])
	var post := obstacle(Vector2(50, 0), Vector2(16, 16))
	await frames(2)
	var person := LIFE.HarborWalker.new()
	person.defer_presentation = true
	person.configure_authored_route(route, "spawn_clearance", 50.0)
	root.add_child(person)
	person.set_physics_process(false)
	check(person.position.distance_to(Vector2(50, 0)) >= 19.0, "Initial spawn is placed outside a solid prop")
	check(person.movement_navigation.clear_segment(person, person.position, person.position), "Spawn has full physical body clearance")
	person.free()
	post.free()
	await frames(2)
	var space := WALK_SPACE.new()
	var network := Node2D.new()
	root.add_child(network)
	space.configure(network, {"roads":[{"points":PackedVector2Array([Vector2(-500,-71.5), Vector2(500,-71.5)]), "width":120.0}]})
	network.free()
	var wall := obstacle(Vector2(150,25), Vector2(260,20))
	person = walker(route, Vector2(0,7.4))
	person.walk_space = space
	person._corridor_segment = -1
	var min_y := INF
	var max_x := 0.0
	for i in 360:
		await physics_frame
		min_y = minf(min_y, person.position.y)
		max_x = maxf(max_x, person.position.x)
	check(max_x > 120.0, "Search resolves a free strip between coarse grid columns: x=%.2f" % max_x)
	check(min_y >= -0.01, "Refined search retains the road boundary")
	person.free()
	wall.free()
	await frames(2)
	print("PEDESTRIAN_SPAWN_NARROW failures=%d" % failures)
	quit(0 if failures == 0 else 1)
