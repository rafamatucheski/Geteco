extends "res://tests/measure/measure.gd"
## Rendered Main with normal population; repeated throttle release, no saves.
var cycles := 0
var variant := "before"
var benchmark_finished := false

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(10102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if not world.session.ready_for_play or not world.production.no_save: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.camera.target_size = 32
	var begin := Time.get_ticks_usec()
	var last := begin
	_cycle()
	while Time.get_ticks_usec() - begin < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		if now - begin < 8000000: cold.append(ms)
		else: samples.append(ms)
		last = now
	var folder := "res://output/coasting-fix/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"frames_ms":samples,"cycles":cycles,"notes":"Rendered Main, normal population, daytime dry, original cap/vsync. Controlled car released from 12 m/s at its spawn every two seconds. Eight seconds warmup then thirty measured. No saves."}
	FileAccess.open(folder + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("COAST_BENCH ", variant, " ", JSON.stringify(report.summary), " cycles=", cycles)
	benchmark_finished = true
	world.free()
	await process_frame
	quit()

func _cycle() -> void:
	var car = world.driving.car
	car.controlled = true
	var origin: Vector3 = car.position
	var heading: float = car.rotation.y
	while not benchmark_finished:
		car.position = origin
		car.rotation.y = heading
		car.speed = 12.0
		car.horizontal_velocity = -car.global_basis.z * 12.0
		car.handling.reset()
		for tick in 120:
			await physics_frame
			if benchmark_finished: return
		cycles += 1
