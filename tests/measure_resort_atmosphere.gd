extends SceneTree
var out := "D:/geteco/artifacts/resort-atmosphere/before"
var mountain: Node2D
var actor: Node2D
var camera: Camera2D
var weather: Node
var failures := 0
var review_only := false

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): out = arg.trim_prefix("out_dir=")
		if arg == "--review": review_only = true
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("SaveManager")._save_dir = out + "/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	seed(15092026)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	if not review_only:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	create_timer(240).timeout.connect(func(): push_error("Resort atmosphere deadline"); quit(2))
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	while current_scene == null or not current_scene.get("region_ready"): await process_frame
	mountain = current_scene
	while not mountain.interior_manager.region_ready: await process_frame
	actor = mountain.player_instance
	weather = mountain.get_node("DayNightWeather")
	weather.is_dynamic_time = false
	weather.time_of_day = 0.9
	weather._update_lighting()
	mountain.storm_manager.weather_clock = 0.0
	mountain.storm_manager.advance_weather(0)
	actor.set_physics_process(false)
	camera = Camera2D.new()
	camera.set_meta("mountain_fixed_framing", true)
	root.add_child(camera)
	camera.zoom = Vector2.ONE * 1.2
	actor.global_position = Vector2(7210,-2690)
	camera.position = actor.global_position
	camera.make_current()
	await _sample("resort-night")
	for id in [&"mountain_cabin", &"ski_lodge"]:
		var manager = mountain.interior_manager
		var room = manager._interiors[id]
		var entrance: BuildingEntrance
		for door in manager._exterior_doors:
			if manager._exterior_doors[door].interior_id == id:
				entrance = door
				break
		assert(entrance != null)
		actor.global_position = entrance.global_position + Vector2(0,24)
		for frame in 3: await physics_frame
		assert(entrance.request_interaction(actor), "Real entrance must admit actor")
		await create_timer(1.0).timeout
		camera.position = room.global_position
		camera.zoom = Vector2.ONE
		camera.make_current()
		assert(actor.has_meta("interior_actor_presentation"), "Actor uses real room depth")
		assert(weather.is_inside_interior and not weather.atmosphere.visible, "Exterior fog stops indoors")
		await _sample(String(id))
		actor.global_position = room.exit_door.global_position
		for frame in 3: await physics_frame
		assert(room.exit_door.request_interaction(actor), "Real exit remains usable")
		await create_timer(1.0).timeout
		# Projected exterior facades can legitimately acquire their own adapter.
		if actor.has_meta("mountain_interior") or actor.model_root.get_viewport() == room.viewport_3d:
			push_error("Exit did not restore actor: " + String(id) + " position=" + str(actor.global_position) + " interior=" + str(actor.get_meta("mountain_interior_id", "none")))
			quit(1)
			return
		assert(not weather.is_inside_interior and weather.atmosphere.visible, "Cold exterior returns")
	print("RESORT_ATMOSPHERE completed: three rendered samples, real entry and exit")
	quit(failures)

func _sample(label: String) -> void:
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < (1000000 if review_only else 30000000):
		await process_frame
		camera.make_current()
		var now := Time.get_ticks_usec()
		samples.append((now - previous)/1000.0)
		previous = now
	var seconds := (previous-start)/1000000.0
	FileAccess.open(out+"/"+label+"-frames.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
	var slow := 0
	var very_slow := 0
	for value in samples:
		if value > 33.333: slow += 1
		if value > 66.667: very_slow += 1
	samples.sort()
	var report := {"scenario":label,"review_only":review_only,"frames":samples.size(),"seconds":seconds,"fps":samples.size()/seconds,
		"p50_ms":samples[int(samples.size()*.5)],"p95_ms":samples[int(samples.size()*.95)],"p99_ms":samples[int(samples.size()*.99)],
		"max_ms":samples.back(),"over_33ms":slow,"over_66ms":very_slow,"gpu":RenderingServer.get_video_adapter_name(),
		"engine":Engine.get_version_info(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps}
	FileAccess.open(out+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RESORT_ATMOSPHERE ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/"+label+".png")
