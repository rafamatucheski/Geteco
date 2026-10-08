extends "res://tests/measure/measure_desert.gd"
## Matched Main/.NET control: ordinary Umbra entry and first-person interior.
const PARK := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
var phase_label := "before"
var arrivals: Array[Dictionary] = []
var normal_limits := false

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("UPSIDE_MEASURE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with isolated fixture required"); quit(2); return
	for arg in args:
		if arg.begins_with("--phase="): phase_label = arg.trim_prefix("--phase=")
	normal_limits = "--normal-limits" in args
	Engine.set_meta("upside_world_baseline",phase_label == "before")
	seed(7102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("upside-control-"+phase_label)
	fingerprint = source_fingerprint()
	for path in ["res://runtime/amusement_park/AmusementParkRuntime.gd","res://gameplay/wine/WineRuntime.gd","res://gameplay/wine/WineState.gd","res://world/places/amusement_park/HauntedHousePlace.gd","res://world/places/amusement_park/HauntedHouseInterior.gd","res://world/places/PlaceCatalog.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path)
	for path in ["res://runtime/upside_world/UpsideWorldRuntime.gd","res://runtime/upside_world/UpsideWorldState.gd","res://runtime/upside_world/UpsideVeil.gd","res://runtime/upside_world/UpsideReturnPoints.gd","res://world/places/upside_world/UpsideWorld.gd","res://world/places/upside_world/UpsideGeometry.gd","res://world/places/upside_world/Apparition.gd","res://ui/AndroidControls.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path)
	var snapshot := FIXTURE.full_snapshot(PARK.HAUNTED_ENTRY+Vector3(0,.08,1.3),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.world.time = .90
	snapshot.world.weather = 0
	var path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or world.production.store.path != path or world.production.save_invalid:
		push_error("Main startup or isolated save failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("Compiled route backend required"); quit(1); return
	if world.session.modal: world.session.close_menu()
	if not normal_limits:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .90
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	await warm("exterior")
	await measure("exterior")
	if not await world.session.enter_place(PARK.HAUNTED_ID,false):
		push_error("Umbra admission failed"); quit(1); return
	await warm("house")
	await measure("house")
	var finish := source_fingerprint(fingerprint)
	var report := {"phase":phase_label,"source_stable":fingerprint==finish,"source_before":fingerprint,"source_after":finish,
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,
		"vsync":DisplayServer.window_get_vsync_mode(),"msaa":root.msaa_3d,"native":world.dispatch.router._native!=null,
		"scenarios":reports,"arrivals":arrivals,"notes":"Real Main/C# with live population; sober night/dry Umbra control,10s warmup and30s per scenario. No capture readback during samples. Compare same control before/after; hallucination needs separate real cycles. Target60FPS/16.67ms; >5% p95/p99 requests finite confirmation. CPU/GPU attribution not available."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("UPSIDE_CONTROL ",output," ",JSON.stringify(reports.map(func(item): return {"id":item.id,"summary":item.summary}))," stable=",report.source_stable)
	quit(0 if report.source_stable else 1)

func warm(id: String) -> void:
	samples.clear(); cpu.clear(); physics.clear()
	previous=Time.get_ticks_usec(); sampling=true
	await create_timer(10).timeout
	sampling=false
	arrivals.append({"id":id,"summary":stats(samples),"intervals_ms":samples.duplicate()})
