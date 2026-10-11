extends "res://tests/measure/measure_pedestrian_game.gd"
## Main real, rua com tráfego/pedestres e resposta policial. A/B conserva atores e só alterna a correção de pose.
const RIG := preload("res://assets/civilians/MeshyBodyRig.gd")

func _ready_world() -> bool:
	var deadline := Time.get_ticks_msec() + 80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if is_instance_valid(world) and world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	return _check(world.session.ready_for_play, "Main pronto para medir") and _check(world.production.store.path == path, "somente fixture isolada, inclusive com no-save")

func _police_counts() -> Dictionary:
	var imported := 0
	var in_view := 0
	var camera := root.get_camera_3d()
	for officer in world.gameplay.police:
		if not is_instance_valid(officer) or officer.get("dead") == true: continue
		var visual: Node3D = officer.get("visual")
		if not is_instance_valid(visual): continue
		var body: Node3D = visual.get("body")
		if not is_instance_valid(body) or body.get("skeleton") == null: continue
		imported += 1
		if camera != null and camera.is_position_in_frustum(body.to_global(Vector3(0, 1.0, 0))): in_view += 1
	return {"total": world.gameplay.police.size(), "imported": imported, "in_view": in_view}

func _run() -> void:
	if DisplayServer.get_name() == "headless": _finish(2); return
	output_dir = "res://evidence/npc-meshy/refinement-20261011/perf-game-contact"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	folder = FIXTURE.output_dir("meshy-contact-game")
	path = FIXTURE.write_fixture(folder, "checkpoint.json", _seed())
	var launch := root.get_node_or_null("V2Launch")
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	root.size = Vector2i(1280, 720)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	world.player.teleport(Vector3(166, .08, 111.8))
	var walk_start: Vector3 = world.player.global_position
	world.player.automatic_direction = Vector3.FORWARD
	await create_timer(1.0).timeout
	world.player.automatic_direction = Vector3.ZERO
	if not _check(world.player.global_position.distance_to(walk_start) > .5, "jogador caminhou pela física de Main renderizada"):
		_finish(1)
		return
	# Usa o despacho produtivo; não injeta uma formação de PoliceModel no lugar da resposta de jogo.
	world.gameplay.register_crime(60, world.player.global_position)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(20.0).timeout
	var police_deadline := Time.get_ticks_msec() + 60000
	while _police_counts().in_view == 0 and Time.get_ticks_msec() < police_deadline:
		await create_timer(1.0).timeout
	if not _check(_police_counts().in_view > 0, "resposta produtiva trouxe policial Meshy à câmera"):
		_finish(1)
		return
	for index in 6:
		var refined := index in [1, 2, 5]
		RIG.correct_hand_reach = refined
		await create_timer(5.0).timeout
		var before := _counts()
		var officers_before := _police_counts()
		frame_ms.clear()
		draw_calls.clear()
		stamp = Time.get_ticks_usec()
		recording = true
		await create_timer(30.0).timeout
		recording = false
		var sorted := frame_ms.duplicate()
		sorted.sort()
		var total := 0.0
		var over33 := 0
		var over66 := 0
		for value in frame_ms:
			total += value
			if value > 33.3: over33 += 1
			if value > 66.7: over66 += 1
		var draw_total := 0.0
		for value in draw_calls: draw_total += value
		var n := sorted.size()
		var row := {"round": index, "kind": "refined" if refined else "legacy", "frames": n,
			"p50": sorted[int(n * .50)], "p95": sorted[int(n * .95)], "p99": sorted[int(n * .99)],
			"max": sorted.back(), "fps": n * 1000.0 / total, "over33": over33, "over66": over66,
			"draw_calls_mean": draw_total / draw_calls.size(), "bodies_before": before, "bodies_after": _counts(),
			"officers_before": officers_before, "officers_after": _police_counts(), "stars": world.gameplay.stars,
			"invalid_round": officers_before.in_view == 0 or _police_counts().in_view == 0 or officers_before != _police_counts() or before != _counts()}
		results.append(row)
		var raw := FileAccess.open("%s/raw-%d.json" % [output_dir, index], FileAccess.WRITE)
		raw.store_string(JSON.stringify({"frame_ms": frame_ms, "draw_calls": draw_calls}))
		print("MESHY_GAME_AB ", JSON.stringify(row))
	var out := FileAccess.open(output_dir + "/ab-game.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"environment": {"engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [1280, 720], "warmup_s": 5, "window_s": 30, "vsync": false, "max_fps": 0}, "rounds": results}, "\t"))
	RIG.correct_hand_reach = true
	_finish(0)
