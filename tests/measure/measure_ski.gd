extends "res://tests/measure/measure.gd"
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	label = "ski-before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	if "--baseline" in OS.get_cmdline_user_args():
		var source := GDScript.new()
		source.source_code = FileAccess.get_file_as_string("res://evidence/ski/MountainProgression.before.gd.txt")
		if source.reload() != OK: quit(2); return
		world.session.mountain_progression.free()
		world.session.mountain_progression = source.new()
		world.add_child(world.session.mountain_progression)
		world.session.mountain_progression.configure(world.session)
		await process_frame
	if not world.production.travel("mountain"): quit(1); return
	for i in 600:
		await physics_frame
		if not world.production.travel_busy: break
	var origin := DEFINITIONS.at(Vector2(6600,-3050), "mountain")
	world.production.region.set_focus(origin)
	world.player.teleport(origin + Vector3.UP * .1)
	world.camera.initialized = false
	world.camera.target_size = 32
	world.session.weather.time_of_day = .5
	world.session.weather.weather_state = 1
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	route = PackedVector3Array([origin, DEFINITIONS.at(Vector2(6570,-4010), "mountain")])
	for i in 180: await physics_frame
	started = Time.get_ticks_usec()
	previous = started
func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://evidence/ski")
	var report := {"label":label,"scene":"Main.tscn / ski","gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"population":world.people.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"intervals_ms":samples,"warmup_ms":cold,"route":str(route),"concurrent_processes":"Other Godot processes present; diagnostic only"}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ski/"+label+".png")
	var file := FileAccess.open("res://evidence/ski/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("SKI_BENCHMARK ", JSON.stringify(report.summary))
	quit()
