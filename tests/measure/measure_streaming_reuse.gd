extends SceneTree
## Cena produtiva renderizada, primeira visita/retorno e câmera ampla; sem tocar saves pessoais.
var world: Node3D
var out := "res://artifacts/streaming-reuse-20261021/before-harbor"
var started := 0
var overview := false
var settings_hash := ""

func _stream_state() -> Dictionary:
	var region: Node=world.production.region
	return {"chunks":region.chunks.size(),"pending":region.pending.size(),"jobs":region.build_jobs.size(),
		"surface_jobs":region.get("_surface_jobs").size() if region.get("_surface_jobs") is Dictionary else 0,
		"drag_pending":region.get("drag_view_pending").size() if region.get("drag_view_pending") is Array else 0,
		"idle":region.is_streaming_idle(),"startup_settled":world.production.startup_streaming_settled}

func _initialize() -> void:
	run.call_deferred()

func _stats(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	return {"frames": values.size(), "duration_ms": total, "fps": values.size()*1000.0/total,
		"p50_ms": sorted[int((sorted.size()-1)*.5)], "p95_ms": sorted[int((sorted.size()-1)*.95)],
		"p99_ms": sorted[int((sorted.size()-1)*.99)], "max_ms": sorted[-1],
		"over33": over33, "over66": over66, "raw_ms": values}

func _sample(label: String, points: Array, seconds: float, transition_began := 0) -> void:
	var frames: Array[float] = []
	var previous := transition_began if transition_began>0 else Time.get_ticks_usec()
	var phase_started := previous
	var stream_before := _stream_state()
	var elapsed := 0.0
	while elapsed < seconds:
		if not points.is_empty():
			var progress := elapsed/seconds*(points.size()-1)
			var index := mini(int(progress),points.size()-2)
			world.player.global_position = (points[index] as Vector3).lerp(points[index+1],progress-index)+Vector3.UP*.2
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		previous = now
		elapsed = float(now-phase_started)/1000000.0
	var report := _stats(frames)
	report.region = world.session.state.region_id
	report.people = world.people.size()
	report.vehicles = world.production.vehicles.size()
	report.chunks = world.production.region.chunks.size()
	report.pending = world.production.region.pending.size()
	report.jobs = world.production.region.build_jobs.size()
	report.memory_bytes = OS.get_static_memory_usage()
	report.streaming_before=stream_before
	report.streaming_after=_stream_state()
	report.overview_full_map=overview
	report.position=str(world.player.global_position)
	report.camera_size=world.camera.size
	report.resolution=str(root.size)
	report.vsync=DisplayServer.window_get_vsync_mode()
	report.max_fps=Engine.max_fps
	if world.production.region.has_method("streaming_reuse_diagnostics"):
		report.reuse=world.production.region.streaming_reuse_diagnostics()
	if "_warm_tunnel_chunks" in world.production.region:
		report.warm_tunnel_chunks=world.production.region._warm_tunnel_chunks.size()
		var route_ids := {}
		for key: String in world.production.region._record_cache:
			if not key.contains("harbor_route_zone"): continue
			var ids: Array=[]
			for node in world.production.region._record_cache[key]:
				if is_instance_valid(node): ids.append(node.get_instance_id())
			route_ids[key]=ids
		report.route_cache_root_ids=route_ids
	FileAccess.open(out.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("raw_ms")
	print("STREAM_REUSE ",label," ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label+".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	create_timer(420,true).timeout.connect(func(): push_error("STREAM_REUSE_TIMEOUT"); quit(3))
	seed(20261021)
	var settings_path: String=preload("res://runtime/Settings.gd").default_path()
	if FileAccess.file_exists(settings_path): settings_hash=FileAccess.get_sha256(settings_path)
	started=Time.get_ticks_usec()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	while world.session == null or not world.session.ready_for_play: await process_frame
	var load_ms := float(Time.get_ticks_usec()-started)/1000.0
	var normal_mode := DisplayServer.window_get_mode()
	var normal_size := DisplayServer.window_get_size()
	var normal_vsync := DisplayServer.window_get_vsync_mode()
	var normal_max_fps := Engine.max_fps
	var startup_stream := _stream_state()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_position(Vector2i(40,40))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=144
	world.player.set_physics_process(false)
	world.player.input_locked=true
	var weather: Variant=world.session.weather
	weather.time_of_day=.5
	weather.weather_timer=1.0e9
	var config := {"load_ms":load_ms,"driver":RenderingServer.get_current_rendering_driver_name(),
		"resolution":str(root.size),"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,
		"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),
		"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,
		"settings_sha256":settings_hash,"launch_args":OS.get_cmdline_user_args(),"origin":str(world.player.global_position),
		"normal_mode":normal_mode,"normal_size":str(normal_size),"normal_vsync":normal_vsync,"normal_max_fps":normal_max_fps,
		"startup_stream":startup_stream,
		"native_routes_active":world.dispatch.router.get("_native")!=null,
		"detailed_session_log":OS.get_environment("HARBOR_SESSION_PROFILE"),"physics_max_steps":Engine.max_physics_steps_per_frame,
		"target_ms":16.67,"regression_confirmation_percent":5,"scope":"production world; scripted traversal, active population; no gameplay acceptance"}
	FileAccess.open(out.path_join("config.json"),FileAccess.WRITE).store_string(JSON.stringify(config))
	print("STREAM_REUSE_READY ",JSON.stringify(config))
	var origin: Vector3=world.player.position
	var points: Array
	if world.session.state.region_id == "harbor":
		points=[Vector3(106,0,71),Vector3(67,0,132),Vector3(390,0,132),Vector3(106,0,71)]
	# Stay inside the desert and outside the race camera's retained band, so
	# the return can exercise ordinary cell retirement/reuse rather than void.
	else: points=[origin,origin+Vector3(-288,0,0),origin]
	await _sample("01-first-route",points,35)
	await _sample("02-return-route",points,35)
	var tools=world.pause_panel.developer_panel.tools
	var transition_began := Time.get_ticks_usec()
	tools.set_active(true)
	tools.set_camera_zoom(25,1)
	overview=true
	print("STREAM_REUSE_OVERVIEW_ACTIVATION_MS ",float(Time.get_ticks_usec()-transition_began)/1000.0)
	await _sample("03-wide-first",[],30,transition_began)
	await _sample("04-wide-next",[],30)
	transition_began=Time.get_ticks_usec()
	tools.reset_camera_zoom()
	tools.set_active(false)
	overview=false
	await _sample("05-recovery",[],30,transition_began)
	# Recheck the saved display configuration in this process, without saving it.
	DisplayServer.window_set_mode(normal_mode)
	if normal_mode==DisplayServer.WINDOW_MODE_WINDOWED: DisplayServer.window_set_size(normal_size)
	DisplayServer.window_set_vsync_mode(normal_vsync)
	Engine.max_fps=normal_max_fps
	await _sample("06-normal-display",[],30)
	print("STREAM_REUSE_DONE ",out)
	world.queue_free()
	await process_frame
	quit()
