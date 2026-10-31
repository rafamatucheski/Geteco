extends "res://tests/measure/measure.gd"
## Same rendered production spawn, first 35 seconds and next 30 seconds.
## --no-save bypasses the user's save, --play-at selects a reproducible spawn.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var out := "res://evidence/background-loading-20261011/before.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): out = arg.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var begin := Time.get_ticks_usec()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("benchmark_trace",true)
	world.set_meta("background_loading_baseline","--background-baseline" in OS.get_cmdline_user_args())
	root.add_child(world)
	current_scene = world
	while not is_instance_valid(world.production) or not world.production.startup_streaming_settled or world.session == null or not world.session.ready_for_play:
		await process_frame
		if Time.get_ticks_usec()-begin > 180000000: push_error("STARTUP_TIMEOUT"); quit(3); return
	# Espera a cortina liberar a entrada, não a flag anterior de população pronta.
	while world.player.controlled_automatically:
		await process_frame
		if Time.get_ticks_usec()-begin > 180000000: quit(4); return
	var loading_ms := (Time.get_ticks_usec()-begin)/1000.0
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	var drive := "--drive" in OS.get_cmdline_user_args()
	var car: CharacterBody3D = world.driving.car
	var drive_start := Vector3.ZERO
	if drive:
		car.place(Vector3(-400,.15,-878.2),-PI/2.0)
		world.player.teleport(car.to_global(Vector3(-car.half_width-.65,.04,.15)))
		await physics_frame
		if not world.driving.interact(): push_error("DRIVE_ENTRY_FAILED"); quit(5); return
		while world.driving.is_body_transition_active(): await physics_frame
		car.set_external_driver(true)
		car.brake_input = false
		drive_start = car.global_position
	var intervals: Array[float] = []
	var early: Array[float] = []
	var states: Array = []
	var start := Time.get_ticks_usec()
	var previous_sample := start
	var next_state := start
	while Time.get_ticks_usec()-start < 65000000:
		if drive:
			var target := Vector3(car.global_position.x+20,car.global_position.y,-878.2)
			var direction: Vector3 = target-car.global_position
			car.steer_input = clampf(angle_difference(car.rotation.y,atan2(-direction.x,-direction.z))*2.0,-1,1)
			car.throttle_input = 1.0 if car.speed < 8.0 else 0.0
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now-previous_sample)/1000.0
		if now-start < 35000000: early.append(ms)
		else: intervals.append(ms)
		previous_sample = now
		if now >= next_state:
			next_state = now+1000000
			states.append({"t":(now-start)/1000000.0,"people":world.people.size(),"cars":world.production.vehicles.size(),"position":str(world.player.position),"queue":world.production.get("background_loading_status"),"driving":world.driving.occupied})
	var report := {"loading_ms":loading_ms,"early":stats(early),"steady":stats(intervals),"early_ms":early,"steady_ms":intervals,"states":states,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"region":world.production.state.region_id}
	if drive: report.drive_displacement = car.global_position.distance_to(drive_start)
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BACKGROUND_MEASURE ",loading_ms," early=",JSON.stringify(report.early)," steady=",JSON.stringify(report.steady))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.trim_suffix(".json")+".png")
	world.queue_free()
	for i in 3: await process_frame
	quit()
