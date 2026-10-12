extends "res://tests/measure/measure.gd"
## Rendered Main, normal population, real pedal actions, isolated no-save session.
var variant := "road-burnout"

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(12102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.camera.target_size = 24
	var car = world.driving.car
	# The starting plaza looks paved but its collider resolves as dirt. Use an
	# actual road for the rubber-smoke scenario, without overriding surface tags.
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var offset := route.get_closest_offset(car.position)
	var point := route.sample_baked(offset, true)
	var heading := route.sample_baked(minf(offset+1,route.get_baked_length()), true)-point
	car.place(point+Vector3.UP*.12, atan2(-heading.x,-heading.z))
	for tick in 12: await physics_frame
	var contacts: Array = car.effects.tire_effects._rear_contacts()
	if contacts.any(func(c): return c.is_empty() or c.kind != "hard"):
		push_error("Burnout benchmark requires two real asphalt contacts: " + str(contacts)); quit(7); return
	world.player.teleport(car.driver_door_anchor(-1))
	await physics_frame
	if not world.driving.interact(): push_error("Burnout benchmark could not board"); quit(4); return
	deadline = Time.get_ticks_msec() + 15000
	while not world.driving.occupied or world.driving.is_body_transition_active():
		await process_frame
		if Time.get_ticks_msec() > deadline: quit(5); return
	var origin: Vector3 = car.global_position
	if variant.contains("idle"):
		Input.action_press("handbrake")
	else:
		Input.action_press("accelerate", 1.0)
		Input.action_press("brake", 1.0)
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec() - begin < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		if now - begin < 8000000: cold.append(ms)
		else: samples.append(ms)
		last = now
	var folder := "res://output/vehicle-burnout/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var tires = car.effects.tire_effects
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"frames_ms":samples,"modes":tires.last_modes.duplicate(),"displacement":car.global_position.distance_to(origin),"archetype":car.archetype,"rpm":car.handling.drive.rpm,"wheelspin":car.handling.wheelspin,"traffic_count":get_nodes_in_group("drivable").size(),"notes":"Rendered Main, normal population, dry daytime, normal cap/vsync, real boarding and accelerate+brake actions. Eight seconds warmup, thirty measured, captures afterwards. No saves. Target 60 FPS/16.67ms; >5% p95/p99 increase requires finite confirmation."}
	report["held_skid_playing"] = is_instance_valid(tires.skid_audio) and tires.skid_audio.playing
	report["setup"] = "Road placement, then real boarding; held brake only for idle baseline, both pedals for burnout. Same production scene/population. Original before/after spawn runs are separate and resolved as dirt."
	report["warmup_frames_ms"] = cold
	for frame in 4:
		await create_timer(.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/held-%02d.png" % frame)
	Input.action_release("accelerate")
	await create_timer(2.0).timeout
	report["release_modes"] = tires.last_modes.duplicate()
	report["release_emitting"] = tires.emitters.any(func(e): return e.emitting)
	Input.action_release("brake")
	Input.action_release("handbrake")
	Input.action_press("accelerate")
	await create_timer(.5).timeout
	report["launch_speed"] = car.speed
	Input.action_release("accelerate")
	FileAccess.open(folder + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BURNOUT_BENCH ", variant, " ", JSON.stringify(report.summary), " modes=", report.modes, " release=", report.release_modes, " launch=", report.launch_speed)
	var held_valid: bool = report.modes == ["",""] if variant.contains("idle") else report.modes == ["smoke","smoke"] and report.held_skid_playing
	var valid: bool = held_valid and not report.release_emitting and report.launch_speed > .5 and report.displacement < .2
	world.free()
	await process_frame
	quit(0 if valid else 6)
