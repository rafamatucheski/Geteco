extends "res://tests/measure/measure_desert.gd"
## Cena do Main, população viva normal e roteamento C# compilado. Rode um processo
## por vez; a fase de antes de propósito não precisa de scripts do Curitiba Cellar.
const CELLAR_ID := "harbor_curitiba_cellar"
const STREET_POINT := Vector3(136.5, .20, 18.3)
var phase := "after"
var selection := "all"
var arrivals: Array[Dictionary] = []
var normal_limits := false
var initial_max_fps := 0
var initial_vsync: DisplayServer.VSyncMode = DisplayServer.VSYNC_DISABLED

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): push_error("CELLAR_MEASURE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET and isolated --no-save required"); quit(2); return
	for arg in args:
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--scenario="): selection = arg.trim_prefix("--scenario=")
		normal_limits = normal_limits or arg == "--normal-limits"
	Engine.set_meta("curitiba_cellar_baseline", phase == "before")
	if selection not in ["all", "exterior", "interior", "drunk", "confirm"] or phase not in ["before", "after"] or (phase == "before" and selection != "exterior"):
		push_error("Use --phase=before --scenario=exterior or --phase=after --scenario=all|exterior|interior|drunk|confirm"); quit(2); return
	seed(7102026)
	root.size = Vector2i(1280, 720)
	output = FIXTURE.output_dir("curitiba-cellar-" + phase + "-" + selection)
	fingerprint = source_fingerprint()
	if phase != "before":
		for directory in ["res://world/places/curitiba_cellar", "res://runtime/curitiba_cellar", "res://gameplay/wine"]:
			_fingerprint_directory(directory)
	for path in ["res://scripts/Actor.gd", "res://scripts/CameraRig.gd", "res://gameplay/Gameplay.gd", "res://world/places/PlaceCatalog.gd", "res://runtime/CuritibaCellar.gd", "res://world/places/curitiba_cellar/CuritibaCellarPlace.gd", "res://tests/measure/measure_curitiba_cellar.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	var snapshot := FIXTURE.full_snapshot(STREET_POINT, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.world.time = .45
	snapshot.world.weather = 0
	var save_path := FIXTURE.write_fixture(output, "checkpoint.json", snapshot)
	if save_path.is_empty(): quit(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or world.production.store.path != save_path or world.production.save_invalid:
		push_error("Main native startup/save isolation failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null:
		push_error("Compiled C# routing backend unavailable"); quit(1); return
	if world.session.modal: world.session.close_menu()
	initial_max_fps=Engine.max_fps
	initial_vsync=DisplayServer.window_get_vsync_mode()
	if not normal_limits:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	world.production.region.set_focus(STREET_POINT)
	world.production.region.prepare_collision_at(STREET_POINT)
	world.player.teleport(STREET_POINT)
	world.camera.initialized = false
	await _warmup("exterior")
	if selection in ["all", "exterior"]: await _measure_cellar("exterior")
	if selection in ["all", "interior", "drunk"]:
		if not await world.session.enter_place(CELLAR_ID, false):
			push_error("Curitiba Cellar admission failed"); quit(1); return
		await _warmup("interior")
		if selection in ["all", "interior"]: await _measure_cellar("interior")
		if selection in ["all", "drunk"]:
			if not await _prepare_drunk(): quit(1); return
			if world.session.modal: world.session.close_menu()
			if not await world.session.leave_place():
				push_error("Cellar exterior return failed"); quit(1); return
			world.player.teleport(STREET_POINT)
			await _warmup("drunk")
			await _measure_cellar("drunk")
	if selection == "confirm" and not await _confirm_sequence():
		quit(1); return
	var finish := source_fingerprint(fingerprint)
	var stable := fingerprint == finish
	var report := {
		"phase":phase, "selection":selection, "source_stable":stable,
		"source_sha256_start":fingerprint, "source_sha256_end":finish,
		"engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(),
		"cpu":OS.get_processor_name(), "renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(),
		"max_fps":Engine.max_fps, "msaa":root.msaa_3d, "normal_limits":normal_limits,
		"initial_limits":{"max_fps":initial_max_fps,"vsync":initial_vsync},
		"mixed_limits":selection=="confirm",
		"native":world.dispatch.router._native != null, "isolated_save":save_path,
		"population":world.production.requested_population, "scenarios":reports, "arrivals":arrivals,
		"notes":"Main gameplay with live population. 10s warmup plus 30s steady samples; relocation and direct admission are diagnostic setup, not route coverage. Exterior has a true preimplementation baseline. Confirm samples interior, four actual drinks and exterior return, then adjacent recovered and normal-limits samples at exactly the same point. Traffic and population stay live and may vary with elapsed time; use context_start/context_end rather than attributing their cost to wine. Mixed limits are recorded per sample. CPU/physics monitors do not isolate GPU cost. Goal60FPS/16.67ms; >5% p95/p99 increase requests one finite confirmation. Readbacks occur after sampling."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CELLAR_MEASURE ", output, " source_stable=", stable)
	quit(0 if stable else 1)

func _warmup(id: String) -> void:
	samples.clear(); cpu.clear(); physics.clear()
	previous = Time.get_ticks_usec()
	sampling = true
	await create_timer(10).timeout
	sampling = false
	arrivals.append({"id":id, "summary":stats(samples), "intervals_ms":samples.duplicate()})

func _measure_cellar(id: String) -> void:
	var start_context:=_case_context()
	await measure(id)
	reports[-1]["context_start"]=start_context
	reports[-1]["context_end"]=_case_context()
	reports[-1]["player_position"] = str(world.player.global_position)
	reports[-1]["place_id"] = world.session.state.place_id
	reports[-1]["camera_transform"] = str(world.camera.global_transform)
	if world.session.get("wine") != null:
		reports[-1]["wine"] = world.session.wine.snapshot()
	print("CELLAR_CASE ", id, " ", JSON.stringify(reports[-1].summary))

func _confirm_sequence() -> bool:
	# Mantém a última edição do interior na mesma verificação renderizada finita.
	if not await world.session.enter_place(CELLAR_ID,false):
		push_error("Confirmation interior admission failed"); return false
	await _warmup("confirm-interior")
	await _measure_cellar("confirm-interior")
	if not await _prepare_drunk(): return false
	if world.session.modal: world.session.close_menu()
	if not await world.session.leave_place():
		push_error("Confirmation exterior return failed"); return false
	world.player.teleport(STREET_POINT)
	await _warmup("confirm-drunk")
	await _measure_cellar("confirm-drunk")
	# Nenhuma entrada nova, teleporte, reinício de população ou mudança de câmera neste par.
	# A única variável explícita é a recuperação; a simulação viva decorrida é registrada.
	world.session.wine.recover()
	await _warmup("confirm-recovered")
	await _measure_cellar("confirm-recovered")
	Engine.max_fps=initial_max_fps
	DisplayServer.window_set_vsync_mode(initial_vsync)
	await _warmup("confirm-recovered-normal")
	await _measure_cellar("confirm-recovered-normal")
	return true

func _case_context() -> Dictionary:
	var position: Vector3=world.player.global_position
	var context:={
		"ticks_usec":Time.get_ticks_usec(),
		"people":world.people.size(),
		"vehicles":world.production.vehicles.size(),
		"requested_population":world.production.requested_population,
		"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"max_fps":Engine.max_fps,
		"vsync":DisplayServer.window_get_vsync_mode(),
		"player_position":[position.x,position.y,position.z],
		"camera_size":world.camera.size,
		"camera_heading":world.camera.heading,
		"hour":world.session.weather.time_of_day,
		"place_id":world.session.state.place_id,
	}
	if world.session.get("wine") != null:
		context["wine_intensity"]=world.session.wine.get_intensity()
		context["wine_overlay_visible"]=world.session.wine.overlay.visible
	return context

func _prepare_drunk() -> bool:
	var wine: Variant = world.session.get("wine")
	if wine == null:
		push_error("Wine runtime unavailable; drunk scenario not measured")
		return false
	# Inventory is fixture setup; consumption/healing/presentation run through
	# the real runtime, including its normal sip cooldown.
	world.player.teleport(world.session.room.interaction_points.service + Vector3.UP * .04)
	world.session.state.economy.grant_reward("cellar_benchmark_funds", 2000)
	if not wine.buy("zacharias_malagousia") or not wine.buy("zacharias_malagousia"): return false
	for glass in 4:
		if not wine.drink("zacharias_malagousia"): return false
		if glass < 3: await create_timer(2.7).timeout
	return wine.get_intensity() > .8

func _fingerprint_directory(directory: String) -> void:
	if not DirAccess.dir_exists_absolute(directory): return
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
			var path := directory.path_join(filename)
			fingerprint[path] = FileAccess.get_sha256(path)
	for child in DirAccess.get_directories_at(directory): _fingerprint_directory(directory.path_join(child))
