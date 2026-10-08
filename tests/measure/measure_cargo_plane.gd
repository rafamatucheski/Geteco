extends "res://tests/measure/measure.gd"
## Main real, .NET, checkpoint exclusivo e caminhada rampa/carga por 30 s.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const PLANE_PATH := "res://world/places/CargoPlaneNative.gd"
var folder := ""
var variant := "before"
var sources := {}
var plane: Node3D
var sample_age := 0.0

func fingerprints() -> Dictionary:
	var result := {}
	for path in [PLANE_PATH,"world/places/CargoPlaneSightline.gd","assets/regions/source/world/mountain_pass/art/review_0908/CrashedCargoPlane3D.gd","assets/regions/source/world/mountain_pass/art/review_0908/CargoPlaneAirframe.gd","systems/inventory/PickupPresentation.gd","scripts/CameraRig.gd","world/regions/NativeRegion.gd","runtime/FullSession.gd","runtime/ProductionWorld.gd","project.godot",".godot/mono/temp/bin/Debug/Harbor.dll"]:
		var resource_path: String = path if str(path).begins_with("res://") else "res://"+str(path)
		result[path] = FileAccess.get_sha256(resource_path)
	return result

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires rendered Godot .NET --no-save"); quit(2); return
	for arg in args:
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=")
	folder="res://evidence/cargo-plane-%s-%d" % [variant,OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var center := CATALOG._at(Vector2(5450,-1150),"mountain")
	var spawn := center+Vector3(0,.08,10.5)
	var state = preload("res://runtime/GameState.gd").new()
	var intro: Dictionary=state.intro.snapshot()
	intro.phase="complete"; intro.location_id="harbor_street"; intro.inventory={}
	intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): quit(2); return
	state.set_location("mountain")
	state.world_state.time=.45; state.world_state.weather=0
	state.world_state.pedestrian={"region":"mountain","position":[spawn.x,spawn.y,spawn.z]}
	var store=preload("res://runtime/SaveStore.gd").new()
	store.path=folder.path_join("fixture.json")
	if store.save(state)!=OK: quit(2); return
	seed(610207)
	sources=fingerprints()
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",store.path)
	root.add_child(world); current_scene=world
	var setup_start := Time.get_ticks_msec()
	while Time.get_ticks_msec()-setup_start<120000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.loaded_save:
		push_error("Cargo plane fixture did not load"); quit(3); return
	world.dispatch.router.nearest_edge(spawn)
	if world.dispatch.router._native==null:
		push_error("C# router missing"); quit(3); return
	for source in get_nodes_in_group("native_world_rewards"):
		if source.get_script().resource_path==PLANE_PATH: plane=source; break
	if plane==null: push_error("Plane not streamed"); quit(3); return
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0; world.session.weather.weather_timer=3600
	world.session.weather._update()
	world.diagnostic_label.hide()
	world.camera.heading=0; world.camera.initialized=false
	world.player.teleport(spawn)
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.player.speed=2
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	for i in 120: await physics_frame
	await photograph("approach")
	# Photographic setups are excluded from frame-time sampling.
	world.player.teleport(center+Vector3(.2,.25,-5.8))
	for entry in [[0.0,"rear"],[PI*.5,"starboard"],[-PI*.5,"port"],[PI,"cockpit"]]:
		world.camera.heading=entry[0]; world.camera.initialized=false
		for i in 45: await physics_frame
		await photograph(entry[1])
	world.camera.heading=0; world.camera.initialized=false
	world.player.teleport(spawn)
	route=PackedVector3Array([center+Vector3(.2,0,-5.8),center+Vector3(.2,0,10.5)])
	waypoint=0
	started=Time.get_ticks_usec(); previous=started
	print("CARGO_PLANE_READY ",folder)

func photograph(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func _process(delta: float) -> bool:
	if started>0:
		sample_age+=delta
		# Same orbit in both versions; exercises both side sightlines.
		world.camera.heading=PI*.5*sin(sample_age*.22)
	return super._process(delta)

func finish() -> void:
	world.player.automatic_direction=Vector3.ZERO
	var report := {"variant":variant,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":stats(samples),"warmup":stats(cold),"cpu":stats(cpu),"physics":stats(physics),"frames_ms":samples,"warmup_ms":cold,"population":world.people.size(),"cars":world.production.vehicles.size(),"distance":world.player.travelled,"sources_before":sources,"sources_after":fingerprints(),"save_isolated":world.production.store.path.begins_with(folder),"notes":"Main real, C# ativo, caminhada local rampa/carga e órbita. Checkpoint inicial não valida viagem da cidade até o lago. Alvo provisório 60 FPS/16.67ms; >5% p95/p99 requer confirmação. Inventário externo de processos acompanha a evidência."}
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CARGO_PLANE_BENCHMARK ",folder," ",JSON.stringify(report.summary))
	# Fotos finais ficam fora da janela de medição e não comprovam FPS.
	world.camera.target_size=40
	world.camera.heading=PI*.5
	world.player.teleport(plane.to_global(Vector3(6.3,.08,-1)))
	world.camera.initialized=false
	for i in 60: await physics_frame
	await photograph("airframe-closed")
	world.camera.target_size=world.camera.WALK_SIZE_CLOSE
	world.camera.heading=PI*.25
	world.player.teleport(plane.to_global(Vector3(.15,.28,-5.5)))
	world.camera.initialized=false
	for i in 60: await physics_frame
	await photograph("cargo-open")
	world.queue_free(); await process_frame; quit()
