extends "res://tests/measure/measure_desert.gd"
## Absolute current-state Main measurements. No usable comparative baseline exists.
const CAMP := preload("res://world/desert/DesertBanditCamp.gd")
var save_path := ""
var errors: Array[String]=[]
var counter_samples: Array[Dictionary]=[]
var draws: Array[float]=[]
var counter_due := 0
var process_start: Dictionary={}
var photos: Array[String]=[]
var region: Node3D
var bandits: Node3D
var wildlife: Node3D
var finished := false

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): fail("240s frontier measurement watchdog elapsed"))
	run.call_deferred()

func _process(delta: float) -> bool:
	super._process(delta)
	if sampling and is_instance_valid(world):
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if Time.get_ticks_msec()>=counter_due:
			counter_due=Time.get_ticks_msec()+1000
			counter_samples.append(counters())
	return false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		fail("Rendered native .NET --benchmark --no-save --population=24 required"); return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-frontier-measure")
	if output.is_empty(): fail("Cannot create isolated evidence folder"); return
	fingerprint=source_fingerprint()
	# A impressão digital do pai cobre o código central/áudio/HUD/veículo; inclui a expansão
	# aninhada e esta fixture exata enquanto congela a lista inicial de arquivos.
	add_source_tree("res://world/desert",fingerprint)
	for path in [get_script().resource_path,"res://tests/measure/measure_desert.gd","res://scripts/CameraRig.gd","res://gameplay/Gameplay.gd","res://gameplay/CobraAgent.gd"]: fingerprint[path]=FileAccess.get_sha256(path)
	process_start=process_metadata()
	var at := Vector3(-850,preload("res://world/desert/DesertTerrainMesh.gd").surface_height(Vector2(-850,-1740))+.08,-1740)
	var snapshot: Dictionary=FIXTURE.full_snapshot(at,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	snapshot.world.time=.45
	snapshot.world[preload("res://runtime/desert/DesertBanditEncounter.gd").STATE_KEY]=preload("res://runtime/desert/DesertBanditEncounter.gd").default_state()
	save_path=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if save_path.is_empty(): fail("Isolated checkpoint validation failed"); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",save_path)
	root.add_child(world); current_scene=world
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled or not world.production.ready_for_play:
		fail("Session and background production startup did not both settle"); return
	if world.production.store.path!=save_path or world.production.save_invalid or not world.session.controller.no_save:
		fail("Save isolation failed"); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null or world.production.requested_population!=24:
		fail("Native backend or requested population24 missing"); return
	if world.session.modal: world.session.close_menu()
	if world.gameplay.god_mode: fail("God mode must remain disabled"); return
	region=world.production.region
	bandits=world.session.desert.frontier.bandits
	wildlife=region.wildlife
	if not is_instance_valid(bandits) or not is_instance_valid(wildlife): fail("Production frontier or canyon wildlife unavailable"); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	for setup in [
		{"id":"canyon-fauna-flora-day","point":Vector3(-850,0,-1740),"size":20.0},
		{"id":"abandoned-ruins-day","point":Vector3(-1300,0,-1708),"size":20.0},
		{"id":"remote-bandit-camp-day","point":CAMP.CENTER+Vector3.RIGHT*33,"size":45.0},
	]:
		if not await admit(setup.point,float(setup.size)): return
		world.session.weather.time_of_day=.45
		world.session.weather._update()
		await warm_and_measure(str(setup.id))
		if not errors.is_empty(): finish(); return
		# A correção de câmera só afeta o cânion. O primeiro cenário mantém
		# o início, a pose e a janela de amostragem idênticos da rodada de referência completa.
		if "--canyon-only" in OS.get_cmdline_user_args(): break
	finish()

func admit(at: Vector3, camera_size: float) -> bool:
	# Estabelece a residência do jogador ANTES de esperar a sincronização de colisão.
	# O posicionamento inicial e estes posteriores não provam acesso físico.
	var expected: float=preload("res://world/desert/DesertTerrainMesh.gd").surface_height(Vector2(at.x,at.z))
	world.player.teleport(Vector3(at.x,expected+2,at.z))
	region.set_focus(at)
	if not region.prepare_collision_at(at): fail("Ground chunk admission failed"); return false
	for i in 6: await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x,expected+2,at.z),Vector3(at.x,expected-2,at.z),1)
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or float(hit.normal.y)<.65: fail("Scenario has no walkable physical terrain"); return false
	var point: Vector3=hit.position+Vector3.UP*.08
	if not world.session.position_clear(point): fail("Scenario actor capsule would overlap a solid"); return false
	world.player.teleport(point)
	world.camera.target=world.player
	world.camera.initialized=false
	world.camera.heading=0
	world.camera.target_size=camera_size
	return true

