extends SceneTree

var output_label := "before"
var samples: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("label="):
			output_label = arg.trim_prefix("label=")
	
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/resort-road-repair/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	create_timer(100).timeout.connect(func(): quit(2))
	var err := change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	if err != OK:
		push_error("Falha ao abrir cena MountainPass.tscn")
		quit(1)
		return

	while current_scene == null or not current_scene.get("region_ready"):
		await process_frame

	var mountain = current_scene
	var player: Node2D = mountain.player_instance
	if player:
		player.global_position = Vector2(6880, -2530)
		player.set_physics_process(false)
		if player.has_node("Camera"):
			var cam: Camera2D = player.get_node("Camera")
			cam.global_position = Vector2(6880, -2530)
			cam.zoom = Vector2.ONE
			cam.reset_smoothing()

	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = Vector2(6880, -2530)
	camera.zoom = Vector2.ONE * 1.2
	camera.set_meta("mountain_fixed_framing", true)
	camera.make_current()
	# 60 frames de aquecimento
	for i in 60:
		await process_frame
		camera.make_current()

	var frame_started := Time.get_ticks_usec()
	var sample_end := frame_started + 30000000
	while Time.get_ticks_usec() < sample_end:
		await process_frame
		camera.make_current()
		var frame_now := Time.get_ticks_usec()
		samples.append(float(frame_now - frame_started) / 1000.0)
		frame_started = frame_now

	var total_time := 0.0
	for t in samples:
		total_time += t
	samples.sort()
	var mean_ft := total_time / float(samples.size())
	var p50 := samples[int(samples.size() * 0.50)]
	var p95 := samples[int(samples.size() * 0.95)]
	var p99 := samples[int(samples.size() * 0.99)]
	var fps_calc := 1000.0 / mean_ft

	print("PERF_RESULT: label=%s samples=%d mean_ms=%.2f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f fps=%.1f" % [
		output_label, samples.size(), mean_ft, p50, p95, p99, fps_calc
	])
	var over_33 := 0
	var over_66 := 0
	for dt in samples:
		if dt > 33.3: over_33 += 1
		if dt > 66.7: over_66 += 1
	print("max_ms=%.2f >33.3=%d >66.7=%d adapter=%s" % [samples[-1], over_33, over_66, RenderingServer.get_video_adapter_name()])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/resort-road-repair/" + output_label + ".png")
	quit(0)
