extends "res://tests/measure/measure_desert.gd"
## Rode em sequência com --benchmark --no-save, uma vez com --baseline e uma
## sem. Mesmo código/build/checkpoint/semente/câmera; isto isola o custo do conteúdo
## do evento ao vivo e NÃO é comparação com o código de antes da implementação.
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
const RANDOM_SEED := 7102026
const OBSERVER := Vector3(37.625,.12,18.875)
const CAMERA_FOCUS := Vector3(42.0,0.0,12.0)
var baseline := false
var timeline: Array[Dictionary] = []
var warmup: Dictionary = {}
var failures: Array[String] = []
var checkpoint_path := ""
var _sample_started := 0
var _next_snapshot := 0
var _collect_scene := false

func _initialize() -> void:
	create_timer(320).timeout.connect(func():
		failures.append("bounded rendered Main timeout")
		_write_report(false)
		quit(3))
	run.call_deferred()

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if _collect_scene and Time.get_ticks_msec() >= _next_snapshot:
		_next_snapshot = Time.get_ticks_msec()+1000
		var row := _scene_snapshot()
		row["seconds"] = float(Time.get_ticks_msec()-_sample_started)/1000.0
		timeline.append(row)
	return result

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--benchmark" not in args or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET requires --benchmark --no-save; no headless/FPS fallback")
		quit(2)
		return
	baseline = "--baseline" in args
	seed(RANDOM_SEED)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("armored-measure-"+("inactive" if baseline else "active"))
	fingerprint = source_fingerprint()
	for filename in DirAccess.get_files_at("res://gameplay/armored"):
		if filename.ends_with(".gd"):
			var path: String = "res://gameplay/armored/"+filename
			fingerprint[path] = FileAccess.get_sha256(path)
	for path in ["res://tests/measure/measure_armored_transport.gd","res://runtime/FleetCatalog.gd","res://data/catalogs/VehicleDoorSpecs.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path)
	for path in ["res://evidence/auditoria-viaria/2026-10-08-banco-transporte/ArmoredTransportBefore.gd","res://evidence/auditoria-viaria/2026-10-08-banco-transporte/ArmoredGuardBefore.gd"]:
		if FileAccess.file_exists(path): fingerprint[path] = FileAccess.get_sha256(path)
	var snapshot := FIXTURE.full_snapshot(OBSERVER,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "harbor"
	snapshot.world.pedestrian = {"region":"harbor","position":[OBSERVER.x,OBSERVER.y,OBSERVER.z]}
	snapshot.world.moon_day = 1
	snapshot.world.time = 9.0/24.0
	snapshot.world.weather = 0
	var event := SCHEDULE.departure(1,9.0/24.0)
	var dormant := SCHEDULE.initial(event,0)
	dormant.phase = "finished"
	snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":event.id,"security_level":0,"event":dormant}
	checkpoint_path = FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if checkpoint_path.is_empty(): _fail("isolated checkpoint invalid"); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",checkpoint_path)
	root.add_child(world)
	current_scene = world
	for frame in 7000:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled or world.production.store.path != checkpoint_path or world.production.save_invalid:
		_fail("Main startup/save isolation failed"); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: _fail("compiled C# router unavailable"); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(OBSERVER)
	for frame in 3: await physics_frame
	if not world.session.position_clear(OBSERVER): _fail("bank observer lacks a clear supported foothold"); return
	world.player.teleport(OBSERVER)
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = 9.0/24.0
	world.session.weather._update()
	# Uma lente de observador fixa cobre a formação inteira do banco nas duas invocações.
	# Cena, streaming, trânsito, guardas, física e combate reais continuam ligados.
	world.camera.set_process(false)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 65.0
	world.camera.global_position = CAMERA_FOCUS+Vector3(0,35,35)
	world.camera.look_at(CAMERA_FOCUS)
	world.camera.current = true
	if "--normal-limit" not in args:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(10).timeout
	var convoy = world.session.armored_transport
	if not convoy.fleet.is_empty(): _fail("dormant checkpoint unexpectedly spawned fleet"); return
	if "--before-parking" in args:
		# Código arquivado e não editado de transporte/guarda no Main atual idêntico.
		# A fixture dormente não tem frota nem equipe para realocar durante a substituição.
		convoy.queue_free()
		await physics_frame
		convoy = load("res://evidence/auditoria-viaria/2026-10-08-banco-transporte/ArmoredTransportBefore.gd").new()
		convoy.configure(world.session)
		world.session.armored_transport = convoy
		world.add_child(convoy)
	seed(RANDOM_SEED)
	samples.clear(); cpu.clear(); physics.clear()
	previous = Time.get_ticks_usec()
	sampling = true
	if not baseline:
		convoy.data = SCHEDULE.initial(event,0)
		convoy.profile = SCHEDULE.security(0)
		convoy.security_level = 0
		convoy.road = null
		convoy._route_retry = 0.0
		convoy._persist()
	await create_timer(10).timeout
	sampling = false
	warmup = {"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),"scene":_scene_snapshot(),"note":"First 10 seconds of event activation/admission/shader and streaming warmup, recorded separately from steady state."}
	if not baseline and convoy.fleet.size() != 4: _fail("active event did not admit four real vehicles during warmup"); return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("bank-start.png"))
	samples.clear(); cpu.clear(); physics.clear()
	previous = Time.get_ticks_usec()
	_sample_started = Time.get_ticks_msec()
	_next_snapshot = _sample_started
	_collect_scene = true
	sampling = true
	await create_timer(30).timeout
	sampling = false
	_collect_scene = false
	var final_scene := _scene_snapshot()
	reports.append({"id":"bank-inactive" if baseline else "bank-active","summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),"timeline":timeline,"final_scene":final_scene})
	for row in timeline:
		if baseline and row.fleet != 0: failures.append("baseline fleet spawned"); break
		if not baseline and (row.fleet != 4 or row.visible_fleet != 4 or row.hostile):
			failures.append("active fleet missing/off-screen/hostile during steady sample"); break
		if not baseline and row.phase not in ["loading","boarding"]:
			failures.append("active service left loading/boarding scenario during sample"); break
		if not baseline and row.phase == "loading" and row.guards != int(convoy.profile.crew_count):
			failures.append("active loading sample lacks its complete living crew"); break
	if stats(samples).get("seconds",0.0) < 29.9: failures.append("steady sample shorter than 30 seconds")
	if fingerprint != source_fingerprint(fingerprint): failures.append("source changed during measurement")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("bank-end.png"))
	_write_report(failures.is_empty())
	print("ARMORED_MEASURE ",output," ",JSON.stringify(reports[-1].summary)," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _scene_snapshot() -> Dictionary:
	var convoy = world.session.armored_transport
	var visible_fleet := 0
	var living_guards := 0
	var vehicles: Array[Dictionary] = []
	for car in convoy.fleet:
		if not is_instance_valid(car): continue
		if world.production._on_screen(car.global_position,3.0): visible_fleet += 1
		vehicles.append({"id":car.vehicle_id,"position":str(car.global_position),"speed":car.speed,"health":car.health})
	for guard in convoy.guards:
		if is_instance_valid(guard) and not guard.dead: living_guards += 1
	return {"phase":convoy.data.get("phase",""),"elapsed":convoy.data.get("elapsed",0),"fleet":convoy.fleet.size(),"visible_fleet":visible_fleet,"guards":living_guards,"hostile":convoy.data.get("hostile",false),"people":world.people.size(),"vehicles_total":world.production.vehicles.size(),"vehicle_records":vehicles,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"hour":world.session.weather.time_of_day,"player_position":str(world.player.global_position),"stars":world.gameplay.stars}

func _write_report(valid: bool) -> void:
	if output.is_empty(): return
	var report := {"valid":valid,"failures":failures,"baseline":baseline,"seed":RANDOM_SEED,"checkpoint":checkpoint_path,"checkpoint_sha256":FileAccess.get_sha256(checkpoint_path) if FileAccess.file_exists(checkpoint_path) else "MISSING","source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint),"warmup":warmup,"scenarios":reports,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"viewport":str(root.get_visible_rect().size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"user_args":OS.get_cmdline_user_args(),"notes":"Sequential same-code content comparison: dormant service versus live tier-0 bank loading/boarding. NOT original-source before/after baseline. Real Main/.NET, fixed bank observer camera, 10s world warmup then 10s event warmup and 30s steady wall-clock samples. Source/checkpoint hashes and actual population counts must match or be reviewed across runs. Default uncapped/VSync off; --normal-limit preserves project/user limits for both runs. Goal60FPS/16.67ms, >5% p95/p99 increase requires finite confirmation. CPU monitor values are coarse engine process/physics timing; frame intervals do not isolate GPU cost. Does not certify night lighting, chase, explosions, desert or road performance."}
	if is_instance_valid(world):
		report["service_variant"] = "archived-street-service" if "--before-parking" in OS.get_cmdline_user_args() else "current-apron-service"
		if not baseline: report["notes"] = "Active service before/after: --before-parking loads archived original transport and guard source into the dormant Main fixture; otherwise uses current apron service. Same isolated .NET Main, seed, fixed camera, population configuration and 10s+10s warmup / 30s steady sample. 60 FPS / 16.67 ms provisional target; >5% p95/p99 regression requires confirmation. This measures loading only, not driving, combat, night lighting or other regions. Check external GPU processes separately."
		report["requested_population"] = world.production.requested_population
		report["camera"] = {"transform":str(world.camera.global_transform),"size":world.camera.size,"projection":world.camera.projection}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func _fail(reason: String) -> void:
	failures.append(reason)
	push_error(reason)
	_write_report(false)
	quit(1)
