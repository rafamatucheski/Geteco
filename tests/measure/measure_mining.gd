extends "res://tests/measure/measure_desert.gd"
var arrival_reports: Array[Dictionary]=[]
## Mesmas configurações de câmera integrada do Main, XZ e população viva antes/depois;
## o chão plano da linha de base e o piso escavado têm necessariamente elevações diferentes.
func _initialize() -> void:
	create_timer(260).timeout.connect(func(): push_error("MINING_MEASURE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET and isolated --no-save required"); quit(2); return
	seed(6102026)
	Engine.set_meta("mining_benchmark_disabled","--without-mining" in OS.get_cmdline_user_args())
	Engine.set_meta("mining_dust_benchmark_disabled","--without-dust" in OS.get_cmdline_user_args())
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("mining-measure")
	fingerprint=source_fingerprint()
	for directory in ["res://world/mining","res://world/mining/coal","res://world/mining/operation","res://gameplay/mining","res://audio/mining"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
				var source: String=directory+"/"+filename
				fingerprint[source]=FileAccess.get_sha256(source)
	fingerprint["res://runtime/MiningRuntime.gd"]=FileAccess.get_sha256("res://runtime/MiningRuntime.gd")
	for directory in ["res://world/desert/village","res://world/desert/expansion","res://runtime/desert/expansion"]:
		_fingerprint_tree(directory)
	for source in ["res://world/places/PlaceCatalog.gd","res://data/catalogs/VehicleDoorSpecs.gd","res://runtime/FleetCatalog.gd","res://scripts/CameraRig.gd","res://scripts/Actor.gd","res://gameplay/Gameplay.gd","res://gameplay/CombatAudio.gd"]:
		fingerprint[source]=FileAccess.get_sha256(source)
	var at:=Vector3(-180,.08,-1645)
	var snapshot:=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		push_error("Main native startup/save isolation failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Native route backend missing"); quit(1); return
	if world.session.modal: world.session.close_menu()
	Engine.max_fps=0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	for setup in [
		{"id":"yard-day","point":Vector3(-180,.08,-1645),"hour":.45},
		{"id":"pit-night","point":Vector3(-173,.08 if "--without-mining" in OS.get_cmdline_user_args() else -27.92,-1782),"hour":.9},
	]:
		if setup.id=="yard-day" and "--skip-yard" in OS.get_cmdline_user_args(): continue
		samples.clear(); cpu.clear(); physics.clear()
		previous=Time.get_ticks_usec(); sampling=true
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		world.player.teleport(setup.point)
		world.camera.initialized=false
		world.session.weather.time_of_day=setup.hour
		world.session.weather._update()
		await create_timer(10).timeout
		sampling=false
		arrival_reports.append({"id":setup.id,"summary":stats(samples),"intervals_ms":samples.duplicate(),"note":"Fixture relocation, collision preparation and 10s shader/streaming warmup; separate from steady sampling."})
		await measure(setup.id)
		print("MINING_CASE ",setup.id," ",JSON.stringify(reports[-1].summary))
	if "--gallery" in OS.get_cmdline_user_args():
		var entry: Vector3=preload("res://world/mining/MiningLayout.gd").SECRET_ENTRY+Vector3.UP*.08
		samples.clear(); cpu.clear(); physics.clear()
		previous=Time.get_ticks_usec(); sampling=true
		world.production.region.set_focus(entry)
		world.production.region.prepare_collision_at(entry)
		world.player.teleport(entry)
		await create_timer(1).timeout
		if not await world.session.enter_place("remote_coal_mine",false): push_error("Mine admission failed"); quit(1); return
		world.session.room.restore_secret(true)
		await create_timer(10).timeout
		sampling=false
		arrival_reports.append({"id":"coal-gallery","summary":stats(samples),"intervals_ms":samples.duplicate(),"note":"Portal approach, transition and 10s interior warmup; separate from steady sampling."})
		await measure("coal-gallery")
		print("MINING_CASE coal-gallery ",JSON.stringify(reports[-1].summary))
	if "--overview" in OS.get_cmdline_user_args():
		if not world.session.state.place_id.is_empty(): await world.session.leave_place()
		var at_overview:=Vector3(-180,-27.92,-1778)
		world.production.region.set_focus(at_overview)
		world.production.region.prepare_collision_at(at_overview)
		world.player.teleport(at_overview)
		world.session.weather.time_of_day=.45
		world.session.weather._update()
		await create_timer(2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("pit-day-gameplay.png"))
		# Só revisão adicional de composição. As medições acima mantêm as câmeras de jogo
		# comuns; esta visão geral rotulada explicitamente tem uma lente de diagnóstico.
		world.production.region.set_retention_radius(2)
		var bounds: Rect2 = preload("res://world/mining/MiningLayout.gd").BOUNDS
		for x in range(floori(bounds.position.x / 96), ceili(bounds.end.x / 96)):
			for z in range(floori(bounds.position.y / 96), ceili(bounds.end.y / 96)):
				world.production.region.prepare_collision_at(Vector3((x + .5) * 96, 0, (z + .5) * 96))
		for frame in 900:
			await physics_frame
			if world.production.region.is_streaming_idle(): break
		world.camera.set_process(false)
		world.camera.far=600
		world.camera.size=280
		world.camera.position=Vector3(-180,200,-1590)
		world.camera.look_at(Vector3(-180,-8,-1750))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("mine-overview-diagnostic.png"))
		for id in ["mining_backhoe", "mining_tractor", "mining_haul_truck"]:
			for car in world.production.vehicles:
				if not is_instance_valid(car) or car.archetype != id: continue
				world.camera.size = 13 if id != "mining_haul_truck" else 18
				world.camera.position = car.global_position + Vector3(12, 10, -12)
				world.camera.look_at(car.global_position + Vector3.UP * 1.3)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(id + "-detail-diagnostic.png"))
				break
		world.camera.set_process(true)
	var stable:=fingerprint==source_fingerprint(fingerprint)
	var report:={"source_stable":stable,"scenarios":reports,"source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint),"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.production.requested_population,"save":path,"notes":"Real Main with native .NET routes; same cameras; 10s warmup + 30s samples. Provisional goal 60 FPS/16.67ms; >5% p95/p99 increase requests finite confirmation. Fixture relocation does not prove route traversal."}
	report["arrivals"]=arrival_reports
	report["without_mining"]="--without-mining" in OS.get_cmdline_user_args()
	report["without_dust"]="--without-dust" in OS.get_cmdline_user_args()
	report["msaa"]=root.msaa_3d
	report["notes"]="Main .NET, same XZ/camera configuration and population; baseline floor y0 versus excavated y-28. Warmup/arrival recorded separately from 30s steady samples. Goal60FPS/16.67ms; >5% p95/p99 increase requests finite confirmation. Fixture placement does not prove driving the road."
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MINING_MEASURE ",output," stable=",stable)
	quit(0 if stable else 1)

func _fingerprint_tree(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
			var source: String=directory+"/"+filename
			fingerprint[source]=FileAccess.get_sha256(source)
	for child in DirAccess.get_directories_at(directory): _fingerprint_tree(directory+"/"+child)

func measure(id: String) -> void:
	await super.measure(id)
	var lights: Array[Dictionary]=[]
	var light_root: Node=world.session.room if is_instance_valid(world.session.room) else world.production.region
	for light in light_root.find_children("*","OmniLight3D",true,false):
		if light_root==world.production.region and not light.has_meta("mining_light_energy"): continue
		lights.append({"name":str(light.name),"position":str(light.global_position),"visible":light.is_visible_in_tree(),"energy":light.light_energy,"range":light.omni_range,"shadows":light.shadow_enabled})
	reports[-1]["mine_lights"]=lights
	if is_instance_valid(world.production.region.mining_dust): reports[-1]["mine_dust"]=world.production.region.mining_dust.debug_snapshot()
	if is_instance_valid(world.production.region.mining_life): reports[-1]["mine_workers"]=world.production.region.mining_life.debug_snapshot()
