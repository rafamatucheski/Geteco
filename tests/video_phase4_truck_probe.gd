extends "res://tests/video_phase4_fall_probe.gd"
## Real impacts on the recorded Westgate junction; no overlapping spawn.
var cases: Array[Dictionary] = []
var truck: CharacterBody3D

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	seed(240924)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		check(false, "Main ready"); await finish(); return
	world.gameplay.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.set_population(0)
	world.player.teleport(Vector3(34, .05, 109))
	world.driving.car.queue_free()
	for frame in 4: await physics_frame
	for kind in ["cargo_flatbed_truck", "towmaster"]:
		for lateral in [-.9, 0.0, .9]:
			phase = kind + "_" + str(lateral)
			coupe = world.production.spawn_vehicle("sport_coupe", Vector3(26.7, .12, 109), 0)
			truck = world.production.spawn_vehicle(kind, Vector3(26.7 + lateral, .12, 120), 0)
			if not is_instance_valid(coupe) or not is_instance_valid(truck):
				check(false, phase + " admitted without overlap"); await finish(); return
			await frames(20)
			truck.set_external_driver(true)
			truck.speed = 11.0
			truck.horizontal_velocity = Vector3.FORWARD * 11.0
			truck.throttle_input = 1.0
			var case_min := coupe.global_position.y
			var case_max := case_min
			var touched := false
			var health_before: float = coupe.health
			for frame in 360:
				await physics_frame
				case_min = minf(case_min, coupe.global_position.y)
				case_max = maxf(case_max, coupe.global_position.y)
				record(frame % 30 == 0)
				if coupe.has_meta("crash_stun") or coupe.health < health_before: touched = true
				if touched:
					truck.throttle_input = 0.0
					truck.brake_input = true
				if coupe.health <= 0 or coupe.global_position.y < -2: break
			check(touched, phase + " actual vehicle impact")
			check(case_min > -.25, phase + " stays above terrain")
			check(coupe.is_on_floor(), phase + " remains grounded")
			cases.append({"case":phase,"min_y":case_min,"max_y":case_max,"impact":touched,"coupe_health":coupe.health,"coupe_position":str(coupe.global_position),"truck_position":str(truck.global_position)})
			coupe.queue_free()
			truck.queue_free()
			for frame in 4: await physics_frame
	await finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT + "fall-truck-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"cases":cases,"records":records,"samples":samples,"notes":"Main causal physics, real truck impacts from disjoint poses; current runtime including phase3 changes. No FPS claim."}, "\t"))
	file.close()
	if is_instance_valid(world):
		world.queue_free()
		for frame in 3: await physics_frame
	print("PHASE4_TRUCK cases=", cases.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
