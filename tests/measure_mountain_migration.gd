extends SceneTree

const IDS := [&"mountain_outfitters", &"mountain_village_outfitters"]
const SAMPLE_SECONDS := 30.0
const OUTPUT_DIR := "geteco-mountain-inline-0922"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(420.0).timeout.connect(func(): quit(2))
	seed(23092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	var saves := root.get_node("SaveManager")
	var out := OS.get_temp_dir().path_join(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(out.path_join("saves"))
	saves._save_dir = out.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var world: Node2D = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.region_ready or not world.interior_manager.region_ready:
		await process_frame
	var player: CharacterBody2D = world.player_instance
	player.set_physics_process(false)
	var selected: Array[StringName] = [&"mountain_outfitters", &"mountain_village_outfitters"]
	if "--cabins" in OS.get_cmdline_user_args():
		selected.clear()
		selected.append_array([
			&"mountain_cabin", &"mountain_cabin_encosta", &"mountain_cabin_forest",
			&"mountain_cabin_village_1", &"mountain_cabin_village_2",
			&"mountain_cabin_village_3", &"mountain_cabin_village_4",
		])
	if "--cabin-sample" in OS.get_cmdline_user_args():
		selected.clear()
		selected.append_array([&"mountain_cabin", &"mountain_cabin_encosta", &"mountain_cabin_forest", &"mountain_cabin_village_1"])
	if "--cabin-village-rest" in OS.get_cmdline_user_args():
		selected.clear()
		selected.append_array([&"mountain_cabin_village_2", &"mountain_cabin_village_3", &"mountain_cabin_village_4"])
	if "--remainder" in OS.get_cmdline_user_args():
		selected.clear()
		selected.append_array([&"lumberjack_shelter", &"ski_lodge", &"mountain_bunker", &"mountain_mystery_cave"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			selected.clear()
			selected.append(StringName(arg.trim_prefix("--id=")))
	var prefix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	for id in selected:
		var entrance: BuildingEntrance = find_entrance(world, id)
		if entrance == null:
			for candidate in world.interior_manager._exterior_doors:
				if world.interior_manager._exterior_doors[candidate].interior_id == id:
					entrance = candidate
					break
		var room: Node2D = world.interior_manager.get_interior(id)
		if entrance == null or room == null:
			push_error("Missing entrance or room: " + String(id))
			quit(1)
			return
		player.global_position = entrance.global_position + Vector2(0, 45)
		player.reset_physics_interpolation()
		for _i in 90: await process_frame
		if "--interiors-only" not in OS.get_cmdline_user_args():
			await measure(out, prefix + "-" + String(id) + "-exterior")
		if room.get("inline_mode") == true:
			player.global_position = room.to_global(room.project_floor(Vector2(0, .5)))
		else:
			world.interior_manager._on_entrance_requested(entrance, player, id, null, &"", entrance)
		player.reset_physics_interpolation()
		await create_timer(5.0).timeout
		await measure(out, prefix + "-" + String(id) + "-interior")
		if room.get("inline_mode") == true:
			player.global_position = entrance.global_position + Vector2(0, 45)
		else:
			world.interior_manager._on_exit_requested(null, player, &"", null, &"", id)
		for _i in 8: await process_frame
	world.queue_free()
	await process_frame
	quit(0)

func find_entrance(parent: Node, id: StringName) -> BuildingEntrance:
	if parent is BuildingEntrance and parent.destination_id == id: return parent
	for child in parent.get_children():
		var match_door := find_entrance(child, id)
		if match_door != null: return match_door
	return null

func measure(out: String, label: String) -> void:
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
	var path := out.path_join(label + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write " + path)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("MOUNTAIN_MEASURE ", JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.trim_suffix(".json") + ".png")
