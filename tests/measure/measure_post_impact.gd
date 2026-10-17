extends "res://tests/measure/measure_katana_session.gd"
const PROPS = preload("res://gameplay/street_physics/FragileProps3D.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	output_dir = "res://evidence/post-impact/" + label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	seed(7)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world); current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	var point := Vector3(103, 0, 129)
	world.player.teleport(point)
	world.production.region.set_focus(point)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	await create_timer(8).timeout
	var items: Array = PROPS.query(point, 60).filter(func(item): return item.kind == "lamp")
	if items.is_empty(): push_error("No native lamp loaded"); quit(4); return
	var item: Dictionary = items[0]
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(item.point + Vector3(12, 9, 15), item.point + Vector3.UP * 3)
	camera.make_current()
	await create_timer(5).timeout
	var street = preload("res://gameplay/street_physics/StreetPhysics.gd").instance
	var frames_ms: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	PROPS.hit(item, 30.0, Vector3.RIGHT, street)
	var shot := 0
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames_ms.append((now - previous) / 1000.0); previous = now
		if shot < 3 and now - start >= (shot + 1) * 300000:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output_dir.path_join("impact-%d.png" % shot))
			shot += 1
	var report := summarize(frames_ms)
	report.engine = Engine.get_version_info().string
	report.gpu = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	report.resolution = str(root.size)
	report.vsync = DisplayServer.window_get_vsync_mode()
	report.max_fps = Engine.max_fps
	report.point = str(item.point)
	FileAccess.open(output_dir.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples_ms")
	print("POST_IMPACT ", label, " ", JSON.stringify(report))
	world.queue_free(); await process_frame
	quit()
