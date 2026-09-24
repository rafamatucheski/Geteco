extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	var arrival := preload("res://runtime/Arrival.gd").new()
	world.add_child(arrival)
	arrival.configure(session)
	arrival.active = true
	arrival.opening_completed = true
	arrival.flags = {"harbor_arrival_seen":true, "harbor_police_briefed":true, "harbor_arrival_call_complete":true}
	world.player.teleport(arrival.PARK + Vector3(4, .1, 0))
	session.controller.region.set_focus(arrival.PARK)
	for i in 12: await physics_frame
	arrival._spawn_encounter()
	var car: CharacterBody3D = arrival.car
	world.player.teleport(car.door_point(1))
	for i in 4: await physics_frame
	arrival._set_phase("tour_board", "", car.door_point(1))
	check(arrival.perform("arrival_board"), "real passenger boarding available")
	for i in 600:
		await physics_frame
		if arrival.riding or arrival.phase == "tour_board": break
	check(arrival.riding, "physical approach reaches both doors and seats")
	if arrival.riding:
		car.set_physics_process(false)
		arrival.set_physics_process(false)
		var stalled := 0
		for step in 12000:
			var before: Vector3 = car.global_position
			car._physics_process(1.0 / 60)
			arrival._physics_process(1.0 / 60)
			car.set_physics_process(false)
			stalled = stalled + 1 if before.distance_to(car.global_position) < .001 else 0
			if step % 60 == 0:
				session.controller.region.set_focus(car.global_position)
				await physics_frame
			if arrival.flags.get("harbor_city_tour_complete", false) or stalled > 600: break
		print("TOUR position=", car.global_position, " distance=", car.route_distance, "/", arrival.route.get_baked_length(), " blocked=", car.blocked, " riding=", arrival.riding)
		print("TOUR endpoint=", arrival.route.get_point_position(arrival.route.point_count - 1), " yaw=", car.rotation.y, " health=", car.health)
		for index in car.get_slide_collision_count(): print("TOUR collision=", car.get_slide_collision(index).get_collider().get_path())
		check(arrival.flags.get("harbor_city_tour_complete", false), "full original Harbor trip reaches garage physically")
		check(world.player.visible and world.player.collision_layer == 2, "passenger restored with collision")
		check(not arrival.maciota.has_method("receive_damage"), "Maciota remains immortal during journey")
		if arrival.flags.get("harbor_city_tour_complete", false):
			for i in 600:
				await physics_frame
				if not arrival.maciota.visible: break
			check(not arrival.maciota.visible, "Maciota physically walks to garage doorway")
	world.free()
	await process_frame
	print("ARRIVAL_DRIVE failures=", failures)
	quit(0 if failures.is_empty() else 1)
