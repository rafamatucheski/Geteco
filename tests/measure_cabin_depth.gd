extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Cabin measurement timeout"); quit(2))
	seed(13092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	var scene = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.region_ready: await process_frame
	while not scene.interior_manager.region_ready: await process_frame
	for frame in 8: await physics_frame
	var actor = scene.player_instance
	var manager = scene.interior_manager
	var args := OS.get_cmdline_user_args()
	var room_id := StringName(args[1]) if args.size() > 1 else &"mountain_cabin"
	var cabin = manager._interiors[room_id]
	var entrance: BuildingEntrance
	for door in manager._exterior_doors:
		if manager._exterior_doors[door]["interior_id"] == room_id:
			entrance = door
			break
	if entrance == null:
		push_error("No registered entrance for " + String(room_id))
		quit(2)
		return
	actor.global_position = entrance.global_position + Vector2(0, 24)
	for frame in 3: await physics_frame
	if not entrance.request_interaction(actor):
		push_error("Cabin entry failed")
		quit(2)
		return
	await create_timer(1.0).timeout
	if args.size() > 2 and args[2] == "legacy":
		# Reproduce the previous renderer without rewriting production files.
		manager._actor_scale_helpers[actor].restore()
		manager._actor_scale_helpers[actor].queue_free()
		var legacy := preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		manager.add_child(legacy)
		legacy.configure(actor, cabin.camera_3d, cabin.sprite_3d)
		manager._actor_scale_helpers[actor] = legacy
		for presentation in cabin._resident_presentations.values():
			presentation.restore()
			presentation.queue_free()
		cabin._resident_presentations.clear()
	actor.global_position = cabin.to_global(cabin.project_floor(Vector2(0, 0.4))) if room_id == &"mountain_cabin" else cabin.to_global(cabin.room_view.project_floor(Vector2(0, 3)))
	scene.main_camera.reset_smoothing()
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	var elapsed := (previous - start) / 1000000.0
	var label := OS.get_cmdline_user_args()[0]
	var out := "D:/geteco/artifacts/interior-solids-0913/"
	var raw := FileAccess.open(out + label + ".json", FileAccess.WRITE)
	raw.store_string(JSON.stringify(samples))
	raw.close()
	var slow := 0
	var very_slow := 0
	for sample in samples:
		if sample > 33.3: slow += 1
		if sample > 66.7: very_slow += 1
	samples.sort()
	print("CABIN_PERF ", label, " GPU=", RenderingServer.get_video_adapter_name(), " max_fps=", Engine.max_fps, " vsync=", DisplayServer.window_get_vsync_mode(), " seconds=", elapsed, " frames=", samples.size(), " fps=", samples.size()/elapsed, " p50=", samples[int(samples.size()*.5)], " p95=", samples[int(samples.size()*.95)], " p99=", samples[int(samples.size()*.99)], " max=", samples.back(), " over33=", slow, " over66=", very_slow)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + label + ".png")
	quit()
