extends "res://tests/measure/measure_desert.gd"
## Main real e câmera de arrancada de produção. As poses da fixture NÃO são teste de travessia.
var race
var save_path := ""
var errors: Array[String] = []
var photos: Array[Dictionary] = []
var draw_samples: Array[float] = []
var population_samples: Array[int] = []
var vehicle_samples: Array[int] = []
var process_start: Dictionary = {}
var warmup: Dictionary = {}
var measurement_started := 0
var fingerprint_exclusions: Array[Dictionary] = []
var canyon_ground: Dictionary = {}

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): fail("300s bounded watchdog for three scenarios elapsed"))
	run.call_deferred()

func _process(delta: float) -> bool:
	super._process(delta)
	if sampling and is_instance_valid(world):
		draw_samples.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		population_samples.append(world.people.size())
		vehicle_samples.append(world.production.vehicles.size())
	return false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		fail("Rendered .NET with --benchmark --no-save --population=24 required")
		return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-horizon-measure")
	if output.is_empty(): fail("Cannot create isolated evidence folder"); return
	# Congela a lista inicial de caminhos: arquivos preparados sem referência acrescentados depois
	# não invalidam uma rodada. Mudanças/exclusões num caminho presente no início invalidam.
	fingerprint=source_fingerprint()
	if "--baseline-relief" in OS.get_cmdline_user_args():
		for filename in ["DesertHorizonRelief.gd","DesertTerrainRelief.gd","DesertTerrainMesh.gd","desert_relief.gdshader"]:
			var staged_path: String="res://world/desert/"+filename
			fingerprint_exclusions.append({"path":staged_path,"initially_present":fingerprint.has(staged_path),"reason":"Explicit baseline-only exclusion: unreferenced relief candidate under concurrent construction before production integration."})
			fingerprint.erase(staged_path)
	fingerprint[get_script().resource_path]=FileAccess.get_sha256(get_script().resource_path)
	fingerprint["res://scripts/CameraRig.gd"]=FileAccess.get_sha256("res://scripts/CameraRig.gd")
	fingerprint["res://tests/measure/measure_desert.gd"]=FileAccess.get_sha256("res://tests/measure/measure_desert.gd")
	process_start=process_metadata()
	var at := Vector3(-1150,.08,-1264)
	var snapshot: Dictionary=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	snapshot.world.time=.9
	save_path=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if save_path.is_empty(): fail("Validated isolated save could not be written"); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=save_path or world.production.save_invalid or not world.session.controller.no_save:
		fail("Main readiness, checkpoint validation or save isolation failed"); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: fail("Compiled native route backend unavailable"); return
	if world.production.requested_population!=24: fail("Run requires --population=24; actual requested population differs"); return
	if world.session.modal: world.session.close_menu()
	if world.session.desert==null or not is_instance_valid(world.session.desert.drag): fail("Production desert drag unavailable"); return
	race=world.session.desert.drag
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.9
	world.session.weather._update()
	await create_timer(2).timeout
	var car=world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not is_instance_valid(car): fail("Production car spawn failed"); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if world.session.modal: world.session.close_menu()
	if not world.driving.interact(): fail("Real boarding action rejected"); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and world.driving.car==car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	if not world.driving.occupied or world.driving.car!=car or not car.controlled or car.input_locked:
		fail("Real boarding did not complete"); return
	if world.session.modal: world.session.close_menu()
	if not race.perform("start"): fail("Real nearby night race start rejected: "+race.start_block_reason()); return
	# Só o controlador da corrida é suspenso. Main, população, clima, luzes,
	# áudio, streaming e física comum continuam vivos durante toda a medição.
	race.set_physics_process(false)
	for scenario in [{"id":"grid-night","hour":.9},{"id":"grid-day","hour":.45}]:
		world.session.weather.time_of_day=float(scenario.hour)
		world.session.weather._update()
		await fixture_pose(0.0)
		await photo(str(scenario.id)+"-before")
		await sample_warmup()
		await measure_grid(str(scenario.id))
		await photo(str(scenario.id)+"-after")
		for station in [{"id":"middle","offset":400.0},{"id":"finish","offset":800.0}]:
			await fixture_pose(float(station.offset))
			await photo(str(scenario.id)+"-"+str(station.id))
	if race.is_physics_processing() or not race.active: errors.append("Race fixture suspension changed during grid cases")
	race.cancel_attempt()
	for i in 3: await physics_frame
	if not world.driving.interact(): fail("Ordinary vehicle exit rejected before canyon case"); return
	for i in 600:
		await physics_frame
		if not world.driving.occupied and not world.driving.is_body_transition_active(): break
	if world.driving.occupied: fail("Ordinary vehicle exit did not complete"); return
	var canyon_at := Vector3(-850,0,-1740)
	world.production.region.set_focus(canyon_at)
	if not world.production.region.prepare_collision_at(canyon_at): fail("Canyon fixture ground admission rejected"); return
	# O streaming de produção segue o jogador real a cada quadro. Mantém o foco aqui
	# enquanto a colisão recém-instalada sincroniza, em vez de deixá-lo descarregar a célula.
	world.player.teleport(canyon_at+Vector3.UP*10)
	for i in 6: await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(canyon_at+Vector3.UP*250,canyon_at+Vector3.DOWN*120,1)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	var ground_normal: Vector3=hit.get("normal",Vector3.ZERO)
	if hit.is_empty() or ground_normal.y<.65: fail("Canyon measurement point has no walkable physical ground"); return
	var ground: Vector3=hit.position
	canyon_ground={"point":str(ground),"normal":str(hit.normal),"collider":str(hit.collider.name)}
	world.player.teleport(ground+Vector3.UP*.08)
	world.camera.initialized=false
	await create_timer(2).timeout
	await photo("canyon-normal-camera-before")
	await sample_warmup()
	await measure_grid("canyon-normal-camera")
	await photo("canyon-normal-camera-after")
	var ended := source_fingerprint(fingerprint)
	if fingerprint!=ended: errors.append("Initially present source changed during measurement")
	var result := metadata()
	result.merge({"valid":errors.is_empty(),"complete":true,"errors":errors,"scenarios":reports,"photos":photos,"canyon_physical_ground":canyon_ground,"fingerprint_exclusions":fingerprint_exclusions,"source_sha256_start":fingerprint,"source_sha256_end":ended,"source_stable":fingerprint==ended,"process_start":process_start,"process_end":process_metadata()},true)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DESERT_HORIZON_MEASURE ",output," valid=",errors.is_empty())
	race.cancel_attempt()
	quit(0 if errors.is_empty() else 1)

