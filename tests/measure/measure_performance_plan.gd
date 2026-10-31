extends SceneTree
## Diagnóstico renderizado na cena de produção, com callbacks normais e saves isolados.
## Espera os limites de população/trânsito da produção, depois aquece 10 s e amostra >=30 s.
var world: Node
var label := "baseline"
var output := ""
var scenario := "idle"
var profile := false
var frames: Array[float] = []
var gpu: Array[float] = []
var render_cpu: Array[float] = []
var physics: Array[float] = []
var process_cpu: Array[float] = []
var draws: Array[float] = []
var warm: Array[float] = []
var states: Array[Dictionary] = []
var seconds := 30.0
var setup_seconds := 90.0
var focus_wait_seconds := 30.0
var shots := 0
var focused := 0
var minimized_frames := 0
var last_shot := 0
var initialized_at := 0
var settling_seconds := 0.0
var settling_states: Array[Dictionary] = []
var settled_state: Dictionary = {}
var profile_started := false
var startup_orphan_enabled := false
var startup_orphan_seen: Dictionary = {}
var startup_orphan_rows: Array[Dictionary] = []
var startup_orphan_dropped := 0
var startup_orphan_usec := 0
var native_presentation := preload("res://tests/measure/NativePresentationGate.gd").new()

func census_startup_orphans(phase: String) -> void:
	if not startup_orphan_enabled: return
	var began := Time.get_ticks_usec()
	for id: int in Node.get_orphan_node_ids():
		if startup_orphan_seen.has(id): continue
		var node := instance_from_id(id) as MeshInstance3D
		# O vazamento observado na saída consiste em malhas sem pai. Subárvores próprias
		# desligadas ficam fora deste censo, não são classificadas automaticamente como vazamento.
		if node == null or node.get_parent() != null: continue
		startup_orphan_seen[id] = true
		if startup_orphan_rows.size() >= 256:
			startup_orphan_dropped += 1
			continue
		var mesh := node.mesh
		var materials: Array[Dictionary] = []
		var count := mesh.get_surface_count() if mesh != null else 0
		for surface in mini(count,16):
			materials.append(describe_warmup_material(node.get_active_material(surface)))
		var row := {"phase":phase,"engine_usec":began,"frame":Engine.get_process_frames(),
			"id":str(id),"name":str(node.name),"queued":node.is_queued_for_deletion(),
			"mesh_path":mesh.resource_path if mesh != null else "",
			"mesh_id":str(mesh.get_instance_id()) if mesh != null else "",
			"materials":materials,"omitted_surfaces":maxi(0,count-16)}
		startup_orphan_rows.append(row)
		print("STARTUP_PARENTLESS_MESH ",JSON.stringify(row))
	startup_orphan_usec += Time.get_ticks_usec()-began

const MAX_IDENTITY_INTERVALS := 12000
const MAX_IDENTITY_WARMUPS := 16
const WARMUP_SOURCE := preload("res://gameplay/VehicleInterior.gd")
var warmup_identity_enabled := false
var identity_intervals: Array[Dictionary] = []
var identity_warmups: Array[Dictionary] = []
var identity_interval_dropped := 0
var identity_dropped_warmups := 0
var identity_dropped_intervals := 0
var identity_draw_pre := 0
var identity_draw_post := 0

func describe_warmup_material(material: Material) -> Dictionary:
	if material == null: return {}
	var row := {"class":material.get_class(),"instance_id":material.get_instance_id(),"resource_path":material.resource_path}
	if material is BaseMaterial3D:
		row.merge({"transparency":material.transparency,"shading_mode":material.shading_mode,
			"blend_mode":material.blend_mode,"depth_draw_mode":material.depth_draw_mode,"cull_mode":material.cull_mode,
			"no_depth_test":material.no_depth_test,"vertex_color_use_as_albedo":material.vertex_color_use_as_albedo,
			"albedo_color":str(material.albedo_color),"roughness":material.roughness,"metallic":material.metallic,
			"emission_enabled":material.emission_enabled,"normal_enabled":material.normal_enabled,
			"albedo_texture":material.albedo_texture.resource_path if material.albedo_texture != null else "",
			"albedo_texture_present":material.albedo_texture != null})
	elif material is ShaderMaterial:
		row["shader_path"] = material.shader.resource_path if material.shader != null else ""
	return row

