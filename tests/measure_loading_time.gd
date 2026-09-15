extends SceneTree
## Render the production loader, then measure the first 30 seconds of driving.
## Usage: --script res://tests/measure_loading_time.gd -- <absolute output dir>
## Run with isolated APPDATA; no existing player save is restored or overwritten.
var output := ""
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().is_empty():
		push_error("Requires a renderer and an absolute output directory")
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	assert(output.is_absolute_path())
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	seed(13092026)
	var campaign = root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var saves = root.get_node("SaveManager")
	saves._save_dir = output.path_join("saves") + "/"
	saves._save_directory_ready = false
	var loader = root.get_node("GameLoading")
	loader.failed.connect(func(message): push_error(message); quit(1))
	create_timer(180.0).timeout.connect(func(): push_error("Loading probe timed out"); quit(1))
	loader.begin("res://world/harbor/HarborGame.tscn")
	await loader.finished
	var result = {"phases":loader.phase_times_ms.duplicate(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"fps_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"nodes":get_node_count()}
	print("LOADING_PHASES ", JSON.stringify(result))
	assert(current_scene.gameplay_ready and current_scene.world_build_ready and not paused)
	# Release controls after the entry view is ready. Distant presentations stay
	# queued and are resolved by proximity instead of blocking every save load.
	var pool = root.get_node("EmergencyPool")
	for fleet in pool._pool.values():
		for vehicle in fleet: assert(is_instance_valid(vehicle.visual_3d))
	for reserve in pool._officer_reserve.values(): assert(reserve.size() == 14)
	var deferred_traffic := 0
	for vehicle in get_nodes_in_group("modern_traffic"):
		if vehicle.get("_pending_spec") == null: continue
		if preload("res://cars/VehicleGeometryCache.gd").is_startup_relevant(vehicle):
			assert(vehicle._pending_spec.is_empty())
		elif not vehicle._pending_spec.is_empty():
			deferred_traffic += 1
	result["deferred_traffic_after_loading"] = deferred_traffic
	var player = current_scene.get_node("Player")
	var car = current_scene.get_node("PlayerCar")
	player.global_position = Vector2(2200,1050)
	car.global_position = Vector2(700,425)
	car.rotation = 0.0
	current_scene._drive()
	Input.action_press("move_up")
	var frames: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-previous)/1000.0)
		previous = now
	Input.action_release("move_up")
	var ordered = frames.duplicate()
	ordered.sort()
	var total := (Time.get_ticks_usec()-start)/1000000.0
	result["gameplay"] = {"seconds":total,"frames":frames.size(),"fps":frames.size()/total,"p50":ordered[int(ordered.size()*0.5)],"p95":ordered[int(ordered.size()*0.95)],"p99":ordered[int(ordered.size()*0.99)],"max":ordered[-1],"over33":frames.filter(func(x): return x>33.3).size(),"over66":frames.filter(func(x): return x>66.7).size()}
	result["frames_ms"] = frames
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("LOADING_GAMEPLAY ",JSON.stringify(result.gameplay))
	quit(0)
