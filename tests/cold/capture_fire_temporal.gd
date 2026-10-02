extends SceneTree
## Every rendered frame is recorded (not sparse screenshots). Capture overhead
## means these frame times are documentation of cadence, not an FPS benchmark.
var world
var folder := "res://evidence/fire-review-20261002/temporal"
var report: Array = []
func _initialize() -> void: _run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func record(label: String) -> void:
	var output := folder.path_join(label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var started := Time.get_ticks_usec()
	var times: Array[float] = []
	while Time.get_ticks_usec() - started < 30000000:
		await RenderingServer.frame_post_draw
		var timestamp := float(Time.get_ticks_usec() - started) / 1000.0
		var shot := root.get_texture().get_image()
		shot.resize(640, 360, Image.INTERPOLATE_BILINEAR)
		shot.save_jpg(output.path_join("frame_%05d.jpg" % times.size()), .86)
		times.append(timestamp)
		await process_frame
	report.append({"scene": label, "frames": times.size(), "timestamps_ms": times,
		"duration_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"capture": "every rendered frame; 640x360 JPEG; capture overhead included"})
	FileAccess.open(folder.path_join("temporal.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FIRE_TEMPORAL ", label, " frames=", times.size())
func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999
	world.session.weather._update()
	for heat in preload("res://runtime/cold/OriginalHeatSources.gd").SOURCES:
		var at: Vector3 = preload("res://runtime/cold/OriginalHeatSources.gd").to_world(heat.point)
		world.player.teleport(at + Vector3(0, .08, 3))
		world.production._update_physical_residency(at)
		world.production._update_logical_region(at)
		world.production.region.set_focus(at)
		await frames(120)
		world.camera.set_process(false)
		world.camera.global_position = at + Vector3(0, 9, 8)
		world.camera.look_at(at + Vector3.UP * .4)
		world.camera.size = 11
		await frames(3)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("source_" + str(heat.id) + ".png"))
		print("FIRE_SOURCE_CAPTURE ", heat.id)
	var source := preload("res://runtime/cold/OriginalHeatSources.gd").to_world(Vector2(7310, -2700))
	world.player.teleport(source + Vector3(0, .08, 2))
	world.production._update_physical_residency(source)
	world.production._update_logical_region(source)
	world.production.region.set_focus(source)
	await frames(240)
	for daytime in [.45, .9]:
		world.session.weather.time_of_day = daytime
		world.session.weather.weather_state = 0
		world.session.weather.weather_timer = 99999
		world.session.weather._update()
		world.camera.set_process(false)
		world.camera.global_position = source + Vector3(0, 9, 8)
		world.camera.look_at(source + Vector3.UP * .4)
		world.camera.size = 11
		await frames(30)
		await record("resort_day" if daytime < .5 else "resort_night")
	world.camera.set_process(true)
	if not await world.session.enter_place("ski_lodge", false): quit(1); return
	await frames(120)
	var hearth: Vector3 = world.session.room.to_global(Vector3(-5.9, .65, 3.2))
	world.camera.set_process(false)
	world.camera.global_position = hearth + Vector3(0, 9, 8)
	world.camera.look_at(hearth)
	world.camera.size = 9
	await record("summit_interior")
	world.queue_free()
	await frames(8)
	quit(0)
