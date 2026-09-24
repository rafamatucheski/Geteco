extends SceneTree

const SAMPLE_SECONDS := 30.0
const OUTPUT_DIR := "geteco-boutique-inline-0922"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(170.0).timeout.connect(func(): quit(2))
	seed(13092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	var saves := root.get_node("SaveManager")
	var output_dir := OS.get_temp_dir().path_join(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_dir.path_join("saves"))
	saves._save_dir = output_dir.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready:
		await process_frame
	var player: CharacterBody2D = world.player_instance
	var facade: Node2D = world.find_child("ResortShopFacade", true, false)
	var room: Node2D = world.interior_manager.get_interior(&"mountain_boutique")
	if facade == null or room == null:
		push_error("Boutique Alpina is unavailable in MountainPass")
		quit(1)
		return
	player.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(OS.get_temp_dir().path_join(OUTPUT_DIR))
	player.global_position = facade.entrance.global_position + Vector2(0, 65)
	player.reset_physics_interpolation()
	for _i in 90:
		await process_frame
	if "--interior-only" not in OS.get_cmdline_user_args():
		await _measure("exterior", room)
	if room.get("inline_mode") == true:
		player.global_position = room.to_global(room.project_floor(Vector2(0, 0.5)))
	else:
		world.interior_manager._on_entrance_requested(facade.entrance, player, &"mountain_boutique", null, &"", facade.entrance)
	player.reset_physics_interpolation()
	await create_timer(5.0).timeout
	await _measure("interior", room)
	world.queue_free()
	await process_frame
	quit(0)

func _measure(label: String, room: Node2D) -> void:
	var samples := PackedFloat64Array()
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var elapsed := float(previous - start) / 1000000.0
	var values := Array(samples)
	values.sort()
	var result := {
		"scenario": label,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"fps_limit": Engine.max_fps,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"resolution": root.size,
		"seconds": elapsed,
		"frames": values.size(),
		"fps_mean": float(values.size()) / elapsed,
		"p50_ms": values[int((values.size() - 1) * .50)],
		"p95_ms": values[int((values.size() - 1) * .95)],
		"p99_ms": values[int((values.size() - 1) * .99)],
		"max_ms": values.back(),
		"over_33_ms": values.filter(func(v): return v > 33.3).size(),
		"over_66_ms": values.filter(func(v): return v > 66.7).size(),
	}
	var prefix := "after-confirm" if "--confirm" in OS.get_cmdline_user_args() else "after" if room.get("inline_mode") == true else "before"
	var path := OS.get_temp_dir().path_join(OUTPUT_DIR).path_join("%s-%s.json" % [prefix, label])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write measurement: " + path)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("BOUTIQUE MEASURE ", JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.trim_suffix(".json") + ".png")
