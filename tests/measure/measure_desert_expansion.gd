extends "res://tests/measure/measure_desert.gd"
## Mesmas posições reais do Main antes/depois. A realocação da fixture não é evidência de travessia.
var save_path := ""
var expansion_errors: Array[String] = []
var capped := false

func _initialize() -> void:
	create_timer(420).timeout.connect(func(): push_error("DESERT_EXPANSION timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with isolated --no-save required"); quit(2); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Engine.set_meta("desert_expansion_benchmark_disabled","--without-expansion" in OS.get_cmdline_user_args())
	Engine.set_meta("desert_landform_cache_benchmark_disabled","--without-landform-cache" in OS.get_cmdline_user_args())
	capped="--normal-cap" in OS.get_cmdline_user_args()
	output=FIXTURE.output_dir("desert-expansion-measure")
	fingerprint=source_fingerprint()
	fingerprint[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)
	for directory in ["res://world/desert/expansion","res://runtime/desert/expansion"]:
		if DirAccess.dir_exists_absolute(directory):
			for filename in DirAccess.get_files_at(directory):
				if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
					var source: String=directory+"/"+filename
					fingerprint[source]=FileAccess.get_sha256(source)
	var at := Vector3(-1092,.08,-575)
	var snapshot := FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	save_path=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if save_path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=save_path or world.production.save_invalid:
		push_error("Main readiness/save isolation failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null or world.production.requested_population!=24:
		push_error("Native backend/population24 missing"); quit(1); return
	if world.session.modal: world.session.close_menu()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Engine.max_fps=60 if capped else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if capped else DisplayServer.VSYNC_DISABLED)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	var cases := [
		{"id":"station-day","point":Vector3(-1092,.08,-575),"hour":.45},
		{"id":"dunes-day","point":Vector3(-30,.08,-610),"hour":.45},
		{"id":"wash-day","point":Vector3(-650,.08,-1080),"hour":.45},
		{"id":"salt-day","point":Vector3(-790,.08,-1420),"hour":.45},
		{"id":"mine-night","point":Vector3(-1390,.08,-1065),"hour":.9},
		{"id":"ecology-day","point":Vector3(-1062,.08,-1078),"approach":Vector3(-1040,.08,-1072),"hour":.45},
	]
	if capped: cases=[cases[0],cases[4],cases[5]]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			var selected:=argument.trim_prefix("--case=").split(",")
			cases=cases.filter(func(record): return str(record.id) in selected)
	if cases.is_empty(): push_error("Unknown expansion benchmark case"); quit(2); return
	for setup in cases:
		world.session.weather.time_of_day=setup.hour
		world.session.weather._update()
		if setup.has("approach"):
			world.production.region.set_focus(setup.approach)
			world.production.region.prepare_collision_at(setup.approach)
			world.player.teleport(setup.approach)
			await create_timer(2).timeout
		samples.clear(); cpu.clear(); physics.clear(); previous=Time.get_ticks_usec(); sampling=true
		var admission_started:=Time.get_ticks_usec()
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		world.player.teleport(setup.point+Vector3.UP*4)
		world.camera.initialized=false
		var admission_ms:=float(Time.get_ticks_usec()-admission_started)/1000.0
		await create_timer(3).timeout
		sampling=false
		var cold := {"summary":stats(samples),"intervals_ms":samples.duplicate(),"synchronous_admission_ms":admission_ms}
		var p: Vector3=setup.point
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*100,p+Vector3.DOWN*10,1)
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): expansion_errors.append("Missing physical ground: "+str(setup.id))
		else: world.player.teleport(hit.position+Vector3.UP*.08)
		await create_timer(10).timeout
		await measure(str(setup.id))
		reports[-1]["first_visit"]=cold
		reports[-1]["player"]=str(world.player.global_position)
		reports[-1]["camera_position"]=str(root.get_camera_3d().global_position)
		reports[-1]["native_backend"]=world.dispatch.router._native!=null
		var ecology: Node3D=world.production.region.expansion_life
		reports[-1]["ecology"]=ecology.diagnostics() if is_instance_valid(ecology) else {}
		reports[-1]["landform_prewarm"]=world.production.region.expansion_prewarm
		print("EXPANSION_CASE ",setup.id," ",JSON.stringify(reports[-1].summary))
	var ended := source_fingerprint(fingerprint)
	var stable := fingerprint==ended
	var changes: Array[String]=[]
	for path in fingerprint:
		if fingerprint[path]!=ended.get(path): changes.append(path)
	var report := {"valid":stable and expansion_errors.is_empty(),"source_stable":stable,"changed_sources":changes,"errors":expansion_errors,"scenarios":reports,"source_sha256_start":fingerprint,"source_sha256_end":ended,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"isolated_save":save_path,"requested_population":24,"user_args":OS.get_cmdline_user_args(),"notes":"Actual Main .NET; 3s first visit separately,10s warmup,30s steady per case. Positions are fixtures and do not prove traversal. Existing game population remains alive. Goal60FPS/16.67ms; >5% p95/p99 requires one finite confirmation with equivalent conditions. No global performance approval."}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DESERT_EXPANSION_MEASURE ",output," stable=",stable)
	quit(0 if report.valid else 1)