func record_warmup_node(node: MeshInstance3D) -> void:
	if identity_warmups.size() >= MAX_IDENTITY_WARMUPS:
		identity_interval_dropped += 1
		return
	var began := Time.get_ticks_usec()
	var visual := node.get_parent()
	var vehicle: Node = visual.get_parent() if visual != null else null
	var row := {"engine_usec":began,"process_frame":Engine.get_process_frames(),"path":str(node.get_path()),
		"material_override":describe_warmup_material(node.material_override),
		"cast_shadow":node.cast_shadow,"layers":node.layers,
		"mesh_class":node.mesh.get_class() if node.mesh != null else "",
		"mesh_instance_id":node.mesh.get_instance_id() if node.mesh != null else 0,
		"surface_count":node.mesh.get_surface_count() if node.mesh != null else 0}
	var valid_owner: bool = is_instance_valid(vehicle) and "archetype" in vehicle and "visual" in vehicle and vehicle.get("visual") == visual
	row["vehicle_owner_verified"] = valid_owner
	if valid_owner:
		row["vehicle_path"] = str(vehicle.get_path())
		row["vehicle_instance_id"] = vehicle.get_instance_id()
		row["archetype"] = str(vehicle.get("archetype"))
		row["vehicle_id"] = str(vehicle.get("vehicle_id")) if "vehicle_id" in vehicle else ""
		if vehicle is Node3D: row["vehicle_position"] = str(vehicle.global_position)
	row["capture_usec"] = Time.get_ticks_usec()-began
	identity_warmups.append(row)

func is_interior_warmup(node: Node) -> bool:
	if not node is MeshInstance3D or node.mesh == null: return false
	if node.position != Vector3(0,-300,0) or node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
	var material := node.material_override as StandardMaterial3D
	if material == null or material.resource_name != "glass" or material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA: return false
	var visual := node.get_parent()
	var vehicle: Node = visual.get_parent() if visual != null else null
	if not is_instance_valid(vehicle) or not "archetype" in vehicle or not "visual" in vehicle or vehicle.get("visual") != visual: return false
	return int(WARMUP_SOURCE._warming.get(str(vehicle.get("archetype")),0)) == vehicle.get_instance_id()

func start_identity_diagnostic() -> void:
	# Só observador opcional: sem wrappers de runtime, arrays de malha nem leitura da GPU.
	node_added.connect(func(node: Node) -> void:
		if is_interior_warmup(node): record_warmup_node(node))
	RenderingServer.frame_pre_draw.connect(func(): identity_draw_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): identity_draw_post = Time.get_ticks_usec())

func capture_identity_interval(now: int, previous: int, phase: String) -> void:
	var began := Time.get_ticks_usec()
	identity_dropped_warmups += identity_interval_dropped
	if identity_intervals.size() < MAX_IDENTITY_INTERVALS:
		var pre_seen := identity_draw_pre != 0
		var post_seen := identity_draw_post != 0
		var draw_in_interval := pre_seen and post_seen and identity_draw_pre >= previous and identity_draw_post <= now
		var row := {"start_usec":previous,"end_usec":now,"process_frame":Engine.get_process_frames(),"phase":phase,
			"focused":DisplayServer.window_is_focused(),
			"draw_pre_usec":identity_draw_pre,"draw_post_usec":identity_draw_post,
			"draw_pre_seen":pre_seen,"draw_post_seen":post_seen,
			"draw_pre_offset_usec":identity_draw_pre-previous if pre_seen else -1,
			"draw_post_offset_usec":identity_draw_post-previous if post_seen else -1,
			"draw_pair_valid":draw_in_interval and identity_draw_pre <= identity_draw_post,
			"pipelines":[Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
				Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)],
			"warmup_nodes":identity_warmups,"dropped_warmup_nodes":identity_interval_dropped}
		identity_intervals.append(row)
		row["capture_usec"] = Time.get_ticks_usec()-began
	else:
		identity_dropped_intervals += 1
		identity_dropped_warmups += identity_warmups.size()
	identity_warmups = []
	identity_interval_dropped = 0
	identity_draw_pre = 0
	identity_draw_post = 0

func _initialize() -> void: run.call_deferred()