func clear_samples() -> void:
	samples.clear(); cpu.clear(); physics.clear(); draws.clear(); counter_samples.clear()
	previous=Time.get_ticks_usec(); counter_due=0

func warm_and_measure(id: String) -> void:
	var processes_before := process_metadata()
	clear_samples(); sampling=true
	await create_timer(10).timeout
	sampling=false
	var warm := {"summary":stats(samples),"intervals_ms":samples.duplicate(),"counters":counter_samples.duplicate(true)}
	if not scene_valid(id): return
	await photo(id+"-before")
	var before := counters()
	var flora := flora_metadata()
	clear_samples()
	var began := Time.get_ticks_usec()
	sampling=true
	await create_timer(30).timeout
	sampling=false
	var wall_seconds := float(Time.get_ticks_usec()-began)/1000000.0
	var after := counters()
	var valid := scene_valid(id)
	if samples.is_empty(): fail("No frame intervals collected"); return
	var row := {"id":id,"valid":valid,"warmup":warm,"sample_wall_seconds":wall_seconds,"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_monitor_summary":stats(cpu),"physics_monitor_summary":stats(physics),"cpu_monitor_ms":cpu.duplicate(),"physics_monitor_ms":physics.duplicate(),"draw_calls":range_summary(draws),"instant_counters_1hz":counter_samples.duplicate(true),"counters_before":before,"counters_after":after,"flora_before":flora,"camera":camera_metadata(),"processes_before_warmup":processes_before,"processes_after_sample":process_metadata(),"fixture_repositioned":true,"not_a_traversal_test":true}
	for sample in counter_samples:
		if bool(sample.modal) or bool(sample.god_mode) or float(sample.health)<=0 or not bool(sample.native_backend):
			errors.append("Gameplay/native contract changed during "+id); break
		if id=="remote-bandit-camp-day" and (int(sample.bandits_alive)!=3 or int(sample.bandits_in_view)!=3 or bool(sample.bandits_engaged)):
			errors.append("Three visible living non-engaged bandits not maintained during sample"); break
	row["valid"]=valid and errors.is_empty()
	reports.append(row)
	await photo(id+"-after")
	FileAccess.open(output.path_join("partial.json"),FileAccess.WRITE).store_string(JSON.stringify({"complete":false,"errors":errors,"scenarios":reports},"\t"))
	print("DESERT_FRONTIER_CASE ",id," ",JSON.stringify(row.summary))

func scene_valid(id: String) -> bool:
	if world.session.modal or world.gameplay.god_mode or world.gameplay.health<=0 or world.player.input_locked:
		errors.append("Modal/invulnerability/death/input lock invalidates "+id); return false
	if Engine.max_fps!=0 or DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED:
		errors.append("Sampling must remain uncapped with VSync disabled"); return false
	if root.get_camera_3d()!=world.camera or world.camera.locked:
		errors.append("Normal production camera unavailable"); return false
	if id=="remote-bandit-camp-day":
		var current := counters()
		if int(current.bandits_alive)!=3 or int(current.bandits_in_view)!=3 or bool(current.bandits_engaged):
			errors.append("Camp requires three living visible bandits outside aggression range"); return false
	if id=="canyon-fauna-flora-day" and int(counters().wildlife_active)==0:
		errors.append("Canyon wildlife is absent; cannot claim fauna scenario"); return false
	return true

