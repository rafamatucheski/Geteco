extends "res://tests/measure/measure.gd"
## Real Main corner route, with traffic/NPCs and no save writes.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	var folder := "res://evidence/curb-access-20260925/" + variant
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): folder = arg.trim_prefix("--output=").path_join(variant)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(25092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.session != null and world.session.weather != null: break
	if world.session == null or world.session.weather == null:
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	world.player.teleport(Vector3(86.7, .16, 73.5))
	world.production._update_physical_residency(world.player.position)
	world.production._update_logical_region(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 20
	world.camera.initialized = false
	world.session.weather.time_of_day = .84
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 10000
	world.session.weather._update()
	world.session.weather.set_process(false)
	var warm: Array[float] = []
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	var begin := last
	while Time.get_ticks_usec() - begin < 8000000:
		await process_frame
		var now := Time.get_ticks_usec()
		warm.append((now-last)/1000.0)
		last = now
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + "/corner.png")
	last = Time.get_ticks_usec()
	begin = last
	while Time.get_ticks_usec() - begin < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last = now
		var t := (now-begin)/1000000.0
		# Finite back-and-forth through both vertical edges; no teleport in samples.
		world.player.automatic_direction = Vector3(0, 0, 1 if fmod(t, 4.0) < 2.0 else -1)
	world.player.automatic_direction = Vector3.ZERO
	var report := {"gpu":RenderingServer.get_video_adapter_name(), "engine":Engine.get_version_info().string, "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "population":world.people.size(), "traffic_children":world.traffic.get_child_count(), "summary":stats(frames), "warmup":stats(warm), "frames_ms":frames, "warmup_ms":warm}
	FileAccess.open(folder + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CURB_BENCHMARK ", variant, " ", JSON.stringify(report.summary))
	if "--capture-details" in OS.get_cmdline_user_args():
		await capture_details(folder)
	quit()

func capture_details(folder: String) -> void:
	# Real authored Market St slab: approach each free edge on foot.
	world.player.speed = 3.5
	var checks: Array = []
	for entry in [["west", Vector3(84.6,.03,73.5),Vector3.RIGHT,20], ["east",Vector3(93.0,.16,73.5),Vector3.LEFT,25], ["north",Vector3(89,.03,71.5),Vector3.BACK,30], ["south",Vector3(89,.03,76),Vector3.FORWARD,40]]:
		world.player.automatic_direction = Vector3.ZERO
		world.player.teleport(entry[1])
		world.camera.initialized = false
		for i in 10: await physics_frame
		world.player.automatic_direction = entry[2]
		for i in entry[3]: await physics_frame
		world.player.automatic_direction = Vector3.ZERO
		for i in 8: await physics_frame
		checks.append({"side":entry[0],"position":str(world.player.position),"on_floor":world.player.is_on_floor()})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/access-" + entry[0] + ".png")
	var anchor := Vector3(86.7,0,73.5)
	var nearest := Vector3.INF
	var distance := INF
	for node in world.find_children("CityLook_planter", "MultiMeshInstance3D", true, false):
		for i in node.multimesh.instance_count:
			var point: Vector3 = (node.global_transform * node.multimesh.get_instance_transform(i)).origin
			if point.distance_to(anchor) < distance:
				distance = point.distance_to(anchor)
				nearest = point
	if nearest.is_finite():
		for side in [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
			world.player.teleport(nearest + side * 1.6 + Vector3.UP * .15)
			world.camera.initialized = false
			world.player.automatic_direction = Vector3.ZERO
			for i in 10: await physics_frame
			world.player.automatic_direction = -side
			for i in 35: await physics_frame
			world.player.automatic_direction = Vector3.ZERO
			for i in 8: await physics_frame
			var separation: float = (world.player.position - nearest).dot(side)
			checks.append({"planter":str(nearest),"side":str(side),"separation":separation,"on_floor":world.player.is_on_floor()})
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + "/planter-%d.png" % checks.size())
	FileAccess.open(folder + "/access.json", FileAccess.WRITE).store_string(JSON.stringify(checks, "\t"))