func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames": values.size(), "seconds": total/1000.0, "mean_ms": total/values.size(), "fps": 1000.0*values.size()/maxf(total,.001), "p50_ms": sorted[int((sorted.size()-1)*.5)], "p95_ms": sorted[int((sorted.size()-1)*.95)], "p99_ms": sorted[int((sorted.size()-1)*.99)], "max_ms": sorted[-1], "over_33_3_ms": slow, "over_66_7_ms": very_slow}

func metric_stats(values: Array[float], unit: String) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += value
	return {"samples":values.size(), "unit":unit, "mean":total/values.size(), "p50":sorted[int((sorted.size()-1)*.5)], "p95":sorted[int((sorted.size()-1)*.95)], "p99":sorted[int((sorted.size()-1)*.99)], "max":sorted[-1]}

func streaming_idle() -> bool:
	for region in world.production.regions.values():
		if is_instance_valid(region) and (not region.is_streaming_idle() or not region._retiring.is_empty()): return false
	return true

func state() -> Dictionary:
	var router = world.dispatch.router if is_instance_valid(world.dispatch) else null
	var moving := 0
	var stopped := 0
	var physics_active := 0
	for car in world.production.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion() or not car.traffic or car.health <= 0: continue
		if absf(float(car.speed)) > .2: moving += 1
		else: stopped += 1
		if car.is_physics_processing(): physics_active += 1
	return {"point": str(world.player.global_position), "people": world.people.size(), "requested_population":world.production.requested_population, "population_cap":world.production._population_cap(), "density_scale":world.production.density_scale, "vehicles": world.production.vehicles.size(), "ambient_traffic":world.production._ambient_traffic_count(), "traffic_cap":world.production._traffic_cap(), "traffic_moving":moving, "traffic_stopped":stopped, "traffic_physics_processing":physics_active, "streaming_idle":streaming_idle(), "physics_frame":Engine.get_physics_frames(), "units": world.dispatch.units.size(), "stars": world.gameplay.stars, "health": world.gameplay.health, "place": world.session.state.place_id, "modal": world.session.modal, "camera_size": world.camera.size, "camera_transform":str(world.camera.global_transform), "camera_heading":world.camera.heading, "camera_preview":world.camera.preview_view, "weather_time":world.session.weather.time_of_day, "focused":DisplayServer.window_is_focused(), "window_mode":DisplayServer.window_get_mode(), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects": Performance.get_monitor(Performance.OBJECT_COUNT), "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "active_physics": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), "collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), "router_native": router != null and router.get("_native") != null}

func settle_load() -> bool:
	var began := Time.get_ticks_usec()
	var next_probe := began
	while Time.get_ticks_usec()-began < int(setup_seconds*1000000.0):
		await process_frame
		var now := Time.get_ticks_usec()
		if now < next_probe: continue
		next_probe = now+1000000
		var row := state()
		row["settling_t"] = (now-began)/1000000.0
		settling_states.append(row)
		if row.people >= row.population_cap and row.ambient_traffic >= row.traffic_cap and row.streaming_idle:
			settling_seconds = (now-began)/1000000.0
			settled_state = row
			return true
	settling_seconds = (Time.get_ticks_usec()-began)/1000000.0
	return false

func apply_load(now: int) -> void:
	if scenario != "chaos" or now-last_shot < 200000: return
	last_shot = now
	if world.gameplay.fire_at(world.player.global_position+Vector3(8,.3,-2)): shots += 1
	if world.session.state.get_ammo("ak47").magazine == 0: world.gameplay.reload_weapon()

