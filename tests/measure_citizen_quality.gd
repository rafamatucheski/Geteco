extends SceneTree
var _profile_views: Array[Viewport] = []
var _profile_last_ms := 0
var _scenario_world: Node
var _scenario_hour := 0.45
## Rendered, finite production checkpoint diagnostic. Each invocation uses a
## fresh scene and redirects gameplay saves to its evidence directory.
## User args: out_dir=<absolute directory> --normal-cap --night

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Frame stability requires a real renderer")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	# A/B the character change against the same current world without touching
	# source files or user saves. This process exits after its finite sample.
	if args.has("--baseline-rig"):
		for path in ["world/shared/pedestrians/CitizenGait.gd","world/shared/pedestrians/CitizenDetails.gd","AnimatedPedestrian3D.gd"]:
			var script: GDScript = load("res://"+path)
			script.source_code=FileAccess.get_file_as_string("D:/geteco/artifacts/citizens-quality-0914/before-source/"+path)
			if script.reload(true)!=OK:
				push_error("Could not load baseline rig: "+path)
				quit(1)
				return
	var output := "D:/geteco/artifacts/station-npcs-review/measurement"
	for arg in args:
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(12092026)
	root.size = Vector2i(1280, 720)
	for arg in args:
		if arg.begins_with("resolution="):
			var dimensions := arg.trim_prefix("resolution=").split("x")
			if dimensions.size() == 2:
				root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	# Keep identical world coverage while changing the native pixel workload.
	root.content_scale_size = Vector2i(1280, 720)
	if not args.has("--normal-cap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		push_error("Frame stability checkpoint unavailable")
		quit(1)
		return
	# Match the normal loading screen's geometry preparation.
	paused = true
	await preload("res://VehicleGeometryCache.gd").prepare_common_models(self)
	if not args.has("--skip-resident-preparation"):
		await preload("res://VehicleGeometryCache.gd").prepare_resident_presentations(self)
	await root.get_node("EmergencyPool").prepare_presentations()
	await preload("res://audio/VehicleEngineSound.gd").prepare_catalog(self)
	paused = false
	_scenario_world = world
	_scenario_hour = 0.90 if args.has("--night") else 0.45
	world.weather.is_dynamic_time = true
	_hold_scenario_clock()
	world.weather.set_biome(world.weather.current_biome)
	world.weather.set_weather(1 if args.has("--rain") else 0)
	world.weather.weather_timer = 1000000.0
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(700, 475)
	player.reset_physics_interpolation()
	await _sample(output, "warmup", 10.0, player)
	await _sample(output, "street", 30.0, player)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("street.png"))
	quit(0)

func _hold_scenario_clock() -> void:
	if not is_instance_valid(_scenario_world): return
	var bridge := _scenario_world.get_node_or_null("CobraCampaign")
	if bridge != null and bridge.ledger != null:
		bridge.ledger.data.day_elapsed = fposmod(_scenario_hour - 0.35, 1.0) * preload("res://world/harbor/campaign/CobraCampaignState.gd").DAY_SECONDS
	_scenario_world.weather.time_of_day = _scenario_hour

func _collect_profile_views(node: Node) -> void:
	# Per-viewport GPU timestamp instrumentation can itself stall the driver
	# with hundreds of cached SubViewports. Opt into that only for diagnosis;
	# normal frame certification runs without --profile-render altogether.
	if node is Viewport and (node == root or OS.get_cmdline_user_args().has("--profile-all-views")):
		_profile_views.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)
	for child in node.get_children(): _collect_profile_views(child)

func _report_render() -> void:
	if _profile_views.is_empty() or Time.get_ticks_msec() - _profile_last_ms < 1000: return
	_profile_last_ms = Time.get_ticks_msec()
	var rows: Array[Dictionary] = []
	for view in _profile_views:
		if not is_instance_valid(view): continue
		if view is SubViewport and view.render_target_update_mode == SubViewport.UPDATE_DISABLED: continue
		var rid := view.get_viewport_rid()
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if cpu > 0.1 or gpu > 0.1: rows.append({"path":str(view.get_path()),"cpu_ms":cpu,"gpu_ms":gpu})
	rows.sort_custom(func(a,b): return a.cpu_ms + a.gpu_ms > b.cpu_ms + b.gpu_ms)
	print("RENDER_BREAKDOWN ", JSON.stringify(rows.slice(0,12)))

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	var file := FileAccess.open(output.path_join(label + ".csv"), FileAccess.WRITE)
	file.store_line("frame_ms,process_ms,physics_ms,draw_calls,x,y,police")
	var samples: Array[float] = []
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	var police_peak := 0
	var hour_min := INF
	var hour_max := -INF
	var weather_states: Array[int] = []
	var previous_frame := Time.get_ticks_usec()
	while total < seconds * 1000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - previous_frame) / 1000.0
		previous_frame = now
		if is_instance_valid(_scenario_world):
			var hour: float = _scenario_world.weather.time_of_day
			hour_min = minf(hour_min, hour)
			hour_max = maxf(hour_max, hour)
			var weather_state: int = _scenario_world.weather.weather_state
			if not weather_states.has(weather_state): weather_states.append(weather_state)
		_hold_scenario_clock()
		_report_render()
		total += ms
		samples.append(ms)
		if ms > 33.3: over_33 += 1
		if ms > 66.7: over_66 += 1
		var police := 0
		for vehicle in get_nodes_in_group("emergency_vehicle"):
			if is_instance_valid(vehicle) and vehicle.visible and int(vehicle.get("type")) == 0: police += 1
		police_peak = maxi(police_peak, police)
		file.store_line("%f,%f,%f,%d,%f,%f,%d" % [ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), car.global_position.x, car.global_position.y, police])
	file.close()
	samples.sort()
	var report := {"scenario": label, "seconds": total / 1000.0, "frames": samples.size(), "fps": samples.size() * 1000.0 / total, "p50_ms": samples[int(samples.size() * .5)], "p95_ms": samples[int(samples.size() * .95)], "p99_ms": samples[int(samples.size() * .99)], "max_ms": samples[-1], "over_33ms": over_33, "over_66ms": over_66, "police_peak": police_peak, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "engine": Engine.get_version_info(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "args": OS.get_cmdline_user_args()}
	var summary := FileAccess.open(output.path_join(label + ".json"), FileAccess.WRITE)
	report["time_of_day_min"] = hour_min
	report["debug_build"] = OS.is_debug_build()
	report["executable"] = OS.get_executable_path()
	report["time_of_day_max"] = hour_max
	report["weather_states"] = weather_states
	if is_instance_valid(_scenario_world): report["is_dark"] = _scenario_world.weather.is_dark
	if is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null: report["streaming"] = stream.get_streaming_stats()
	summary.store_string(JSON.stringify(report, "\t"))
	summary.close()
	print("FRAME_STABILITY ", JSON.stringify(report))