func clear_samples() -> void:
	samples.clear(); cpu.clear(); physics.clear()
	draw_samples.clear(); population_samples.clear(); vehicle_samples.clear()
	previous=Time.get_ticks_usec()

func sample_warmup() -> void:
	clear_samples()
	sampling=true
	await create_timer(10).timeout
	sampling=false
	warmup={"summary":stats(samples),"intervals_ms":samples.duplicate()}

func measure_grid(id: String) -> void:
	clear_samples()
	measurement_started=Time.get_ticks_usec()
	sampling=true
	await create_timer(30).timeout
	sampling=false
	var wall_seconds := float(Time.get_ticks_usec()-measurement_started)/1000000.0
	reports.append({"id":id,"sample_wall_seconds":wall_seconds,"warmup":warmup.duplicate(true),"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_monitor_summary":stats(cpu),"physics_monitor_summary":stats(physics),"cpu_monitor_ms":cpu.duplicate(),"physics_monitor_ms":physics.duplicate(),"draw_calls":range_summary(draw_samples),"requested_population":world.production.requested_population,"people_min":population_samples.min(),"people_max":population_samples.max(),"vehicles_min":vehicle_samples.min(),"vehicles_max":vehicle_samples.max(),"hour_end":world.session.weather.time_of_day,"camera":camera_metadata(),"native_backend":world.dispatch.router._native!=null,"race_physics_enabled":race.is_physics_processing()})
	FileAccess.open(output.path_join("partial.json"),FileAccess.WRITE).store_string(JSON.stringify({"complete":false,"scenarios":reports,"errors":errors},"\t"))
	print("DESERT_HORIZON_CASE ",id," ",JSON.stringify(reports[-1].summary))

