extends SceneTree
## SERIAL rendered comparison, never headless. Run baseline and candidate with
## identical arguments/hardware except --north-gateway-baseline. --completed
## selects the completed checkpoint in BOTH runs. Require --benchmark --no-save.
## The player follows the same existing dry land between the old lanes; baseline
## never relies on the new bridge, shoreline opening, or new collision geometry.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const POLICY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const START := Vector3(375.0,.12,-248.0)
const FINISH := START
const VIEW_FOCUS := Vector3(350.0,2.4,-310.0)
const WARMUP_SECONDS := 10.0
const MEASURE_SECONDS := 30.0
var world
var output := ""
var save_path := ""
var baseline := false
var completed := false
var phase := "idle"
var previous := 0
var phase_started := 0
var started := 0
var startup_ms := 0.0
var sections := {"startup":[],"warmup":[],"approach":[],"steady":[]}
var cpu: Array[float] = []
var physics: Array[float] = []
var population: Array[Dictionary] = []
var population_clock := 0.0
var distance_started := 0.0
var measured_distance := 0.0
var errors: Array[String] = []
var fingerprint_started: Dictionary = {}
var diagnostics: Array[Dictionary] = []
var presteady_costs: Array = []
var steady_started_usec := 0

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("NORTH_GATEWAY benchmark timeout; no performance approval"); quit(3))
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--benchmark" not in args or "--no-save" not in args:
		push_error("Rendered benchmark requires --benchmark --no-save; run .NET build serially after coordination.")
		quit(2)
		return
	if not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("HARBOR_NO_CSHARP fallback cannot be used for the .NET comparison.")
		quit(2)
		return
	baseline = POLICY.baseline_disabled()
	completed = "--completed" in args
	seed(5102026)
	fingerprint_started = FIXTURE.source_fingerprint()
	output = FIXTURE.output_dir("desert-gateway-static-%s-%s"%["baseline" if baseline else "candidate","complete" if completed else "works"])
	save_path = FIXTURE.write_fixture(output,"checkpoint.json",FIXTURE.full_snapshot(START,completed))
	if save_path.is_empty(): fail("isolated fixture creation failed"); return
	root.size = Vector2i(1280,720)
	started = Time.get_ticks_usec()
	previous = started
	phase_started = started
	phase = "startup"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("benchmark_trace",true)
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	for index in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled:
		fail("real Main never became ready with settled startup streaming")
		return
	if not world.production.no_save or not world.production.loaded_save or world.production.save_invalid or world.production.store.path!=save_path:
		fail("save isolation was not honored by production")
		return
	var gateway = get_first_node_in_group("north_gateway")
	if baseline and is_instance_valid(gateway): fail("baseline unexpectedly installed gateway"); return
	if not baseline and (not is_instance_valid(gateway) or not gateway.is_mounted() or gateway.completed!=completed):
		fail("candidate did not install and mount requested bridge state")
		return
	var edge: Dictionary = world.dispatch.router.nearest_edge(START)
	if edge.is_empty() or world.dispatch.router._native==null:
		fail("compiled .NET route backend unavailable")
		return
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	# An identical fixed overview makes workers, gap and completed deck visible
	# while streaming/population keep their actual focus on the physical player.
	world.camera.set_process(false)
	world.camera.global_position = VIEW_FOCUS+Vector3(0,35,35)
	world.camera.look_at(VIEW_FOCUS)
	world.camera.size = 62.0
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600.0
	world.session.weather._update()
	distance_started = world.player.travelled
	startup_ms = float(Time.get_ticks_usec()-started)/1000.0
	change_phase("warmup")

func _process(delta: float) -> bool:
	if phase in ["idle","finished"]: return false
	var now := Time.get_ticks_usec()
	sections[phase].append(float(now-previous)/1000.0)
	previous = now
	if phase=="startup": return false
	population_clock += delta
	if population_clock>=1.0:
		population_clock = 0.0
		population.append({"phase":phase,"seconds":float(now-started)/1000000.0,"people":world.people.size(),"vehicles":world.production.vehicles.size(),"dispatch_units":world.dispatch.units.size(),"player_position":str(world.player.global_position)})
		_collect_diagnostics(now)
	var elapsed := float(now-phase_started)/1000000.0
	match phase:
		"warmup":
			if elapsed>=WARMUP_SECONDS: change_phase("approach")
		"approach":
			var direction: Vector3 = FINISH-world.player.global_position
			direction.y = 0
			world.player.automatic_direction = direction.normalized()
			if direction.length()<.35:
				world.player.automatic_direction = Vector3.ZERO
				measured_distance = world.player.travelled-distance_started
				change_phase("steady")
			elif elapsed>=15.0:
				fail.call_deferred("physical common approach did not finish; baseline and candidate are not comparable")
				phase = "finished"
		"steady":
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
			if elapsed>=MEASURE_SECONDS:
				phase = "finished"
				finish.call_deferred()
	return false

func change_phase(next: String) -> void:
	if next == "steady":
		# Startup uses the same bounded trace buffer. Keep it separately so the
		# 512-entry cap cannot hide the steady-state work being investigated.
		presteady_costs = world.get_meta("perf_costs",[]).duplicate(true)
		world.set_meta("perf_costs",[])
	phase = next
	phase_started = Time.get_ticks_usec()
	previous = phase_started
	if next == "steady": steady_started_usec = phase_started

