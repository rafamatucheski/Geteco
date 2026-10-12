extends "res://tests/measure/measure.gd"
## Rendered Main with normal population; repeated real entry/exit, isolated no-save.
var cycles := 0
var entry_rows: Array[Dictionary] = []
var failure := ""
var variant := "before"
var benchmark_finished := false

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		# Baseline snapshot replaces this resource only in this test process.
		# Never restore or overwrite concurrent workspace edits for A/B runs.
		if arg.begins_with("--boarding-source="):
			var boarding_script: GDScript = load("res://gameplay/VehicleBoardingPresentation.gd")
			boarding_script.source_code = FileAccess.get_file_as_string(arg.trim_prefix("--boarding-source="))
			if boarding_script.reload() != OK: quit(5); return
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
	while Time.get_ticks_usec() - begin < 38000000 and failure.is_empty():
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		if now - begin < 8000000: cold.append(ms)
		else: samples.append(ms)
		last = now
	if not failure.is_empty(): push_error(failure); quit(4); return
	var folder := "res://output/vehicle-entry-20261010/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"frames_ms":samples,"entries":entry_rows,"cycles":cycles,"notes":"Rendered Main, normal population, daytime dry, original cap/vsync. Fixture relocates Dante beside the same stationary car between real Driving.interact/leave cycles. No save writes; 8 seconds warmup then 30 seconds measured. No capture readbacks during measurement."}
	FileAccess.open(folder + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENTRY_BENCH ", variant, " ", JSON.stringify(report.summary), " cycles=", cycles)
	benchmark_finished = true
	world.free()
	await process_frame
	quit()

func _cycle() -> void:
	while not benchmark_finished and is_instance_valid(world):
		var car: CharacterBody3D = world.driving.car
		car.speed = 0
		car.velocity = Vector3.ZERO
		car.stop_boarding_motion()
		var door: Vector3 = car.driver_door_anchor(-1)
		world.player.teleport(door + car.global_basis.x * -.35 - car.global_basis.z * .7)
		await physics_frame
		await physics_frame
		if benchmark_finished: return
		var began := Time.get_ticks_msec()
		if not world.driving.interact(): failure = "entry rejected"; return
		var body = world.driving.transition
		entry_rows.append({"path_m":body._path_length,"duration_s":body.duration})
		while not benchmark_finished and world.driving.is_body_transition_active():
			await process_frame
			if Time.get_ticks_msec() - began > 12000: failure = "entry timeout"; return
		if benchmark_finished: return
		if not car.controlled or not world.player.seated: failure = "entry did not seat driver"; return
		if not world.driving.leave(): failure = "exit rejected"; return
		while not benchmark_finished and world.driving.is_body_transition_active(): await process_frame
		if benchmark_finished: return
		cycles += 1
