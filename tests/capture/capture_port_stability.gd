extends SceneTree
## Temporal evidence in Main; saves every rendered frame, separately from FPS measurements.
var world
var folder := "res://evidence/port-glitches-20260929/before"
var duration := 8.0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): folder = "res://evidence/port-glitches-20260929/"+arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--seconds="): duration = float(arg.trim_prefix("--seconds="))
	root.size = Vector2i(1280,720)
	seed(29092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	Engine.max_fps = 30
	var scenarios := ["loading", "day", "night"]
	if "--day-only" in OS.get_cmdline_user_args(): scenarios = ["day"]
	if "--loading-only" in OS.get_cmdline_user_args(): scenarios = ["loading"]
	for scenario in scenarios:
		world.session.weather.time_of_day = .9 if scenario == "night" else .4
		world.session.weather.weather_state = 0
		world.session.weather._update()
		world.player.automatic_direction = Vector3.ZERO
		world.player.teleport(Vector3(258,.1,219) if scenario == "loading" else Vector3(289,.1,232))
		world.production.region.set_focus(world.player.position)
		world.camera.heading = PI*.25
		world.camera.target_size = 30
		world.camera.initialized = false
		for i in 90: await process_frame
		var target: String = folder+"/"+scenario
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target))
		var rows: Array = []
		var start := Time.get_ticks_usec()
		var frame := 0
		while Time.get_ticks_usec()-start < duration*1000000:
			var elapsed := (Time.get_ticks_usec()-start)/1000000.0
			if scenario != "loading":
				world.player.automatic_direction = Vector3.RIGHT * (1 if elapsed < duration*.5 else -1) if elapsed > 2 else Vector3.ZERO
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(target+"/%05d.jpg"%frame,.93)
			var cargo = world.session.urban_operations.cargo_handling
			var trucks: Array = []
			for i in cargo.work_trucks.size():
				var state: Dictionary = cargo.work_trucks[i]
				trucks.append({"phase":state.phase,"clock":cargo.cranes[i].clock,"cargo":str(cargo.cranes[i].visual.global_transform),"truck":str(state.truck.global_transform) if is_instance_valid(state.truck) else "missing"})
			rows.append({"frame":frame,"time_us":Time.get_ticks_usec()-start,"camera":str(world.camera.global_transform),"trucks":trucks})
			frame += 1
			await process_frame
		FileAccess.open(target+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
		print("PORT_TEMPORAL ",scenario," frames=",frame)
	world.queue_free()
	for i in 5: await process_frame
	quit()