func _collect_diagnostics(now: int) -> void:
	var began := Time.get_ticks_usec()
	var regions: Dictionary = {}
	for id in world.production.regions:
		var region: Node3D = world.production.regions[id]
		if not is_instance_valid(region): continue
		var row := {"instance_id":region.get_instance_id(),"chunks":region.chunks.size(),"pending":region.pending.size(),"build_jobs":region.build_jobs.size(),"cell":str(region.current_cell),"support_cells":region.vehicle_support_cells.size()}
		if id == "desert":
			row["chunk_keys"] = str(region.chunks.keys())
			row["ambient_visible"] = is_instance_valid(region.ambient) and region.ambient.visible
			row["ambient_physics"] = is_instance_valid(region.ambient) and region.ambient.is_physics_processing()
		regions[id] = row
	var vehicle_models: Dictionary = {}
	var vehicle_rows: Array[Dictionary] = []
	for vehicle in world.production.vehicles:
		if not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion(): continue
		var model: String = vehicle.archetype
		vehicle_models[model] = int(vehicle_models.get(model,0))+1
		vehicle_rows.append({"id":vehicle.vehicle_id,"model":model,"position":str(vehicle.global_position),"traffic":vehicle.traffic,"physics":vehicle.is_physics_processing(),"desert_powertrain":vehicle.has_meta("desert_powertrain")})
	var graphs: Dictionary = {}
	for id in ["traffic_routes","ambient_traffic_routes"]:
		var graph: Variant = world.production.get(id)
		if graph == null: continue
		var edge_count := 0
		for outgoing in graph.edges.values(): edge_count += outgoing.size()
		graphs[id] = {"segments":graph.segments.size(),"vertices":graph.vertices.size(),"edges":edge_count}
	diagnostics.append({
		"phase":phase,"seconds":float(now-started)/1000000.0,"phase_seconds":float(now-phase_started)/1000000.0,
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"physics_active_objects":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_collision_pairs":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"cpu_monitor_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_monitor_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"node_count":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"regions":regions,"graphs":graphs,"vehicle_models":vehicle_models,"vehicle_rows":vehicle_rows,
		"modal":world.session.modal,"capture_usec":Time.get_ticks_usec()-began})

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		total += float(value)
		if value>33.3: over33 += 1
		if value>66.7: over66 += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":float(values.size())*1000.0/maxf(total,.001),"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":over33,"over_66_7_ms":over66}

func fail(reason: String) -> void:
	errors.append(reason)
	push_error("NORTH_GATEWAY_BENCHMARK "+reason)
	phase = "finished"
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("failure.json"),FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify({"errors":errors,"sections_ms":sections,"source_sha256_start":fingerprint_started,"source_sha256_end":FIXTURE.source_fingerprint(),"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args()},"\t"))
	quit(1)

func finish() -> void:
	world.player.automatic_direction = Vector3.ZERO
	var gate = get_first_node_in_group("north_gateway")
	var fingerprint_ended := FIXTURE.source_fingerprint()
	if fingerprint_started!=fingerprint_ended: errors.append("Source changed during measurement; comparison invalid.")
	var report := {
		"scenario":"desert_gateway_stationary_overview_v1","baseline":baseline,"completed":completed,
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"cpu":OS.get_processor_name(),"os":OS.get_name(),"os_version":OS.get_version(),"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),
		"source_sha256_start":fingerprint_started,"source_sha256_end":fingerprint_ended,"source_stable":fingerprint_started==fingerprint_ended,
		"resolution":str(root.size),"window_size":str(DisplayServer.window_get_size()),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,
		"seed":5102026,"time_of_day":world.session.weather.time_of_day,"weather":world.session.weather.weather_state,
		"requested_population":world.production.requested_population,"population_samples":population,
		"diagnostic_samples":diagnostics,"perf_costs_presteady":presteady_costs,"perf_costs_steady":world.get_meta("perf_costs",[]).duplicate(true),"steady_started_usec":steady_started_usec,
		"trace_enabled":true,"trace_threshold_usec":2000,"trace_capacity":512,"trace_steady_saturated":world.get_meta("perf_costs",[]).size()>=512,
		"diagnostic_notes":"One sample per second; capture_usec records fixture overhead. Existing production trace records only instrumented operations >=2ms, so missing entries do not prove zero cost. Performance CPU/physics monitors are low-frequency snapshots repeated by the original per-frame arrays; use frame_intervals_ms for actual frame timing, not summed monitor values.",
		"frame_intervals_ms":sections,"summary":stats(sections.steady),"startup":stats(sections.startup),"warmup":stats(sections.warmup),"approach":stats(sections.approach),
		"cpu_process":stats(cpu),"physics":stats(physics),"cpu_ms":cpu,"physics_ms":physics,"startup_ms":startup_ms,
		"player_start":str(START),"player_finish":str(world.player.global_position),"player_distance":measured_distance,"camera_focus":str(VIEW_FOCUS),"camera_size":world.camera.size,
		"gateway_mounted":is_instance_valid(gate) and gate.is_mounted(),"workers_active":is_instance_valid(gate) and is_instance_valid(gate.workers) and gate.workers.is_processing(),
		"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"isolated_save":save_path,"errors":errors,
		"notes":"Real rendered Main/.NET, unchanged production population/render settings, fixed overview camera (does not validate normal gameplay camera), 10s warmup then >=30s stationary sample. Physical crossing is tested separately. First load measured separately. Only compare serial runs with matching settings, build and population; startup variance requires inspection. No global performance or temporal-lighting approval is implied. Screenshot is outside sampling; construction animation needs visual temporal review."
	}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("overview.png"))
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: fail("cannot write benchmark report"); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("NORTH_GATEWAY_BENCHMARK ",output," ",JSON.stringify(report.summary))
	quit(0 if errors.is_empty() else 1)
