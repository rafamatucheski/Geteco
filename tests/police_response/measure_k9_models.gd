extends "res://tests/police_response/measure_response.gd"
## Two visible, animated K9 models in Main's normal populated city.
## Isolates presentation cost; functional combat is covered separately.

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args: quit(2); return
	label = "before" if "--baseline" in args else "after"
	output = "res://evidence/k9-options-20261002"
	var model: Script = load("res://evidence/k9-options-20261002/baseline_models.gd") if label == "before" else load("res://gameplay/police_response/air_k9/AirK9Models.gd")
	seed(20261002)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(240).timeout.connect(func(): quit(3))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(4); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = 0.45
	if "--paired" in args:
		for trial in ["old-a", "new-a", "new-b", "old-b"]:
			label = trial
			model = load("res://evidence/k9-options-20261002/baseline_models.gd") if trial.begins_with("old") else load("res://gameplay/police_response/air_k9/AirK9Models.gd")
			await sample_models(model)
	else:
		await sample_models(model)
	world.queue_free()
	await process_frame
	quit(0)

func sample_models(model: Script) -> void:
	var visuals: Array[Node3D] = []
	var rigs: Array[Dictionary] = []
	for index in 2:
		var visual := Node3D.new()
		world.add_child(visual)
		visuals.append(visual)
		visual.global_position = world.player.global_position + Vector3(-1.5 + index * 3.0, 0, -2.0)
		rigs.append(model.dog(visual))
	var frames: Array[float] = []
	var warm: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - previous) / 1000.0
		previous = now
		var gait := float(now - start) / 1000000.0 * 8.0
		for rig in rigs:
			for index in 4: rig.legs[index].rotation.x = sin(gait + (PI if index in [1, 2] else 0.0)) * 0.5
		if now - start < 8000000: warm.append(ms)
		else: frames.append(ms)
	var report := {"label": label, "scene": "res://Main.tscn", "dogs": 2, "seed": 20261002,
		"gpu": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"population": world.people.size(), "camera": str(world.camera.global_transform),
		"summary": stats(frames), "warmup": stats(warm), "frames_ms": frames, "warmup_ms": warm}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label + "-models.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("K9_MODELS_MEASURE ", JSON.stringify(report.summary))
	for visual in visuals: visual.queue_free()
	await process_frame
