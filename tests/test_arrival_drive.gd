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
	for i in 240:
		await physics_frame
		if session.arrival.phase == "complete": break
	check(session.arrival.phase == "complete", "skipped opening finishes before tour fixture")
	var arrival = session.arrival
	arrival.active = true
	arrival.opening_completed = true
	arrival.flags = {"harbor_arrival_seen":true, "harbor_police_briefed":true, "harbor_arrival_call_complete":true}
	world.player.teleport(arrival.PARK + Vector3(4, .1, 0))
	session.controller.region.set_focus(arrival.PARK)
	for i in 600:
		await physics_frame
		if session.controller.region.is_streaming_idle(): break
	check(session.controller.region.is_streaming_idle(), "arrival yard collision streamed before boarding")
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
		var stalled := 0
		# Avança o mundo junto do passeio para o trânsito que compartilha a via
		# dirigir e liberar a faixa; passos manuais congelavam os outros carros.
		# A rota tem 201 m; o teto inclui circulação e filas reais sem permitir
		# que uma parada contínua acima de 30 s passe despercebida.
		for step in 9000:
			var before: Vector3 = car.global_position
			await physics_frame
			stalled = stalled + 1 if before.distance_to(car.global_position) < .001 else 0
			# Uma fila de cruzamento pode conter mais de um carro; cada reserva
			# expira após 8 s quando o dono fica preso.
			if arrival.flags.get("harbor_city_tour_complete", false) or stalled > 1800: break
		print("TOUR position=", car.global_position, " distance=", car.route_distance, "/", arrival.route.get_baked_length(), " blocked=", car.blocked, " blocker=", car.blocker.get_path() if is_instance_valid(car.blocker) and car.blocker is Node else str(car.blocker), " riding=", arrival.riding)
		if is_instance_valid(car.blocker) and car.blocker is Node3D:
			print("TOUR blocker_position=", car.blocker.global_position, " ambient=", car.blocker.get_meta("ambient_traffic", false), " traffic=", car.blocker.get("traffic"), " controlled=", car.blocker.get("controlled"), " player_car=", car.blocker == world.driving.car)
		print("TOUR endpoint=", arrival.route.get_point_position(arrival.route.point_count - 1), " yaw=", car.rotation.y, " speed=", car.speed, " junction_wait=", car.junction_wait, " health=", car.health)
		if car.junction_wait: print("TOUR junction owners=", preload("res://gameplay/traffic_junctions/TrafficJunctions.gd").owners, " held=", car._held_junction)
		for index in car.get_slide_collision_count(): print("TOUR collision=", car.get_slide_collision(index).get_collider().get_path())
		if not arrival.flags.get("harbor_city_tour_complete", false):
			print("ARRIVAL_DRIVE_FAIL position=", car.global_position, " distance=", car.route_distance, "/", arrival.route.get_baked_length(), " stalled_frames=", stalled, " blocked=", car.blocked, " junction_wait=", car.junction_wait, " blocker=", car.blocker.get_path() if is_instance_valid(car.blocker) and car.blocker is Node else str(car.blocker))
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