func run() -> void:
	startup_orphan_enabled = OS.get_environment("HARBOR_PLAN_STARTUP_ORPHANS") == "1"
	warmup_identity_enabled = OS.get_environment("HARBOR_PLAN_WARMUP_IDENTITY") == "1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--seconds="): seconds = maxf(30,float(arg.trim_prefix("--seconds=")))
		elif arg.begins_with("--setup-seconds="): setup_seconds = clampf(float(arg.trim_prefix("--setup-seconds=")),90.0,180.0)
		elif arg.begins_with("--native-focus-wait-seconds="): focus_wait_seconds = clampf(float(arg.trim_prefix("--native-focus-wait-seconds=")),30.0,180.0)
		elif arg == "--profile": profile = true
	if output.is_empty() or DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if not ClassDB.class_exists(&"CSharpScript") or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): push_error("Requires compiled .NET path"); quit(3); return
	create_timer(maxf(240.0,setup_seconds+seconds+75.0+focus_wait_seconds-30.0)).timeout.connect(func(): push_error("PERFORMANCE_PLAN_TIMEOUT"); quit(4))
	initialized_at = Time.get_ticks_usec()
	census_startup_orphans("before_main")
	world = load("res://Main.tscn").instantiate()
	census_startup_orphans("main_instantiated")
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	census_startup_orphans("main_added")
	current_scene = world
	# A prontidão da sessão ocorre antes de a produção terminar o aquecimento final.
	# Não deixa restore_location nem a cortina de carregamento sobrescreverem esta fixture.
	while world.session == null or not world.session.ready_for_play or world.production == null or not world.production.ready_for_play or root.has_node("LoadingCurtain") or world.has_node("LoadingCurtain"):
		await process_frame
		census_startup_orphans("startup")
	print("PERFORMANCE_PLAN_FINAL_STARTUP_READY ",Time.get_ticks_usec())
	census_startup_orphans("startup_final")
	if scenario == "startup-orphans":
		if not startup_orphan_enabled: push_error("Startup orphan census required"); quit(7); return
		var survivors: Array[String] = []
		for row in startup_orphan_rows:
			if is_instance_id_valid(int(row.id)): survivors.append(row.id)
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify({"rows":startup_orphan_rows,"surviving_ids":survivors,"dropped":startup_orphan_dropped,"capture_usec":startup_orphan_usec,"scope":"Startup-only parentless MeshInstance census; no gameplay FPS measurement."},"\t"))
		quit(0 if startup_orphan_dropped == 0 else 7)
		return
	world.session.state.intro.stage = "complete"
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	# A FullSession consulta o ponteiro independente dos callbacks de entrada. Fixa uma direção
	# de mira real no estilo controle para que o movimento do mouse do desktop não mova a
	# câmera nem mude a pose da arma entre as rodadas comparadas.
	var controls := root.get_node("GameInput")
	controls.set_process_input(false)
	controls._clear_camera_motion()
	controls.touch_aim = Vector2(5.0,3.0).normalized()
	world.player.teleport(Vector3(107,.1,23))
	world.production.region.set_focus(world.player.global_position)
	world.camera.initialized = false
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather._update()
	if not await settle_load():
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify({"label":label,"scenario":scenario,"invalid":"settling_timeout","settling_seconds":settling_seconds,"settling_states":settling_states,"last_state":state(),"summary":{}},"\t"))
		push_error("PERFORMANCE_PLAN_SETTLING_TIMEOUT: population/traffic caps and streaming did not settle within %.0f seconds" % setup_seconds)
		quit(6)
		return
	# Reinicia o relógio no limite do cenário: durações de preenchimento diferentes não podem
	# mudar em silêncio a luz do dia entre janelas comparáveis de aquecimento/amostra.
	world.session.weather.time_of_day = .4
	world.session.state.world_state.time = .4
	world.session.weather._update()
	if scenario == "chaos":
		world.gameplay.toggle_god_mode()
		world.gameplay.activate_arsenal_cheat()
		world.session.state.equip_weapon("ak47")
		world.gameplay.register_crime(150,world.player.global_position)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	if profile:
		if not EngineDebugger.is_active() or not EngineDebugger.has_profiler("servers"): push_error("Profiler receiver missing"); quit(5); return
	if not await native_presentation.wait_until_presented(self):
		DirAccess.make_dir_recursive_absolute(output)
		FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify({"label":label,"invalid":native_presentation.failure,"native_presentation":native_presentation.snapshot(),"summary":{},"last_state":state()},"\t"))
		push_error("PERFORMANCE_PLAN_NATIVE_PRESENTATION: "+native_presentation.failure)
		quit(8)
		return
	if warmup_identity_enabled: start_identity_diagnostic()
	var started := Time.get_ticks_usec()
	var previous := started
	var next_state := started
	var sample_started := 0
	var invalid := ""
	print("PERFORMANCE_PLAN_READY ",label," ",scenario," ",JSON.stringify(state()))
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now-previous)/1000.0
		var presentation_failure: String = native_presentation.poll(now)
		if not presentation_failure.is_empty():
			invalid = presentation_failure
			break
		if warmup_identity_enabled:
			var phase := "warmup" if now-started < 10000000 else ("boundary" if sample_started == 0 else "measurement")
			# Fecha antes de apply_load; os disparos deste quadro pertencem ao próximo intervalo.
			capture_identity_interval(now,previous,phase)
		previous = now
		apply_load(now)
		if now >= next_state:
			next_state = now+1000000
			var row := state()
			row["t"] = (now-started)/1000000.0
			states.append(row)
		if world.session.modal or not world.session.state.place_id.is_empty() or world.gameplay.health <= 0:
			invalid = "Player state interrupted"
			break
		if now-started < 10000000: warm.append(ms); continue
		if sample_started == 0:
			sample_started = now
			if profile:
				EngineDebugger.profiler_enable("servers",true,[256,true])
				profile_started = true
			# Este intervalo cruzou o limite do aquecimento e vem antes do profiler.
			continue
		frames.append(ms)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		process_cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if DisplayServer.window_is_focused(): focused += 1
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: minimized_frames += 1
		if now-sample_started >= seconds*1000000: break
	var presentation_failure: String = native_presentation.finish(Time.get_ticks_usec())
	if not presentation_failure.is_empty(): invalid = presentation_failure
	if profile_started: EngineDebugger.profiler_enable("servers",false)
	if warmup_identity_enabled and identity_intervals.is_empty():
		invalid = "warmup_identity_no_intervals"
		push_error("WarmUp identity diagnostic requested but no intervals were captured")
	if focused != frames.size(): invalid = "measurement_lost_focus"
	if minimized_frames > 0: invalid = "measurement_minimized"
	var report := {"label":label,"scenario":scenario,"invalid":invalid,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"gpu_ms":metric_stats(gpu,"ms"),"render_cpu_ms":metric_stats(render_cpu,"ms"),"physics_monitor_ms":metric_stats(physics,"ms"),"process_monitor_ms":metric_stats(process_cpu,"ms"),"draw_calls":metric_stats(draws,"draw_calls"),"states":states,"shots":shots,"focused_frames":focused,"startup_seconds":(started-initialized_at)/1000000.0-settling_seconds,"settling_seconds":settling_seconds,"settling_states":settling_states,"settled_state":settled_state,"configuration":{"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"physics_hz":Engine.physics_ticks_per_second,"max_physics_steps":Engine.max_physics_steps_per_frame,"profile":profile,"low_processor_usage_mode":OS.low_processor_usage_mode,"no_save":world.production.no_save,"global_seed":21092026},"scope":"Rendered Main production scene; stationary teleport fixture; live NPCs/traffic. Start requires population/ambient-traffic caps plus idle streaming and retirement; later fluctuations remain normal gameplay and are recorded. Chaos uses godmode, arsenal and direct fire API after settling. CPU/GPU render timings are root viewport only. TIME_PROCESS and TIME_PHYSICS_PROCESS are last-second maxima repeated by frame sampling, not mean CPU per frame/physics step. Global seed does not make asynchronous gameplay deterministic. No manual callback adoption."}
	report["minimized_frames"] = minimized_frames
	report["native_presentation"] = native_presentation.snapshot()
	report["clock"] = {"initialized_usec":initialized_at,"scenario_start_usec":started,
		"measurement_start_usec":sample_started,"measurement_end_usec":previous}
	report["warmup_identity"] = {"enabled":warmup_identity_enabled}
	if warmup_identity_enabled:
		report["warmup_identity"].merge({"intervals":identity_intervals,"max_intervals":MAX_IDENTITY_INTERVALS,
			"max_warmups_per_interval":MAX_IDENTITY_WARMUPS,"dropped_intervals":identity_dropped_intervals,
			"dropped_warmups":identity_dropped_warmups,
			"unclosed_tail_warmups":identity_warmups.size(),"unclosed_tail_dropped_warmups":identity_interval_dropped,
			"scope":"Opt-in identity/pipeline/render-signal observer during warmup and measurement; zero WarmUp events is valid. Detects verified vehicle visual children at the exact prewarm position/material/shadow contract, independent of auto-renamed siblings. Draw fields are last observed signals; invalid pairs do not imply duration. Timestamps are wall time, not exclusive CPU/GPU; counters do not attribute compilation duration. Observer cost is included; compare clean FPS with observer disabled."})
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("PERFORMANCE_PLAN ",JSON.stringify({"summary":report.summary,"gpu":report.gpu_ms,"cpu_render":report.render_cpu_ms,"physics":report.physics_monitor_ms,"state":state(),"invalid":invalid}))
	quit(0 if invalid.is_empty() else 1)