func counters() -> Dictionary:
	var animals := 0
	var capacity := 0
	if is_instance_valid(wildlife):
		capacity=wildlife._animals.size()
		for animal in wildlife._animals:
			if bool(animal.active) and is_instance_valid(animal.node) and animal.node.is_visible_in_tree(): animals+=1
	var in_view := 0
	var camera: Camera3D=root.get_camera_3d()
	if is_instance_valid(bandits) and is_instance_valid(camera):
		for actor in bandits.actors.values():
			if not is_instance_valid(actor) or actor.dead: continue
			var point: Vector3=actor.global_position+Vector3.UP
			if not camera.is_position_behind(point) and root.get_visible_rect().has_point(camera.unproject_position(point)): in_view+=1
	var at: Vector3=world.player.global_position
	var ecology: Dictionary=region.expansion_life.diagnostics() if is_instance_valid(region.expansion_life) else {}
	return {"ticks_usec":Time.get_ticks_usec(),"physics_frame":Engine.get_physics_frames(),"render_frame":Engine.get_frames_drawn(),"people":world.people.size(),"requested_population":world.production.requested_population,"vehicles":world.production.vehicles.size(),"wildlife_active":animals,"wildlife_capacity":capacity,"expansion_animals_active":int(ecology.get("ground_animals",0)),"bandits_alive":bandits.live_count(),"bandits_resident":bandits.actors.size(),"bandits_engaged":bandits.snapshot().engaged,"bandits_in_view":in_view,"region_chunks":region.chunks.size(),"streaming_idle":region.is_streaming_idle(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"player_position":[at.x,at.y,at.z],"exact_terrain_height":preload("res://world/desert/DesertTerrainMesh.gd").surface_height(Vector2(at.x,at.z)),"player_on_floor":world.player.is_on_floor(),"health":world.gameplay.health,"god_mode":world.gameplay.god_mode,"modal":world.session.modal,"native_backend":world.dispatch.router._native!=null}

func flora_metadata() -> Dictionary:
	var dry_batches := 0
	var expansion_batches := 0
	var expansion_plants := 0
	for node in region.find_children("*","MeshInstance3D",true,false):
		if node.name=="DesertDryFloraBatch": dry_batches+=1
		if node.name=="DesertEcologyFloraBatch":
			expansion_batches+=1
			expansion_plants+=node.get_meta("flora_positions",PackedVector3Array()).size()
	return {"dry_flora_batches":dry_batches,"expansion_flora_batches":expansion_batches,"expansion_plants":expansion_plants}

func camera_metadata() -> Dictionary:
	var camera: Camera3D=root.get_camera_3d()
	return {"path":str(camera.get_path()),"position":str(camera.global_position),"rotation":str(camera.global_rotation),"size":camera.size,"projection":camera.projection,"fov":camera.fov,"far":camera.far,"normal_rig":camera==world.camera,"target":str(world.camera.target.get_path()),"locked":world.camera.locked}

func photo(id: String) -> void:
	assert(not sampling)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(id+".png"))!=OK: errors.append("Photo failed: "+id)
	photos.append(id+".png")

func range_summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered := values.duplicate(); ordered.sort()
	return {"min":ordered[0],"p50":ordered[int((ordered.size()-1)*.5)],"p95":ordered[int((ordered.size()-1)*.95)],"max":ordered[-1]}

func add_source_tree(folder: String, result: Dictionary) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd") or file.ends_with(".gdshader"): result[folder.path_join(file)]=FileAccess.get_sha256(folder.path_join(file))
	for directory in DirAccess.get_directories_at(folder): add_source_tree(folder.path_join(directory),result)

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
	push_error("DESERT_FRONTIER_MEASURE "+reason)
	finish()

func finish() -> void:
	if finished: return
	finished=true; sampling=false
	var ended := source_fingerprint(fingerprint)
	if not fingerprint.is_empty() and fingerprint!=ended: errors.append("Initially present source changed during measurement")
	var expected_scenarios := 1 if "--canyon-only" in OS.get_cmdline_user_args() else 3
	if reports.size()!=expected_scenarios: errors.append("Selected complete scenario samples required: %d"%expected_scenarios)
	if not output.is_empty():
		var result := {"complete":reports.size()==expected_scenarios,"requested_scenarios":expected_scenarios,"valid":errors.is_empty(),"comparison":"current-state absolute measurement only; previous relief baseline invalidated by external overlap","errors":errors,"scenarios":reports,"photos":photos,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"window_size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"physics_ticks_per_second":Engine.physics_ticks_per_second,"isolated_save":save_path,"source_stable":fingerprint==ended,"source_sha256_start":fingerprint,"source_sha256_end":ended,"process_start":process_start,"process_end":process_metadata(),"external_overlap_verification":"Coordinator lease/process history required; endpoint snapshots alone do not exclude interference during samples","notes":"Actual rendered Main .NET, population24 requested, alive ordinary actor, native routing, normal camera. Each scenario10s warmup and30s steady wall-frame intervals; no screenshot/process-list/source hashing inside samples. Camp uses existing CameraRig target_size45 review zoom to include three non-aggressive bandits at33m; canyon and ruins size20. Fixture ground-ray placements do not prove access traversal. No invulnerability, disabled NPC controller or modal pause. CPU/physics monitors are sampled counters, not summed frame cost. This provides no before/after or universal lighting/FPS certification."}
		# Lê os metadados de geração/cache depois de toda a amostragem, nunca no laço de quadros.
		result["terrain_mesh"]=preload("res://world/desert/DesertTerrainMesh.gd").diagnostics()
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DESERT_FRONTIER_MEASURE_DONE ",output," valid=",errors.is_empty())
	quit(0 if errors.is_empty() else 1)