func fixture_pose(distance: float) -> void:
	# Posicionamento explícito da fixture para revisão de ângulo/oclusão, não travessia física.
	for i in 2:
		var pose: Transform3D=race.grid(i)
		pose.origin+=race.direction*distance+Vector3.UP*.08
		world.production.region.prepare_collision_at(pose.origin)
		race.racers[i].car.global_transform=pose
		race.racers[i].car.velocity=Vector3.ZERO
	world.player.teleport(race.racers[0].car.global_position)
	world.production.region.set_focus(race.racers[0].car.global_position)
	race._update_camera(0)
	await create_timer(2).timeout
	race._update_camera(0)

func photo(id: String) -> void:
	assert(not sampling)
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(output.path_join(id+".png"))
	if code!=OK: errors.append("Screenshot failed: "+id)
	photos.append({"id":id,"file":id+".png","camera":camera_metadata(),"fixture_repositioned":true,"not_a_traversal_test":true})

func camera_metadata() -> Dictionary:
	var camera: Camera3D=root.get_camera_3d()
	var result := {"name":str(camera.name),"position":str(camera.global_position),"rotation":str(camera.global_rotation),"fov":camera.fov,"far":camera.far,"projection":camera.projection,"player":str(world.player.global_position)}
	if race.active and race.racers.size()==2:
		result["player_car"]=str(race.racers[0].car.global_position)
		result["rival_car"]=str(race.racers[1].car.global_position)
	return result

func range_summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"min":sorted[0],"p50":sorted[int((sorted.size()-1)*.5)],"p95":sorted[int((sorted.size()-1)*.95)],"max":sorted[-1]}

func metadata() -> Dictionary:
	return {"scenario":"desert_horizon_real_drag_grid_and_canyon_v1","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"window_size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"physics_ticks_per_second":Engine.physics_ticks_per_second,"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),"isolated_save":save_path,"notes":"Real Main .NET population24 requested, actual vehicle admission/boarding/night race start. Only race controller physics suspended after grid. Grid night/day and canyon normal-camera cases each10s warmup+30s steady wall-frame intervals; no screenshots inside measurements. Day is fixture lighting override after a legal night start, not a change to production race policy. Middle/finish images use explicit fixture reposition and do not prove traversal/collision. Canyon view follows actual ordinary car exit and a vertical physical ground ray at(-850,-1740), then fixture placement; it is not a traversal test. Process snapshots at endpoints do not rule out mid-run external interference; coordinator lease is required. CPU/physics monitors are sampled counters, not summed frame cost. No global FPS/lighting approval implied."}

func process_metadata() -> Dictionary:
	var result := {"pid":OS.get_process_id(),"utc":Time.get_datetime_string_from_system(true),"ticks_usec":Time.get_ticks_usec(),"processors":OS.get_processor_count(),"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args()}
	if OS.get_name()=="Windows":
		var listing: Array=[]
		var command := "Get-CimInstance Win32_Process -Filter \"Name LIKE 'Godot%'\" | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Compress"
		result["process_listing_exit"]=OS.execute("powershell",PackedStringArray(["-NoProfile","-NonInteractive","-Command",command]),listing,true)
		result["godot_processes_json"]="\n".join(listing)
	return result

func fail(reason: String) -> void:
	sampling=false
	errors.append(reason)
	push_error("DESERT_HORIZON "+reason)
	if not output.is_empty():
		FileAccess.open(output.path_join("failure.json"),FileAccess.WRITE).store_string(JSON.stringify({"complete":false,"errors":errors,"scenarios":reports,"fingerprint_exclusions":fingerprint_exclusions,"source_sha256_start":fingerprint,"source_sha256_end":source_fingerprint(fingerprint)},"\t"))
	quit(1)
