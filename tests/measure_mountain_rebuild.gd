extends SceneTree
var world: Node

func _hold_clock() -> void:
	if not is_instance_valid(world): return
	var bridge = world.get_node_or_null("CobraCampaign")
	if bridge and bridge.ledger:
		bridge.ledger.data.day_elapsed = 0.1 * preload("res://world/harbor/campaign/CobraCampaignState.gd").DAY_SECONDS
	world.weather.time_of_day = 0.45

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(300).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/mountain-rebuild-0913/saves")
	seed(912)
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/mountain-rebuild-0913/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	root.get_node("CampaignState").reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var scene = current_scene
	while not scene.gameplay_ready or not scene.world_build_ready: await process_frame
	var stream = scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	world = scene
	process_frame.connect(_hold_clock)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	scene.weather.is_dynamic_time = true
	scene.weather.time_of_day = 0.45
	scene.weather.set_weather(0)
	scene.weather._update_lighting()
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.zoom = Vector2.ONE
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	if "--final" in OS.get_cmdline_user_args(): label = "final"
	if "--delivered" in OS.get_cmdline_user_args(): label = "delivered"
	var walkable := "--resort-walkable" in OS.get_cmdline_user_args()
	if walkable: label = "walkable"
	print("CLIFF_ENV ", RenderingServer.get_video_adapter_name(), " renderer=", RenderingServer.get_current_rendering_method(), " vsync=", DisplayServer.window_get_vsync_mode(), " cap=", Engine.max_fps)
	var scenarios: Array = [] if "--capture-only" in OS.get_cmdline_user_args() else [Vector2(6950,-250), Vector2(7140,-2760), Vector2(7000,-3450)]
	if walkable: scenarios = [Vector2(7140,-2760)]
	for point in scenarios:
		player.global_position = stream.mountain.to_global(point)
		camera.global_position = player.global_position
		if walkable: player.global_position += Vector2(0,125)
		camera.make_current()
		for i in 120: await process_frame
		var samples: Array[float] = []
		var process_ms := 0.0
		var physics_ms := 0.0
		var draws := 0.0
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec()-start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-previous)/1000.0)
			process_ms += Performance.get_monitor(Performance.TIME_PROCESS)*1000.0
			physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			previous = now
		var total := float(previous-start)/1000000.0
		var raw := samples.duplicate()
		samples.sort()
		var report := {"label":label,"point":str(point),"seconds":total,"frames":samples.size(),"fps":samples.size()/total,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples[-1],"over33":samples.filter(func(v): return v>33.3).size(),"over66":samples.filter(func(v): return v>66.7).size(),"samples_ms":raw}
		var prefix := "D:/geteco/artifacts/mountain-rebuild-0913/%s-%d" % [label,abs(int(point.y))]
		report["process_mean_ms"] = process_ms/samples.size()
		report["physics_mean_ms"] = physics_ms/samples.size()
		report["draw_calls_mean"] = draws/samples.size()
		report["camera_zoom"] = str(camera.zoom)
		report["player_point"] = str(stream.mountain.to_local(player.global_position))
		FileAccess.open(prefix+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		report.erase("samples_ms")
		print("CLIFF_PERF ",JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(prefix+".png")
	quit()
