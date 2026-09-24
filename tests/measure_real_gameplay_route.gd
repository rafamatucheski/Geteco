extends SceneTree

## Benchmark renderizado do fluxo que o jogador realmente executa:
## HarborGame -> caminhar por input -> entrar com [E] -> dirigir por input.
##
## Este arquivo deliberadamente nao chama HarborPreview._drive(), nao escreve
## global_position/position/rotation/velocity de ator algum e nao desliga
## trafego, populacao, policia, fisica, streaming ou apresentacoes.
##
## Execucao renderizada (PowerShell):
## & $godot --path D:/geteco/game --audio-driver Dummy `
##   --script res://tests/measure_real_gameplay_route.gd -- `
##   scenario=normal out_dir=D:/geteco/artifacts/real-route-normal --capture
## & $godot --path D:/geteco/game --audio-driver Dummy `
##   --script res://tests/measure_real_gameplay_route.gd -- `
##   scenario=chaos out_dir=D:/geteco/artifacts/real-route-chaos --night --rain --capture
##
## Parse/contrato apenas (nao mede FPS):
## & $godot --headless --path D:/geteco/game `
##   --script res://tests/measure_real_gameplay_route.gd -- --validate-only

const GAME_PATH := "res://world/harbor/HarborGame.tscn"
const CONNECTOR_PATH := "res://world/harbor/HarborMountainConnector.gd"
const SCHEDULER_PATH := "res://systems/RuntimeWorkScheduler.gd"
const VEHICLE_CACHE_PATH := "res://cars/VehicleGeometryCache.gd"
const ROUTE_SCRIPT_PATH := "res://tests/measure_real_gameplay_route.gd"

const WALK_TIMEOUT_SECONDS := 45.0
const DRIVE_TIMEOUT_SECONDS := 180.0
const BOARDING_TIMEOUT_SECONDS := 6.0
const WALK_TOLERANCE := 15.0
const DRIVE_TOLERANCE := 95.0
const WALK_MAX_PHYSICS_STEP := 38.0
const DRIVE_MAX_PHYSICS_STEP := 95.0
const MAX_ROUTE_STOP_MS := 8000.0
const MIN_DRIVE_DISTANCE := 6500.0
const MIN_DRIVE_MOVING_FRACTION := 0.60
const POLICE_REFRESH_SECONDS := 14.0
const DRIVE_STUCK_RECOVERY_MSEC := 1800
const DRIVE_REVERSE_RECOVERY_MSEC := 850
const DRIVE_FORWARD_RECOVERY_MSEC := 750
const REPLACEMENT_SEARCH_RADIUS := 1400.0
const REPLACEMENT_BOARDING_TIMEOUT_SECONDS := 8.0
const MAX_INPUT_WAYPOINT_GAP := 1500.0
const TELEMETRY_SAMPLE_FRAMES := 15
const SCHEDULER_BUDGET_USEC := 6000
const MAX_AVG_FRAME_MS := 16.67
const MAX_P95_FRAME_MS := 16.67
const MAX_P99_FRAME_MS := 33.3
const MAX_SINGLE_FRAME_MS := 50.0
const MAX_CORRELATION_SAMPLES := 32768
const MAX_REPORT_COLLECTION_ITEMS := 512
const MAX_REPORT_DICTIONARY_KEYS := 256
const MAX_REPORT_DEPTH := 8
const STARTUP_TIMEOUT_MSEC := 120000
const DEFAULT_STALL_THRESHOLD_MS := 100.0
const MAX_STALL_TRACES := 32

var _city_drive_waypoints := PackedVector2Array([
	Vector2(565, 2140),
	Vector2(700, 2170),
	Vector2(1300, 2170),
	Vector2(2150, 2170),
	Vector2(2930, 2170),
	Vector2(2930, 1300),
	Vector2(2930, 470),
	Vector2(2930, 370),
	# Foundry Avenue's authored eastbound lane is y=370. Driving east at y=430
	# puts the fixture against westbound traffic and previously trapped it near
	# x=3250; keep normal collisions and use the correct lane instead.
	Vector2(3800, 370),
	Vector2(4600, 370),
	Vector2(5500, 370),
	Vector2(6380, 370),
	Vector2(6380, -900),
	Vector2(6380, -1880),
	Vector2(6150, -1940),
	Vector2(6150, -3000),
	Vector2(6150, -4080),
])

var _output := ""
var _game_scene: PackedScene
var _connector_script: Variant
var _scheduler_script: Variant
var _vehicle_cache_script: Variant
var _scenario_world: Node
var _scenario_hour := 0.45
var _stall_threshold_ms := DEFAULT_STALL_THRESHOLD_MS
var _trace_stall_events := false
var _profile_views: Array[Viewport] = []
var _profile_last_ms := 0
var _tree_event_serial := 0
var _recent_tree_events: Array[Dictionary] = []
var _csv: FileAccess
var _stall_file: FileAccess
var _samples: Array[float] = []
var _phase_stats: Dictionary = {}
var _failures: Array[String] = []
var _teleport_events: Array[Dictionary] = []
var _previous_frame_usec := 0
var _previous_metrics: Dictionary = {}
var _previous_physics_frame := 0
var _frame_index := 0
var _stall_count := 0
var _stall_traces := 0
var _over_16 := 0
var _over_33 := 0
var _over_50 := 0
var _over_66 := 0
var _focused_frames := 0
var _focus_transitions := 0
var _previous_focus := true
var _police_peak := 0
var _traffic_peak := 0
var _wanted_peak := 0
var _population_peak := 0
var _police_sum := 0
var _traffic_sum := 0
var _population_sum := 0
var _actor_count_samples := 0
var _driving_actor_samples := 0
var _driving_wanted_required_samples := 0
var _drive_waypoint_index := 0
var _waypoint_arrivals: Array[Dictionary] = []
var _route_completed := false
var _boarding_completed := false
var _walk_start := Vector2.ZERO
var _walk_end := Vector2.ZERO
var _walk_required_distance := 0.0
var _walk_detours := 0
var _drive_recovery_count := 0
var _vehicle_replacement_count := 0
var _drive_recovery_events: Array[Dictionary] = []
var _physics_guard_subject: Node2D
var _physics_guard_previous := Vector2.ZERO
var _physics_guard_phase := ""
var _physics_guard_limit := INF
var _physics_guard_armed := false
var _physics_guard_max_step := 0.0
var _last_police_refresh_ms := 0
var _traffic_probe := RectangleShape2D.new()
var _motion_contract_failed := false
var _scenario_mode := ""
var _requested_wanted_level := 0
var _physical_transition: Dictionary = {}
# Keep correlation data in packed/typed series. A Dictionary per gameplay frame
# noticeably changes the memory profile of a multi-minute route, while scheduler
# jobs only need an exact lookup after the run.
var _sample_engine_frames := PackedInt64Array()
var _sample_route_frames := PackedInt64Array()
var _sample_frame_ms := PackedFloat64Array()
var _sample_phases: Array[String] = []
var _sample_waypoints := PackedInt32Array()
var _sample_positions: Array[Vector2] = []
var _sample_police := PackedInt32Array()
var _sample_traffic := PackedInt32Array()
var _sample_population := PackedInt32Array()
var _sample_wanted := PackedInt32Array()
var _correlation_next_index := 0
var _correlation_overwrites := 0
var _scheduler_baseline_ids: Dictionary = {}
var _cache_baseline: Dictionary = {}
var _unique_deaths: Dictionary = {}
var _unique_corpses: Dictionary = {}
var _unique_blood: Dictionary = {}
var _dead_peak := 0
var _corpse_peak := 0
var _blood_peak := 0
var _memory_start_bytes := 0
var _memory_peak_bytes := 0
var _video_memory_peak_bytes := 0
var _subviewport_peak: Dictionary = {}
var _subviewport_latest: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_trace_stall_events = args.has("--trace-stalls")
	if args.has("--validate-only"):
		_validate_only()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Real gameplay route requires a real renderer; use --validate-only only for headless parsing")
		quit(1)
		return
	_scenario_mode = _scenario_from_args(args)
	if not _validate_scenario_args(args, _scenario_mode):
		quit(1)
		return
	_game_scene = load(GAME_PATH) as PackedScene
	_connector_script = load(CONNECTOR_PATH)
	_scheduler_script = load(SCHEDULER_PATH)
	_vehicle_cache_script = load(VEHICLE_CACHE_PATH)
	if _game_scene == null or _connector_script == null or _scheduler_script == null or _vehicle_cache_script == null:
		_fail("Rendered route could not load one or more production resources")
		quit(1)
		return
	var forbidden_motion_writes := _forbidden_motion_write_findings()
	if not forbidden_motion_writes.is_empty():
		for finding in forbidden_motion_writes:
			_fail("Route source contains forbidden actor repositioning: " + finding)
		quit(1)
		return
	_requested_wanted_level = 4 if _scenario_mode == "chaos" else 2

	_output = ProjectSettings.globalize_path("user://tests/real-gameplay-route")
	for arg in args:
		if arg.begins_with("out_dir="):
			_output = arg.trim_prefix("out_dir=")
		elif arg.begins_with("stall_threshold_ms="):
			_stall_threshold_ms = maxf(16.67, float(arg.trim_prefix("stall_threshold_ms=")))
	if DirAccess.make_dir_recursive_absolute(_output.path_join("saves")) != OK:
		_fail("Cannot create benchmark output: " + _output)
		quit(1)
		return

	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", _output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(19092026)
	root.size = Vector2i(1280, 720)
	for arg in args:
		if arg.begins_with("resolution="):
			var dimensions := arg.trim_prefix("resolution=").split("x")
			if dimensions.size() == 2:
				root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	root.content_scale_size = Vector2i(1280, 720)
	if not args.has("--normal-cap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0

	# A free-roam campaign fixture avoids the arrival cinematic, but does not
	# alter the world simulation or move either playable actor after scene load.
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [
		&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met",
		&"harbor_delivery_started", &"harbor_delivery_picked_up", &"harbor_delivery_complete",
	]:
		campaign.set_campaign_flag(flag, true)

	var world := _game_scene.instantiate()
	root.add_child(world)
	current_scene = world
	_scenario_world = world
	var startup_deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < startup_deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		_fail("HarborGame did not reach its normal playable state")
		await _finish(world)
		return

	var player := world.get_node("Player") as CharacterBody2D
	var car := world.get_node("PlayerCar") as CharacterBody2D
	if player == null or car == null or not player.visible or not player.is_physics_processing():
		_fail("Player or PlayerCar is unavailable after normal HarborGame startup")
		await _finish(world)
		return
	if car.get("is_driven_by_player") == true:
		_fail("PlayerCar started already occupied; normal boarding cannot be measured")
		await _finish(world)
		return

	_scenario_hour = 0.90 if _scenario_mode == "chaos" else 0.45
	world.weather.is_dynamic_time = true
	_hold_scenario_clock()
	world.weather.set_biome(world.weather.current_biome)
	world.weather.set_weather(1 if _scenario_mode == "chaos" else 0)
	world.weather.weather_timer = 1000000.0
	if args.has("--profile-render"):
		_collect_profile_views(root)

	if not _open_measurement_files():
		await _finish(world)
		return
	_cache_baseline = _vehicle_cache_script.telemetry()
	_capture_scheduler_baseline()
	_memory_start_bytes = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_memory_peak_bytes = _memory_start_bytes
	_sample_extended_state()
	if _trace_stall_events:
		node_added.connect(_record_tree_event.bind("add"))
		node_removed.connect(_record_tree_event.bind("remove"))
	physics_frame.connect(_audit_physics_step)

	_walk_start = player.global_position
	var door_target := car.to_global(Vector2(0, -48))
	_walk_required_distance = _walk_start.distance_to(door_target)
	print("REAL_ROUTE start_player=%s parked_car=%s door=%s" % [_walk_start, car.global_position, door_target])
	var walk_route := _walk_route_for(_walk_start, door_target)
	_set_physics_guard(player, "walking", WALK_MAX_PHYSICS_STEP)
	var walked := await _walk_path(player, walk_route)
	_walk_end = player.global_position
	_release_motion()
	if not walked:
		_fail("Walking route did not reach the parked car using movement input")
	if player.global_position.distance_to(car.global_position) >= 80.0:
		_fail("Player is outside the normal vehicle interaction radius")

	_set_physics_guard(null, "boarding", INF)
	await _tap_key(KEY_E, "boarding", player)
	var boarding_deadline := Time.get_ticks_msec() + int(BOARDING_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < boarding_deadline:
		await process_frame
		_record_frame("boarding", car if car.is_driven_by_player else player)
		if car.is_driven_by_player and not car.has_meta("vehicle_boarding"):
			_boarding_completed = true
			break
	if not _boarding_completed:
		_fail("Normal interact input did not complete VehicleBoarding")
		await _finish(world)
		return
	if player.visible or player.is_physics_processing():
		_fail("Boarding completed with the pedestrian still active")

	# Release every movement action once so PlayerCar's normal input arming can
	# observe neutral controls. No direct controller call is used.
	_release_motion()
	for _i in 3:
		await process_frame
		_record_frame("boarding", car)

	var wanted := root.get_node("WantedManager")
	wanted.ensure_minimum_wanted_level(_requested_wanted_level)
	_last_police_refresh_ms = Time.get_ticks_msec()
	_traffic_probe.size = Vector2(260.0, 44.0)
	var drive_route := _build_drive_route()
	var waypoint_failures := _validate_waypoint_contract(drive_route, car.global_position)
	for failure in waypoint_failures:
		_fail(failure)
	if not waypoint_failures.is_empty():
		await _finish(world)
		return
	_set_physics_guard(car, "driving", DRIVE_MAX_PHYSICS_STEP)
	_route_completed = await _drive_path(car, drive_route, wanted, _requested_wanted_level)
	_release_motion()
	if not _route_completed:
		_fail("Input-driven route did not reach the Harbor/Mountain seam")

	var stream := world.get_node_or_null("ContinuousWorld")
	if stream == null or not bool(stream.get("ready_for_crossing")):
		_fail("ContinuousWorld did not prepare the next region during the real drive")
	elif String(stream.get("current_region")) != "mountain":
		_fail("Route ended without crossing into the mountain region")
	if _police_peak < 1:
		_fail("No live police vehicle joined the route")
	if _traffic_peak < 1:
		_fail("No production traffic was present during the route")
	if _population_peak < 1:
		_fail("No production population was present during the route")
	if _wanted_peak < _requested_wanted_level:
		_fail("Wanted level never reached the required scenario level %d" % _requested_wanted_level)
	if _physical_transition.is_empty():
		_fail("No physical Harbor-to-Mountain transition was observed while driving")

	_validate_motion_contracts()
	if args.has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("real_route_end.png"))
	await _finish(world)


func _scenario_from_args(args: PackedStringArray) -> String:
	var selected := ""
	for argument in args:
		if not argument.begins_with("scenario="):
			continue
		if not selected.is_empty():
			return "duplicate"
		selected = argument.trim_prefix("scenario=")
	return selected


func _validate_scenario_args(args: PackedStringArray, scenario: String) -> bool:
	if scenario not in ["normal", "chaos"]:
		_fail("Rendered route requires exactly one scenario=normal or scenario=chaos argument")
		return false
	if args.has("--chaos"):
		_fail("Legacy --chaos is rejected; use a separate scenario=chaos execution")
	if scenario == "normal" and (args.has("--night") or args.has("--rain")):
		_fail("Normal wanted-2 passage must run in its distinct day/dry scenario")
	if scenario == "chaos" and (not args.has("--night") or not args.has("--rain")):
		_fail("Chaos wanted-4 passage requires both --night and --rain")
	return _failures.is_empty()


func _hold_scenario_clock() -> void:
	if not is_instance_valid(_scenario_world):
		return
	var bridge := _scenario_world.get_node_or_null("CobraCampaign")
	if bridge != null and bridge.ledger != null:
		bridge.ledger.data.day_elapsed = fposmod(_scenario_hour - 0.35, 1.0) * 600.0
	_scenario_world.weather.time_of_day = _scenario_hour


func _collect_profile_views(node: Node) -> void:
	if node is Viewport and (node == root or OS.get_cmdline_user_args().has("--profile-all-views")):
		_profile_views.append(node)
		RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(), true)
	for child in node.get_children():
		_collect_profile_views(child)


func _report_render() -> void:
	if _profile_views.is_empty() or Time.get_ticks_msec() - _profile_last_ms < 1000:
		return
	_profile_last_ms = Time.get_ticks_msec()
	var rows: Array[Dictionary] = []
	for view in _profile_views:
		if not is_instance_valid(view):
			continue
		if view is SubViewport and view.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			continue
		var rid := view.get_viewport_rid()
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if cpu > 0.1 or gpu > 0.1:
			rows.append({"path": str(view.get_path()), "cpu_ms": cpu, "gpu_ms": gpu})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.cpu_ms) + float(a.gpu_ms) > float(b.cpu_ms) + float(b.gpu_ms)
	)
	print("RENDER_BREAKDOWN ", JSON.stringify(rows.slice(0, 12)))


func _sample_subject_state(subject: Node2D) -> Dictionary:
	var state := {
		"path": str(subject.get_path()),
		"position": str(subject.global_position),
		"rotation": subject.global_rotation,
		"paused": paused,
		"can_process": subject.can_process(),
	}
	if subject is CharacterBody2D:
		state["velocity"] = str(subject.velocity)
		state["speed"] = subject.velocity.length()
	return state


func _frame_metrics_snapshot(presentation_budget: Node = null, known: Dictionary = {}) -> Dictionary:
	if presentation_budget == null:
		presentation_budget = root.get_node_or_null("PresentationBudget")
	var presentation_stats: Dictionary = presentation_budget.get("_stats") if presentation_budget != null else {}
	var vehicle_cache: Dictionary = _vehicle_cache_script.telemetry() if _vehicle_cache_script != null else {}
	return {
		"object_count": known.get("object_count", Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": known.get("node_count", Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resource_count": known.get("resource_count", Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"video_mem_mb": known.get("video_mem_mb", Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"physics_active": known.get("physics_active", Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"physics_pairs": known.get("physics_pairs", Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"draw_calls": known.get("draw_calls", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"presentation_pending": int(presentation_budget.pending.size()) if presentation_budget != null else 0,
		"presentation_requests": int(presentation_stats.get("requests", 0)),
		"presentation_builds": int(presentation_stats.get("builds", 0)),
		"presentation_cancelled": int(presentation_stats.get("cancelled", 0)),
		"presentation_over_budget": int(presentation_stats.get("over_budget_builds", 0)),
		"presentation_max_build_usec": int(presentation_stats.get("max_build_usec", 0)),
		"vehicle_cache_hits": int(vehicle_cache.get("hits", 0)),
		"vehicle_cache_misses": int(vehicle_cache.get("misses", 0)),
		"vehicle_cache_captures": int(vehicle_cache.get("captures", 0)),
		"vehicle_cache_restore_usec": int(vehicle_cache.get("restore_usec", 0)),
		"vehicle_cache_capture_usec": int(vehicle_cache.get("capture_usec", 0)),
		"vehicle_cache_cold_builds": int(vehicle_cache.get("cold_builds", 0)),
		"vehicle_cache_cold_build_usec": int(vehicle_cache.get("cold_build_usec", 0)),
		"tree_event_serial": _tree_event_serial,
	}


func _numeric_delta(previous: Dictionary, current: Dictionary) -> Dictionary:
	var delta := {}
	for key in current:
		if current[key] is int or current[key] is float:
			delta[key] = current[key] - previous.get(key, current[key])
	return delta


func _stall_details(
	label: String,
	frame_index: int,
	elapsed_ms: float,
	frame_ms: float,
	physics_steps: int,
	subject: Node2D,
	previous: Dictionary,
	current: Dictionary
) -> Dictionary:
	var details := {
		"scenario": label,
		"frame_index": frame_index,
		"elapsed_ms": elapsed_ms,
		"frame_ms": frame_ms,
		"physics_steps": physics_steps,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"subject": _sample_subject_state(subject),
		"metrics": current,
		"delta": _numeric_delta(previous, current),
		"groups": _stall_group_counts(),
		"tree_events_since_previous_frame": _tree_events_after(int(previous.get("tree_event_serial", 0))),
		"vehicle_geometry_cache": _vehicle_cache_script.telemetry(),
		"static_memory_mb": OS.get_static_memory_usage() / 1048576.0,
	}
	var presentation_budget := root.get_node_or_null("PresentationBudget")
	if presentation_budget != null:
		details["presentation"] = presentation_budget.get_stats()
		details["presentation_pending_sample"] = _pending_presentation_sample(presentation_budget, subject.global_position)
	if is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null:
			details["streaming"] = stream.get_streaming_stats()
	var wanted := root.get_node_or_null("WantedManager")
	if wanted != null:
		details["wanted"] = {"stars": wanted.current_stars, "crime_points": wanted.crime_points}
	print("FRAME_STALL ", JSON.stringify(_bounded_report_value(details)))
	return details


func _stall_group_counts() -> Dictionary:
	var counts := {}
	for group in [
		"modern_traffic", "vehicle", "motorcycle", "pedestrian", "authored_sidewalk_pedestrian",
		"emergency_vehicle", "police_officer", "paramedic", "firefighter", "medical_observer",
		"ground_blood", "explosives", "weapon_effects", "shot_contacts", "person_fire_visuals",
		"explosion_visuals", "explosion_remains", "explosion_scorches",
	]:
		counts[group] = get_nodes_in_group(group).size()
	return counts


func _pending_presentation_sample(presentation_budget: Node, focus: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending_value: Variant = presentation_budget.get("pending")
	if not pending_value is Array:
		return result
	for candidate in pending_value:
		if result.size() >= 12:
			break
		if not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		var actor := candidate as Node2D
		result.append({
			"path": str(actor.get_path()),
			"script": String(actor.get_script().resource_path) if actor.get_script() != null else "",
			"distance": actor.global_position.distance_to(focus),
			"visible": actor.is_visible_in_tree(),
			"sleeping": actor.get_meta("proximity_sleeping", false),
		})
	return result


func _record_tree_event(node: Node, operation: String) -> void:
	_tree_event_serial += 1
	var script_path := ""
	if is_instance_valid(node) and node.get_script() != null:
		script_path = String(node.get_script().resource_path)
	var event := {
		"serial": _tree_event_serial,
		"time_usec": Time.get_ticks_usec(),
		"operation": operation,
		"name": String(node.name) if is_instance_valid(node) else "",
		"class": node.get_class() if is_instance_valid(node) else "",
		"script": script_path,
		"parent": str(node.get_parent().get_path()) if is_instance_valid(node) and node.get_parent() != null else "",
	}
	if is_instance_valid(node) and node is Node2D:
		event["position"] = str((node as Node2D).global_position)
	_recent_tree_events.append(event)
	if _recent_tree_events.size() > 192:
		_recent_tree_events.pop_front()


func _tree_events_after(serial: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event in _recent_tree_events:
		if int(event.get("serial", 0)) > serial:
			events.append(event.duplicate())
	return events


func _forbidden_motion_write_findings() -> Array[String]:
	var findings: Array[String] = []
	var source := FileAccess.get_file_as_string(ROUTE_SCRIPT_PATH)
	if source.is_empty():
		findings.append("route source could not be read")
		return findings
	var expressions := [
		"\\.(global_position|position|global_rotation|rotation|velocity|linear_velocity)\\s*=",
		"\\.(set_global_position|set_position|set_global_rotation|set_rotation|set_velocity|set_linear_velocity)\\s*\\(",
		"\\.(teleport|warp|warp_to|reset_to|move_to)\\s*\\(",
		"set_deferred\\s*\\(\\s*[\"'](global_position|position|global_rotation|rotation|velocity|linear_velocity)[\"']",
	]
	var lines := source.split("\n")
	for expression in expressions:
		var regex := RegEx.new()
		if regex.compile(expression) != OK:
			findings.append("validator regex failed: " + expression)
			continue
		for index in lines.size():
			var line := String(lines[index])
			if regex.search(line) != null:
				findings.append("line %d: %s" % [index + 1, line.strip_edges()])
	return findings


func _walk_route_for(start: Vector2, door: Vector2) -> PackedVector2Array:
	# HarborGame currently exposes two legitimate starts depending on startup
	# flow: the authored scene position near the garage, or ArrivalSpawn after
	# campaign initialization. Select a street route from the observed position;
	# never normalize it by moving the player.
	if start.distance_to(door) < 520.0:
		return PackedVector2Array([
			Vector2(maxf(start.x, 715.0), 1935.0),
			door,
		])
	# Both Union Avenue sidewalks contain authored entrances/solids below Market
	# Street. Follow the open avenue axis to Dock Street, then enter the garage
	# apron from the south. Traffic remains physical and the input driver uses its
	# short lateral detour when a moving vehicle occupies the corridor.
	# These are normal walkable corridors; the benchmark still drives them only
	# through Player input and keeps the impossible-step guard armed.
	return PackedVector2Array([
		Vector2(1300.0, start.y),
		Vector2(1300.0, 2100.0),
		Vector2(715.0, 2100.0),
		Vector2(715.0, 1990.0),
		door,
	])


func _build_drive_route() -> PackedVector2Array:
	var result := _city_drive_waypoints.duplicate()
	var connector: PackedVector2Array = _connector_script.road_definitions()[0].points
	for index in range(0, connector.size(), 3):
		result.append(connector[index])
	if result[-1] != connector[-1]:
		result.append(connector[-1])
	# The seam is x=7300. A short continuation proves the selected region
	# changed without teleporting deep into the mountain.
	result.append(Vector2(7425.0, -4530.0))
	return result


func _build_contract_drive_route() -> PackedVector2Array:
	# Pure-data mirror of HarborMountainConnector's outbound centerline. This is
	# intentionally used only by --validate-only, so structural validation does
	# not load/reload/instantiate the playable runtime or query singleton state.
	var connector := PackedVector2Array()
	for index in range(25):
		connector.append(
			Vector2(6400.0, -4200.0)
			+ Vector2.from_angle(PI + PI * 0.5 * index / 24.0) * 280.0
		)
	for index in range(1, 25):
		var weight := float(index) / 24.0
		connector.append(Vector2(
			lerpf(6400.0, 7300.0, weight),
			lerpf(-4480.0, -4529.0, smoothstep(0.0, 1.0, weight))
		))
	var result := _city_drive_waypoints.duplicate()
	for index in range(0, connector.size(), 3):
		result.append(connector[index])
	if result[-1] != connector[-1]:
		result.append(connector[-1])
	result.append(Vector2(7425.0, -4530.0))
	return result


func _validate_waypoint_contract(route: PackedVector2Array, actual_start: Vector2) -> Array[String]:
	var failures: Array[String] = []
	if route.is_empty():
		failures.append("Input route contains no waypoints")
		return failures
	var previous := actual_start
	for index in route.size():
		var waypoint := route[index]
		if not waypoint.is_finite():
			failures.append("Waypoint %d is non-finite and cannot be reached by input" % index)
			continue
		var gap := previous.distance_to(waypoint)
		if gap > MAX_INPUT_WAYPOINT_GAP:
			failures.append(
				"Waypoint %d requires %.1f px discontinuity; repositioning is forbidden" % [index, gap]
			)
		previous = waypoint
	if route[-1].x <= 7300.0:
		failures.append("Input route does not physically cross the Harbor/Mountain seam")
	return failures


func _walk_path(player: CharacterBody2D, route: PackedVector2Array) -> bool:
	var index := 0
	var deadline := Time.get_ticks_msec() + int(WALK_TIMEOUT_SECONDS * 1000.0)
	var progress_position := player.global_position
	var last_progress_ms := Time.get_ticks_msec()
	var detour_until_ms := 0
	var detour_side := -1.0
	while index < route.size() and Time.get_ticks_msec() < deadline:
		if _motion_contract_failed:
			return false
		var delta := route[index] - player.global_position
		if delta.length() <= WALK_TOLERANCE:
			index += 1
			progress_position = player.global_position
			last_progress_ms = Time.get_ticks_msec()
			continue
		var direction := delta.normalized()
		var now_ms := Time.get_ticks_msec()
		if player.global_position.distance_to(progress_position) >= 8.0:
			progress_position = player.global_position
			last_progress_ms = now_ms
		elif now_ms - last_progress_ms >= 900:
			# A real player walks around a parked car, pedestrian or corner instead
			# of holding the same direction forever. Apply a short lateral input;
			# no transform, velocity or collision state is changed by the fixture.
			detour_side *= -1.0
			detour_until_ms = now_ms + 650
			last_progress_ms = now_ms
			_walk_detours += 1
		if now_ms < detour_until_ms:
			direction = (direction + direction.orthogonal() * detour_side * 0.85).normalized()
		_set_action(&"move_left", maxf(-direction.x, 0.0))
		_set_action(&"move_right", maxf(direction.x, 0.0))
		_set_action(&"move_up", maxf(-direction.y, 0.0))
		_set_action(&"move_down", maxf(direction.y, 0.0))
		Input.action_press(&"sprint")
		await process_frame
		_record_frame("walking", player)
	_release_motion()
	return index >= route.size()


func _drive_path(car: CharacterBody2D, route: PackedVector2Array, wanted: Node, police_level: int) -> bool:
	_drive_waypoint_index = 0
	var deadline := Time.get_ticks_msec() + int(DRIVE_TIMEOUT_SECONDS * 1000.0)
	var progress_position := car.global_position
	var last_progress_ms := Time.get_ticks_msec()
	var recovery_started_ms := 0
	var recovery_until_ms := 0
	var recovery_side := -1.0
	while _drive_waypoint_index < route.size() and Time.get_ticks_msec() < deadline:
		if _motion_contract_failed:
			return false
		if car.get("is_broken") == true or car.get("is_exploded") == true:
			var replacement := await _replace_destroyed_route_vehicle(car)
			if replacement == null:
				_fail("Driven vehicle was destroyed and no physical replacement could be boarded")
				return false
			car = replacement
			_set_physics_guard(car, "driving", DRIVE_MAX_PHYSICS_STEP)
			progress_position = car.global_position
			last_progress_ms = Time.get_ticks_msec()
			recovery_started_ms = 0
			recovery_until_ms = 0
			continue
		if car.get("is_driven_by_player") != true:
			_fail("Player lost normal control of the vehicle during the route")
			return false
		var target := route[_drive_waypoint_index]
		var to_target := target - car.global_position
		if to_target.length() <= DRIVE_TOLERANCE:
			_waypoint_arrivals.append({
				"index": _drive_waypoint_index,
				"engine_frame": Engine.get_process_frames(),
				"target": str(target),
				"actual_position": str(car.global_position),
				"distance_px": to_target.length(),
			})
			_drive_waypoint_index += 1
			progress_position = car.global_position
			last_progress_ms = Time.get_ticks_msec()
			recovery_started_ms = 0
			recovery_until_ms = 0
			continue
		var now_ms := Time.get_ticks_msec()
		if car.global_position.distance_to(progress_position) >= 32.0:
			progress_position = car.global_position
			last_progress_ms = now_ms
		elif recovery_until_ms <= now_ms and now_ms - last_progress_ms >= DRIVE_STUCK_RECOVERY_MSEC:
			recovery_side *= -1.0
			recovery_started_ms = now_ms
			recovery_until_ms = now_ms + DRIVE_REVERSE_RECOVERY_MSEC + DRIVE_FORWARD_RECOVERY_MSEC
			_drive_recovery_count += 1
			if _drive_recovery_events.size() < 32:
				_drive_recovery_events.append({
					"engine_frame": Engine.get_process_frames(),
					"waypoint": _drive_waypoint_index,
					"position": str(car.global_position),
					"target": str(target),
					"reason": "blocked_without_progress",
				})
		if recovery_until_ms > now_ms:
			var recovery_elapsed := now_ms - recovery_started_ms
			if recovery_elapsed < DRIVE_REVERSE_RECOVERY_MSEC:
				_set_action(&"move_left", maxf(-recovery_side, 0.0))
				_set_action(&"move_right", maxf(recovery_side, 0.0))
				_set_action(&"move_up", 0.0)
				_set_action(&"move_down", 1.0)
			else:
				_set_action(&"move_left", maxf(recovery_side, 0.0))
				_set_action(&"move_right", maxf(-recovery_side, 0.0))
				_set_action(&"move_up", 0.8)
				_set_action(&"move_down", 0.0)
			await process_frame
			_record_frame("driving", car)
			continue
		var angle_error := wrapf(to_target.angle() - car.global_rotation, -PI, PI)
		var steering := clampf(angle_error * 2.3, -1.0, 1.0)
		_set_action(&"move_left", maxf(-steering, 0.0))
		_set_action(&"move_right", maxf(steering, 0.0))
		var desired_speed := 155.0
		if absf(angle_error) > 0.75:
			desired_speed = 42.0
		elif absf(angle_error) > 0.35:
			desired_speed = 85.0
		if to_target.length() < 180.0:
			desired_speed = minf(desired_speed, 75.0)
		desired_speed = minf(desired_speed, _route_traffic_limited_speed(car))
		var forward_speed := car.velocity.dot(car.global_transform.x)
		_set_action(&"move_up", clampf((desired_speed - forward_speed) / 35.0, 0.0, 1.0))
		_set_action(&"move_down", 0.65 if forward_speed > desired_speed + 28.0 else 0.0)
		if Time.get_ticks_msec() - _last_police_refresh_ms >= int(POLICE_REFRESH_SECONDS * 1000.0):
			# Production API, severity zero once already at the requested level:
			# keeps the finite pursuit alive over the long regional drive without
			# spawning units directly or bypassing dispatch/pool limits.
			wanted.ensure_minimum_wanted_level(police_level)
			_last_police_refresh_ms = Time.get_ticks_msec()
		await process_frame
		_record_frame("driving", car)
	_release_motion()
	return _drive_waypoint_index >= route.size()


func _replace_destroyed_route_vehicle(previous_car: CharacterBody2D) -> CharacterBody2D:
	_release_motion()
	if previous_car.get("is_driven_by_player") == true:
		Input.action_press(&"exit_vehicle")
		for _frame in 3:
			await process_frame
			_record_frame("vehicle_recovery", previous_car)
		Input.action_release(&"exit_vehicle")
	var exit_deadline := Time.get_ticks_msec() + 6000
	while previous_car.get("is_driven_by_player") == true and Time.get_ticks_msec() < exit_deadline:
		await process_frame
		_record_frame("vehicle_recovery", previous_car)
	var player := get_first_node_in_group("player") as CharacterBody2D
	if not is_instance_valid(player) or not player.visible or not player.is_physics_processing():
		return null
	var replacement := _nearest_route_replacement(player.global_position, previous_car)
	if replacement == null:
		return null
	_set_physics_guard(player, "vehicle_recovery_walk", WALK_MAX_PHYSICS_STEP)
	var door_target := replacement.to_global(Vector2(0.0, -48.0))
	if not await _walk_path(player, PackedVector2Array([door_target])):
		return null
	_release_motion()
	if player.global_position.distance_to(replacement.global_position) >= 80.0:
		return null
	await _tap_key(KEY_E, "vehicle_recovery_boarding", player)
	var boarding_deadline := Time.get_ticks_msec() + int(REPLACEMENT_BOARDING_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < boarding_deadline:
		await process_frame
		_record_frame("vehicle_recovery_boarding", replacement if replacement.get("is_driven_by_player") == true else player)
		if replacement.get("is_driven_by_player") == true and not replacement.has_meta("vehicle_boarding"):
			_vehicle_replacement_count += 1
			return replacement
	return null


func _nearest_route_replacement(origin: Vector2, previous_car: CharacterBody2D) -> CharacterBody2D:
	var candidates: Array[Node] = []
	for group_name in [&"parked_vehicle", &"vehicle"]:
		for candidate in get_nodes_in_group(group_name):
			if not candidates.has(candidate):
				candidates.append(candidate)
	# Prefer an authored parked vehicle even when a temporarily stopped traffic
	# car is a few pixels closer. The latter can resume its lane while the player
	# walks toward it, which makes the recovery unlike a reasonable player choice.
	for parked_only in [true, false]:
		var best: CharacterBody2D
		var best_distance := REPLACEMENT_SEARCH_RADIUS
		for candidate_node in candidates:
			var candidate := candidate_node as CharacterBody2D
			if candidate == null or candidate == previous_car or not is_instance_valid(candidate):
				continue
			if candidate.is_in_group("parked_vehicle") != parked_only:
				continue
			if candidate.get("is_driven_by_player") == true or candidate.get("is_broken") == true or candidate.get("is_exploded") == true:
				continue
			if candidate.has_meta("vehicle_boarding") or candidate.is_in_group("emergency_vehicle"):
				continue
			var distance := origin.distance_to(candidate.global_position)
			if distance >= best_distance:
				continue
			var moving := Vector2.ZERO
			var velocity_value: Variant = candidate.get("velocity")
			if velocity_value is Vector2:
				moving = velocity_value
			if not parked_only and moving.length() > 8.0:
				continue
			best = candidate
			best_distance = distance
		if best != null:
			return best
	return null


func _route_traffic_limited_speed(car: CharacterBody2D) -> float:
	# The benchmark driver sees the same physical traffic a player sees and
	# follows its leader instead of driving through it or disabling collisions.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _traffic_probe
	query.transform = Transform2D(car.global_rotation, car.global_position + car.global_transform.x * 130.0)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [car.get_rid()]
	var nearest: CharacterBody2D
	var nearest_forward := INF
	for hit in car.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var candidate := hit.get("collider") as CharacterBody2D
		if candidate == null or candidate == car or not candidate.is_in_group("vehicle"): continue
		var forward := (candidate.global_position - car.global_position).dot(car.global_transform.x)
		if forward <= 0.0 or forward >= nearest_forward: continue
		nearest = candidate
		nearest_forward = forward
	if nearest == null: return INF
	var other_half_length := 20.0
	var other_hull := nearest.get_node_or_null("Collision") as CollisionShape2D
	if other_hull != null and other_hull.shape != null:
		other_half_length = other_hull.shape.get_rect().size.x * 0.5
	var own_length := float(car.get("target_length")) if car.get("target_length") != null else 96.0
	var clearance := maxf(0.0, nearest_forward - own_length * 0.5 - other_half_length)
	var leader_speed := maxf(0.0, nearest.velocity.dot(car.global_transform.x))
	if nearest.get("_lane_motion_speed") != null:
		leader_speed = maxf(leader_speed, float(nearest.get("_lane_motion_speed")))
	return clampf(leader_speed + maxf(0.0, clearance - 60.0) * 0.6, 0.0, 155.0)


func _tap_key(code: Key, phase: String, subject: Node2D) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		for _i in 2:
			await process_frame
			_record_frame(phase, subject)


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_motion() -> void:
	for action in [&"move_up", &"move_down", &"move_left", &"move_right", &"sprint", &"handbrake"]:
		Input.action_release(action)


func _set_physics_guard(subject: Node2D, phase: String, limit: float) -> void:
	_physics_guard_subject = subject
	_physics_guard_phase = phase
	_physics_guard_limit = limit
	_physics_guard_armed = is_instance_valid(subject)
	if _physics_guard_armed:
		_physics_guard_previous = subject.global_position


func _audit_physics_step() -> void:
	if not _physics_guard_armed or not is_instance_valid(_physics_guard_subject):
		return
	var current := _physics_guard_subject.global_position
	var step := current.distance_to(_physics_guard_previous)
	_physics_guard_previous = current
	_physics_guard_max_step = maxf(_physics_guard_max_step, step)
	if not current.is_finite() or step > _physics_guard_limit:
		var event := {
			"phase": _physics_guard_phase,
			"physics_frame": Engine.get_physics_frames(),
			"step_px": step,
			"limit_px": _physics_guard_limit,
			"position": str(current),
		}
		_teleport_events.append(event)
		_motion_contract_failed = true
		_fail("Impossible physics step detected: " + JSON.stringify(event))


func _open_measurement_files() -> bool:
	_csv = FileAccess.open(_output.path_join("real_route.csv"), FileAccess.WRITE)
	_stall_file = FileAccess.open(_output.path_join("real_route_stalls.jsonl"), FileAccess.WRITE)
	if _csv == null or _stall_file == null:
		_fail("Could not open route evidence files in " + _output)
		return false
	_csv.store_line("phase,engine_frame,frame_ms,process_ms,physics_ms,draw_calls,x,y,speed,police,traffic,population,wanted_stars,physics_active,physics_pairs,object_count,node_count,resource_count,static_mem_mb,video_mem_mb,presentation_pending,subviewports_total,subviewports_active,window_focused,route_waypoint")
	_previous_frame_usec = Time.get_ticks_usec()
	_previous_physics_frame = Engine.get_physics_frames()
	_previous_metrics = _frame_metrics_snapshot()
	_previous_focus = DisplayServer.window_is_focused()
	return true


func _record_frame(phase: String, subject: Node2D) -> void:
	if _csv == null or not is_instance_valid(subject):
		return
	var now := Time.get_ticks_usec()
	var frame_ms := maxf(0.001, (now - _previous_frame_usec) / 1000.0)
	_samples.append(frame_ms)
	if frame_ms > 16.67: _over_16 += 1
	if frame_ms > 33.3: _over_33 += 1
	if frame_ms > 50.0: _over_50 += 1
	if frame_ms > 66.7: _over_66 += 1

	var stats: Dictionary = _phase_stats.get(phase, {
		"frames": 0, "elapsed_ms": 0.0, "travelled_px": 0.0,
		"moving_ms": 0.0, "stopped_ms": 0.0, "longest_stop_ms": 0.0,
		"max_render_step_px": 0.0, "previous_position": subject.global_position,
	})
	var previous_position: Vector2 = stats.previous_position
	var step := subject.global_position.distance_to(previous_position)
	stats.frames = int(stats.frames) + 1
	stats.elapsed_ms = float(stats.elapsed_ms) + frame_ms
	stats.travelled_px = float(stats.travelled_px) + step
	stats.max_render_step_px = maxf(float(stats.max_render_step_px), step)
	stats.previous_position = subject.global_position
	if phase in ["walking", "driving"]:
		if step > frame_ms * 0.005:
			stats.moving_ms = float(stats.moving_ms) + frame_ms
			stats.stopped_ms = 0.0
		else:
			stats.stopped_ms = float(stats.stopped_ms) + frame_ms
			stats.longest_stop_ms = maxf(float(stats.longest_stop_ms), float(stats.stopped_ms))
	_phase_stats[phase] = stats

	_hold_scenario_clock()
	_report_render()
	var police := _count_live_police()
	var traffic := _count_live_traffic()
	var population := _count_live_population()
	var wanted := root.get_node_or_null("WantedManager")
	var wanted_stars := int(wanted.current_stars) if wanted != null else 0
	_police_peak = maxi(_police_peak, police)
	_traffic_peak = maxi(_traffic_peak, traffic)
	_population_peak = maxi(_population_peak, population)
	_wanted_peak = maxi(_wanted_peak, wanted_stars)
	_police_sum += police
	_traffic_sum += traffic
	_population_sum += population
	_actor_count_samples += 1
	if phase == "driving":
		_driving_actor_samples += 1
		if wanted_stars >= _requested_wanted_level:
			_driving_wanted_required_samples += 1
	var presentation_budget := root.get_node_or_null("PresentationBudget")
	var active_objects := Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)
	var collision_pairs := Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)
	var object_count := Performance.get_monitor(Performance.OBJECT_COUNT)
	var node_count := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var resource_count := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var static_memory_bytes := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_memory_peak_bytes = maxi(_memory_peak_bytes, static_memory_bytes)
	var video_mem_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	_video_memory_peak_bytes = maxi(
		_video_memory_peak_bytes,
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	)
	var pending := int(presentation_budget.pending.size()) if presentation_budget != null else 0
	if _frame_index % TELEMETRY_SAMPLE_FRAMES == 0:
		_sample_extended_state()
	var focused := DisplayServer.window_is_focused()
	if focused: _focused_frames += 1
	if focused != _previous_focus: _focus_transitions += 1
	_previous_focus = focused
	# SceneTree.process_frame wakes this fixture before nodes process the new
	# frame. The elapsed interval therefore represents the frame that just ended.
	# Scheduler tickets granted in frame N are paid by the sample observed at the
	# start of N+1, which is labelled N here for an exact composed-frame join.
	var engine_frame := maxi(0, Engine.get_process_frames() - 1)
	var csv_row: PackedStringArray = []
	for value in [
		phase, engine_frame, frame_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		subject.global_position.x, subject.global_position.y,
		subject.velocity.length() if subject is CharacterBody2D else 0.0,
		police, traffic, population, wanted_stars, active_objects, collision_pairs,
		object_count, node_count, resource_count, static_memory_bytes / 1048576.0,
		video_mem_mb, pending, int(_subviewport_latest.get("total", 0)),
		int(_subviewport_latest.get("active", 0)), int(focused), _drive_waypoint_index,
	]:
		csv_row.append(str(value))
	_csv.store_csv_line(csv_row)
	_store_frame_correlation(
		engine_frame, _frame_index, frame_ms, phase, _drive_waypoint_index,
		subject.global_position, police, traffic, population, wanted_stars
	)
	var frame_evidence := {
		"engine_frame": engine_frame,
		"route_frame": _frame_index,
		"phase": phase,
		"frame_ms": frame_ms,
		"waypoint": _drive_waypoint_index,
		"position": str(subject.global_position),
		"police": police,
		"traffic": traffic,
		"population": population,
		"wanted": wanted_stars,
	}
	if phase == "driving" and _physical_transition.is_empty() and is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null and String(stream.get("current_region")) == "mountain":
			_physical_transition = frame_evidence.duplicate(true)

	var current_metrics := _frame_metrics_snapshot(presentation_budget, {
		"object_count": object_count, "node_count": node_count,
		"resource_count": resource_count, "video_mem_mb": video_mem_mb,
		"physics_active": active_objects, "physics_pairs": collision_pairs,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	})
	var current_physics_frame := Engine.get_physics_frames()
	var physics_steps := current_physics_frame - _previous_physics_frame
	_previous_physics_frame = current_physics_frame
	if frame_ms >= _stall_threshold_ms:
		_stall_count += 1
		if _stall_traces < MAX_STALL_TRACES:
			var details := _stall_details(phase, _frame_index, _elapsed_ms(), frame_ms, physics_steps, subject, _previous_metrics, current_metrics)
			details["route_waypoint"] = _drive_waypoint_index
			_stall_file.store_line(JSON.stringify(_bounded_report_value(details)))
			_stall_traces += 1
	_previous_metrics = current_metrics
	_frame_index += 1
	# The CSV/group/SubViewport probes are observers, not gameplay. Start the next
	# wall-clock interval only after they finish, otherwise their own work is
	# charged to the following frame and can fabricate a composed-frame outlier.
	_previous_frame_usec = Time.get_ticks_usec()


func _count_live_police() -> int:
	var count := 0
	for vehicle in get_nodes_in_group("emergency_vehicle"):
		if is_instance_valid(vehicle) and vehicle.visible and vehicle.get("type") == 0:
			count += 1
	return count


func _count_live_traffic() -> int:
	var count := 0
	for vehicle in get_nodes_in_group("modern_traffic"):
		if is_instance_valid(vehicle) and vehicle.visible and vehicle.get("is_driven_by_player") != true:
			count += 1
	return count


func _count_live_population() -> int:
	var actors := {}
	for group in [&"pedestrian", &"authored_sidewalk_pedestrian"]:
		for actor in get_nodes_in_group(group):
			if not is_instance_valid(actor) or not actor is Node2D:
				continue
			if not actor.visible or ("is_dead" in actor and actor.is_dead == true):
				continue
			actors[actor.get_instance_id()] = true
	return actors.size()


func _sample_extended_state() -> void:
	var dead_now := 0
	var corpse_now := 0
	var seen_actors := {}
	for group in [
		&"damageable", &"pedestrian", &"authored_sidewalk_pedestrian",
		&"police_officer", &"firefighter", &"paramedic", &"mortician",
	]:
		for actor in get_nodes_in_group(group):
			if not is_instance_valid(actor) or seen_actors.has(actor.get_instance_id()):
				continue
			seen_actors[actor.get_instance_id()] = true
			if "is_dead" in actor and actor.is_dead == true:
				dead_now += 1
				_unique_deaths[actor.get_instance_id()] = true
			if actor.has_meta("corpse_visual_id"):
				corpse_now += 1
				_unique_corpses[actor.get_instance_id()] = true
	_dead_peak = maxi(_dead_peak, dead_now)
	_corpse_peak = maxi(_corpse_peak, corpse_now)

	var blood_now := 0
	for blood in get_nodes_in_group("ground_blood"):
		if not is_instance_valid(blood):
			continue
		blood_now += 1
		_unique_blood[blood.get_instance_id()] = true
	_blood_peak = maxi(_blood_peak, blood_now)

	var viewport_snapshot := {
		"total": 0,
		"active": 0,
		"disabled": 0,
		"once": 0,
		"when_visible": 0,
		"always": 0,
		"pixels": 0,
	}
	for candidate in root.find_children("*", "SubViewport", true, false):
		var viewport := candidate as SubViewport
		if viewport == null:
			continue
		viewport_snapshot.total += 1
		viewport_snapshot.pixels += int(viewport.size.x) * int(viewport.size.y)
		match viewport.render_target_update_mode:
			SubViewport.UPDATE_DISABLED:
				viewport_snapshot.disabled += 1
			SubViewport.UPDATE_ONCE:
				viewport_snapshot.once += 1
			SubViewport.UPDATE_WHEN_VISIBLE:
				viewport_snapshot.when_visible += 1
			SubViewport.UPDATE_ALWAYS:
				viewport_snapshot.always += 1
		if viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			viewport_snapshot.active += 1
	_subviewport_latest = viewport_snapshot
	if _subviewport_peak.is_empty():
		_subviewport_peak = viewport_snapshot.duplicate(true)
	else:
		for key in viewport_snapshot:
			_subviewport_peak[key] = maxi(
				int(_subviewport_peak.get(key, 0)),
				int(viewport_snapshot[key])
			)


func _elapsed_ms() -> float:
	var total := 0.0
	for value in _samples:
		total += value
	return total


func _capture_scheduler_baseline() -> void:
	_scheduler_baseline_ids.clear()
	for record_value in _scheduler_script.telemetry_snapshot().get("records", []):
		var record: Dictionary = record_value
		_scheduler_baseline_ids[int(record.get("id", -1))] = true


func _store_frame_correlation(
	engine_frame: int,
	route_frame: int,
	frame_ms: float,
	phase: String,
	waypoint: int,
	position: Vector2,
	police: int,
	traffic: int,
	population: int,
	wanted: int
) -> void:
	if _sample_engine_frames.size() < MAX_CORRELATION_SAMPLES:
		_sample_engine_frames.append(engine_frame)
		_sample_route_frames.append(route_frame)
		_sample_frame_ms.append(frame_ms)
		_sample_phases.append(phase)
		_sample_waypoints.append(waypoint)
		_sample_positions.append(position)
		_sample_police.append(police)
		_sample_traffic.append(traffic)
		_sample_population.append(population)
		_sample_wanted.append(wanted)
		_correlation_next_index = _sample_engine_frames.size() % MAX_CORRELATION_SAMPLES
		return
	var index := _correlation_next_index
	_sample_engine_frames[index] = engine_frame
	_sample_route_frames[index] = route_frame
	_sample_frame_ms[index] = frame_ms
	_sample_phases[index] = phase
	_sample_waypoints[index] = waypoint
	_sample_positions[index] = position
	_sample_police[index] = police
	_sample_traffic[index] = traffic
	_sample_population[index] = population
	_sample_wanted[index] = wanted
	_correlation_next_index = (_correlation_next_index + 1) % MAX_CORRELATION_SAMPLES
	_correlation_overwrites += 1


func _route_frame_evidence(engine_frame: int) -> Dictionary:
	# Search newest-to-oldest in a fixed-size ring. Route scheduler jobs are few;
	# this moves lookup work out of measured gameplay without unbounded storage.
	var sample_count := _sample_engine_frames.size()
	for offset in sample_count:
		var index := posmod(_correlation_next_index - 1 - offset, sample_count)
		var recorded_frame := int(_sample_engine_frames[index])
		if recorded_frame != engine_frame:
			continue
		return {
			"engine_frame": recorded_frame,
			"route_frame": int(_sample_route_frames[index]),
			"phase": _sample_phases[index],
			"frame_ms": float(_sample_frame_ms[index]),
			"waypoint": int(_sample_waypoints[index]),
			"position": str(_sample_positions[index]),
			"police": int(_sample_police[index]),
			"traffic": int(_sample_traffic[index]),
			"population": int(_sample_population[index]),
			"wanted": int(_sample_wanted[index]),
		}
	return {}


func _scheduler_route_report(cache_report: Dictionary) -> Dictionary:
	var snapshot: Dictionary = _scheduler_script.telemetry_snapshot()
	var by_producer := {}
	var jobs: Array[Dictionary] = []
	var jobs_over_budget: Array[Dictionary] = []
	var uncorrelated_jobs: Array[Dictionary] = []
	var stage_candidates: Array[Dictionary] = []
	for stage_value in cache_report.get("regional_stage_steps", []):
		if stage_candidates.size() >= MAX_REPORT_COLLECTION_ITEMS:
			break
		stage_candidates.append((stage_value as Dictionary).duplicate(true))
	var stage_by_ticket := {}
	var duplicate_stage_ticket_ids: Array[int] = []
	for candidate_index in stage_candidates.size():
		var ticket_id := int(stage_candidates[candidate_index].get("ticket_id", -1))
		if ticket_id < 0:
			continue
		if stage_by_ticket.has(ticket_id):
			duplicate_stage_ticket_ids.append(ticket_id)
			continue
		stage_by_ticket[ticket_id] = candidate_index
	var matched_stage_candidates := {}
	for record_value in snapshot.get("records", []):
		var record: Dictionary = record_value
		if _scheduler_baseline_ids.has(int(record.get("id", -1))):
			continue
		if String(record.get("status", "")) != "completed":
			continue
		var producer := String(record.get("producer", "unknown"))
		var actual_usec := int(record.get("actual_usec", 0))
		var engine_frame := int(record.get("frame", -1))
		var frame_evidence := _route_frame_evidence(engine_frame)
		var detail := {
			"id": int(record.get("id", -1)),
			"producer": producer,
			"engine_frame": engine_frame,
			"actual_usec": actual_usec,
			"actual_ms": actual_usec / 1000.0,
			"expected_usec": int(record.get("expected_usec", 0)),
			"waited_frames": int(record.get("waited_frames", 0)),
			"over_scheduler_budget": actual_usec > SCHEDULER_BUDGET_USEC,
			"frame_correlated": not frame_evidence.is_empty(),
			"composed_frame": frame_evidence.duplicate(true),
		}
		if producer.begins_with("vehicle_prewarm:"):
			var ticket_id := int(record.get("id", -1))
			var candidate_index := int(stage_by_ticket.get(ticket_id, -1))
			if candidate_index >= 0:
				var candidate: Dictionary = stage_candidates[candidate_index]
				var correlation_errors: Array[String] = []
				var stage_path := String(candidate.get("path", ""))
				var stage_name := String(candidate.get("stage", ""))
				if int(candidate.get("frame", -1)) != engine_frame:
					correlation_errors.append("frame_mismatch")
				if int(candidate.get("actual_usec", -1)) != actual_usec:
					correlation_errors.append("actual_usec_mismatch")
				if stage_path.is_empty():
					correlation_errors.append("missing_path")
				if stage_name.is_empty():
					correlation_errors.append("missing_stage")
				if String(candidate.get("producer", "")) != producer:
					correlation_errors.append("producer_mismatch")
				detail["regional_stage_ticket_id"] = int(candidate.get("ticket_id", -1))
				detail["regional_stage_frame"] = int(candidate.get("frame", -1))
				detail["regional_model_path"] = stage_path
				detail["regional_stage"] = stage_name
				detail["regional_stage_correlated"] = correlation_errors.is_empty()
				if correlation_errors.is_empty():
					matched_stage_candidates[candidate_index] = true
				else:
					detail["regional_correlation_errors"] = correlation_errors
			else:
				detail["regional_stage_correlated"] = false
				detail["regional_correlation_errors"] = ["missing_stage_step_for_ticket"]
		jobs.append(detail)
		if actual_usec > SCHEDULER_BUDGET_USEC:
			jobs_over_budget.append(detail.duplicate(true))
		if frame_evidence.is_empty():
			uncorrelated_jobs.append(detail.duplicate(true))
		var producer_stats: Dictionary = by_producer.get(producer, {
			"jobs": 0,
			"total_actual_usec": 0,
			"max_actual_usec": 0,
			"over_budget_jobs": 0,
			"correlated_jobs": 0,
			"max_composed_frame_ms": 0.0,
			"composed_frames_over_16_67": 0,
		})
		producer_stats.jobs += 1
		producer_stats.total_actual_usec += actual_usec
		producer_stats.max_actual_usec = maxi(int(producer_stats.max_actual_usec), actual_usec)
		if actual_usec > SCHEDULER_BUDGET_USEC:
			producer_stats.over_budget_jobs += 1
		if not frame_evidence.is_empty():
			producer_stats.correlated_jobs += 1
			var composed_ms := float(frame_evidence.get("frame_ms", 0.0))
			producer_stats.max_composed_frame_ms = maxf(float(producer_stats.max_composed_frame_ms), composed_ms)
			if composed_ms > 16.67:
				producer_stats.composed_frames_over_16_67 += 1
		by_producer[producer] = producer_stats
	for producer in by_producer:
		var stats: Dictionary = by_producer[producer]
		stats["average_actual_usec"] = int(stats.total_actual_usec) / float(maxi(1, int(stats.jobs)))
		by_producer[producer] = stats
	var unmatched_stage_steps: Array[Dictionary] = []
	for candidate_index in stage_candidates.size():
		if not matched_stage_candidates.has(candidate_index):
			unmatched_stage_steps.append(stage_candidates[candidate_index].duplicate(true))
	return {
		"budget_usec": int(snapshot.get("frame_budget_usec", SCHEDULER_BUDGET_USEC)),
		"acceptance_basis": "same_frame_composed_route_frametime",
		"isolated_job_under_16_67_is_sufficient": false,
		"route_jobs": jobs,
		"jobs_over_budget": jobs_over_budget,
		"uncorrelated_jobs": uncorrelated_jobs,
		"by_producer": by_producer,
		"route_completed_jobs": jobs.size(),
		"route_over_budget_jobs": jobs_over_budget.size(),
		"regional_stage_candidates": stage_candidates.size(),
		"regional_stage_jobs_matched": matched_stage_candidates.size(),
		"unmatched_regional_stage_steps": unmatched_stage_steps,
		"duplicate_regional_stage_ticket_ids": duplicate_stage_ticket_ids,
		"regional_stage_steps_executed": int(cache_report.get("regional_stage_steps_executed", 0)),
		"regional_stage_steps_dropped": int(cache_report.get("regional_stage_steps_dropped", 0)),
		"correlation_buffer": {
			"capacity": MAX_CORRELATION_SAMPLES,
			"retained_samples": _sample_engine_frames.size(),
			"overwritten_samples": _correlation_overwrites,
		},
		"scheduler_snapshot_totals": {
			"completed_total": int(snapshot.get("completed_total", 0)),
			"cancelled_total": int(snapshot.get("cancelled_total", 0)),
			"over_budget_total": int(snapshot.get("over_budget_total", 0)),
			"pending": int(snapshot.get("pending", 0)),
			"records_retained": (snapshot.get("records", []) as Array).size(),
		},
	}


func _vehicle_cache_route_report() -> Dictionary:
	var final: Dictionary = _vehicle_cache_script.telemetry()
	var mountain: Dictionary = _vehicle_cache_script.region_telemetry(&"mountain")
	return {
		"baseline": {
			"misses": int(_cache_baseline.get("misses", 0)),
			"cold_builds": int(_cache_baseline.get("cold_builds", 0)),
			"cold_build_usec": int(_cache_baseline.get("cold_build_usec", 0)),
			"regional_misses": int(_cache_baseline.get("regional_misses", 0)),
			"regional_cold_builds": int(_cache_baseline.get("regional_cold_builds", 0)),
			"regional_cold_build_usec": int(_cache_baseline.get("regional_cold_build_usec", 0)),
		},
		"final": {
			"misses": int(final.get("misses", 0)),
			"cold_builds": int(final.get("cold_builds", 0)),
			"cold_build_usec": int(final.get("cold_build_usec", 0)),
			"regional_misses": int(final.get("regional_misses", 0)),
			"regional_cold_builds": int(final.get("regional_cold_builds", 0)),
			"regional_cold_build_usec": int(final.get("regional_cold_build_usec", 0)),
			"max_cold_build_usec": int(final.get("max_cold_build_usec", 0)),
			"last_model_key": String(final.get("last_model_key", "")),
		},
		"route_delta": {
			"misses": maxi(0, int(final.get("misses", 0)) - int(_cache_baseline.get("misses", 0))),
			"cold_builds": maxi(0, int(final.get("cold_builds", 0)) - int(_cache_baseline.get("cold_builds", 0))),
			"cold_build_usec": maxi(0, int(final.get("cold_build_usec", 0)) - int(_cache_baseline.get("cold_build_usec", 0))),
			"regional_misses": maxi(0, int(final.get("regional_misses", 0)) - int(_cache_baseline.get("regional_misses", 0))),
			"regional_cold_builds": maxi(0, int(final.get("regional_cold_builds", 0)) - int(_cache_baseline.get("regional_cold_builds", 0))),
			"regional_cold_build_usec": maxi(0, int(final.get("regional_cold_build_usec", 0)) - int(_cache_baseline.get("regional_cold_build_usec", 0))),
		},
		"mountain_region": mountain,
		"regional_model_timings": mountain.get("model_timings", []),
		"regional_stage_steps": mountain.get("stage_steps", []),
		"regional_stage_steps_executed": int(mountain.get("stage_steps_executed", 0)),
		"regional_stage_steps_dropped": int(mountain.get("stage_steps_dropped", 0)),
		"regional_stage_totals_usec": mountain.get("stage_totals_usec", {}),
		"failed_models": mountain.get("failed_models", []),
	}


func _write_json_sidecar(file_name: String, value: Dictionary) -> bool:
	var file := FileAccess.open(_output.path_join(file_name), FileAccess.WRITE)
	if file == null:
		_fail("Could not write report sidecar " + file_name)
		return false
	file.store_string(JSON.stringify(_bounded_report_value(value), "\t"))
	file.close()
	return true


func _bounded_report_value(value: Variant, depth := 0) -> Variant:
	if depth >= MAX_REPORT_DEPTH:
		return {"_truncated": true, "reason": "maximum_depth"}
	if value is Array:
		var source_array := value as Array
		var bounded_array: Array = []
		var retained_items := mini(source_array.size(), MAX_REPORT_COLLECTION_ITEMS)
		for index in retained_items:
			bounded_array.append(_bounded_report_value(source_array[index], depth + 1))
		if source_array.size() > retained_items:
			bounded_array.append({"_truncated_items": source_array.size() - retained_items})
		return bounded_array
	if value is Dictionary:
		var source_dictionary := value as Dictionary
		var bounded_dictionary := {}
		var retained_keys := 0
		for key in source_dictionary:
			if retained_keys >= MAX_REPORT_DICTIONARY_KEYS:
				break
			bounded_dictionary[key] = _bounded_report_value(source_dictionary[key], depth + 1)
			retained_keys += 1
		if source_dictionary.size() > retained_keys:
			bounded_dictionary["_truncated_keys"] = source_dictionary.size() - retained_keys
		return bounded_dictionary
	if value is String and String(value).length() > 4096:
		return String(value).left(4096) + "…"
	return value


func _validate_motion_contracts() -> void:
	var walking: Dictionary = _phase_stats.get("walking", {})
	var driving: Dictionary = _phase_stats.get("driving", {})
	var walked := float(walking.get("travelled_px", 0.0))
	var minimum_walk := maxf(120.0, _walk_required_distance * 0.70)
	if walked < minimum_walk:
		_fail("Walking coverage too small: %.1f px < %.1f px" % [walked, minimum_walk])
	var driven := float(driving.get("travelled_px", 0.0))
	if driven < MIN_DRIVE_DISTANCE:
		_fail("Driving coverage too small: %.1f px < %.1f px" % [driven, MIN_DRIVE_DISTANCE])
	var drive_elapsed := float(driving.get("elapsed_ms", 0.0))
	var moving_fraction := float(driving.get("moving_ms", 0.0)) / maxf(1.0, drive_elapsed)
	if moving_fraction < MIN_DRIVE_MOVING_FRACTION:
		_fail("Driving movement fraction too small: %.3f" % moving_fraction)
	var longest_stop := float(driving.get("longest_stop_ms", 0.0))
	if longest_stop >= MAX_ROUTE_STOP_MS:
		_fail("Driving stopped too long: %.1f ms" % longest_stop)
	if not _teleport_events.is_empty():
		_fail("Route contains impossible physics steps")
	if drive_elapsed < 30000.0:
		_fail("Driving sample is shorter than the 30 second minimum")


func _finish(world: Node) -> void:
	_release_motion()
	_set_physics_guard(null, "", INF)
	if physics_frame.is_connected(_audit_physics_step):
		physics_frame.disconnect(_audit_physics_step)
	if _trace_stall_events:
		if node_added.is_connected(_record_tree_event.bind("add")):
			node_added.disconnect(_record_tree_event.bind("add"))
		if node_removed.is_connected(_record_tree_event.bind("remove")):
			node_removed.disconnect(_record_tree_event.bind("remove"))
	if _csv != null: _csv.close()
	if _stall_file != null: _stall_file.close()
	_sample_extended_state()
	var sorted := _samples.duplicate()
	sorted.sort()
	var total := _elapsed_ms()
	var average_ms := total / float(maxi(1, _samples.size()))
	var p50_ms := _percentile(sorted, 0.50)
	var p95_ms := _percentile(sorted, 0.95)
	var p99_ms := _percentile(sorted, 0.99)
	var max_ms: float = float(sorted[-1]) if not sorted.is_empty() else 0.0
	var focus_fraction := _focused_frames / float(maxi(1, _samples.size()))
	if not _samples.is_empty() and focus_fraction < 0.90:
		_fail("Rendered window was focused for less than 90% of the measured route")
	if average_ms > MAX_AVG_FRAME_MS:
		_fail("Composed average frame time exceeds %.2f ms: %.3f ms" % [MAX_AVG_FRAME_MS, average_ms])
	if p95_ms > MAX_P95_FRAME_MS:
		_fail("Composed p95 frame time exceeds %.2f ms: %.3f ms" % [MAX_P95_FRAME_MS, p95_ms])
	if p99_ms > MAX_P99_FRAME_MS:
		_fail("Composed p99 frame time exceeds %.1f ms: %.3f ms" % [MAX_P99_FRAME_MS, p99_ms])
	if max_ms > MAX_SINGLE_FRAME_MS:
		_fail("Composed maximum frame time exceeds %.1f ms: %.3f ms" % [MAX_SINGLE_FRAME_MS, max_ms])
	var report_phase_stats := {}
	for phase in _phase_stats:
		var cleaned: Dictionary = _phase_stats[phase].duplicate()
		cleaned.erase("previous_position")
		cleaned["moving_fraction"] = float(cleaned.get("moving_ms", 0.0)) / maxf(1.0, float(cleaned.get("elapsed_ms", 0.0)))
		report_phase_stats[phase] = cleaned
	var cache_report := _vehicle_cache_route_report()
	var scheduler_report := _scheduler_route_report(cache_report)
	var streaming := {}
	if is_instance_valid(_scenario_world):
		var stream := _scenario_world.get_node_or_null("ContinuousWorld")
		if stream != null:
			streaming = stream.get_streaming_stats()
	var regional_prewarm: Dictionary = streaming.get("vehicle_regional_prewarm", {})
	var crossed_before_ready := int(regional_prewarm.get("crossed_before_ready", 0))
	if crossed_before_ready > 0:
		_fail("Physical route crossed before regional vehicle readiness")
	if int(scheduler_report.get("route_completed_jobs", 0)) == 0:
		_fail("No RuntimeWorkScheduler job was observed during the regional route")
	if int((scheduler_report.get("scheduler_snapshot_totals", {}) as Dictionary).get("pending", 0)) > 0:
		_fail("RuntimeWorkScheduler still has pending work after the physical route")
	if not (scheduler_report.get("uncorrelated_jobs", []) as Array).is_empty():
		_fail("One or more scheduler jobs lack same-frame route correlation")
	if int(scheduler_report.get("regional_stage_steps_dropped", 0)) > 0:
		_fail("Regional stage telemetry was truncated; exact cold-work certification is impossible")
	if int(scheduler_report.get("regional_stage_steps_executed", 0)) != int(scheduler_report.get("regional_stage_candidates", 0)):
		_fail("Regional stage telemetry retained count does not match executed count")
	if not (scheduler_report.get("duplicate_regional_stage_ticket_ids", []) as Array).is_empty():
		_fail("Regional stage telemetry contains duplicate scheduler ticket ids")
	if not (scheduler_report.get("unmatched_regional_stage_steps", []) as Array).is_empty():
		_fail("One or more regional stages lack an exact scheduler ticket correlation")
	for job_value in scheduler_report.get("route_jobs", []):
		var job: Dictionary = job_value
		var composed: Dictionary = job.get("composed_frame", {})
		if String(job.get("producer", "")).begins_with("vehicle_prewarm:"):
			if not bool(job.get("regional_stage_correlated", false)):
				_fail("Regional scheduler job lacks exact ticket/frame/path/stage correlation")
			if bool(job.get("over_scheduler_budget", false)):
				_fail("Regional scheduler stage exceeded the 6 ms work budget")
		if not composed.is_empty() and float(composed.get("frame_ms", 0.0)) > 16.67:
			_fail(
				"Scheduler job %s composed with a %.3f ms route frame" % [
					String(job.get("producer", "unknown")),
					float(composed.get("frame_ms", 0.0)),
				]
			)
	var route_cache_delta: Dictionary = cache_report.get("route_delta", {})
	var total_misses_delta := int(route_cache_delta.get("misses", 0))
	var regional_misses_delta := int(route_cache_delta.get("regional_misses", 0))
	var total_cold_builds_delta := int(route_cache_delta.get("cold_builds", 0))
	var regional_cold_builds_delta := int(route_cache_delta.get("regional_cold_builds", 0))
	var total_cold_build_usec_delta := int(route_cache_delta.get("cold_build_usec", 0))
	var regional_cold_build_usec_delta := int(route_cache_delta.get("regional_cold_build_usec", 0))
	var unscheduled_misses := maxi(0, total_misses_delta - regional_misses_delta)
	var unscheduled_cold_builds := maxi(0, total_cold_builds_delta - regional_cold_builds_delta)
	var unscheduled_cold_build_usec := maxi(0, total_cold_build_usec_delta - regional_cold_build_usec_delta)
	var correlated_stage_paths := {}
	for job_value in scheduler_report.get("route_jobs", []):
		var job: Dictionary = job_value
		if not String(job.get("producer", "")).begins_with("vehicle_prewarm:"):
			continue
		if bool(job.get("regional_stage_correlated", false)):
			correlated_stage_paths[String(job.get("regional_model_path", ""))] = true
	var completed_model_paths := {}
	var completed_model_active_usec := 0
	for timing_value in cache_report.get("regional_model_timings", []):
		var timing: Dictionary = timing_value
		var path := String(timing.get("path", ""))
		if path.is_empty() or completed_model_paths.has(path):
			_fail("Regional model completion telemetry lacks a unique model path")
			continue
		completed_model_paths[path] = true
		completed_model_active_usec += int(timing.get("actual_usec", 0))
		if not correlated_stage_paths.has(path):
			_fail("Regional cold build completed without correlated scheduled stages")
	var mountain_region: Dictionary = cache_report.get("mountain_region", {})
	var reported_region_misses := int(mountain_region.get("regional_misses", 0))
	var reported_region_cold_builds := int(mountain_region.get("regional_cold_builds", 0))
	var reported_region_cold_build_usec := int(mountain_region.get("regional_cold_build_usec", 0))
	route_cache_delta["unscheduled_misses"] = unscheduled_misses
	route_cache_delta["unscheduled_cold_builds"] = unscheduled_cold_builds
	route_cache_delta["unscheduled_cold_build_usec"] = unscheduled_cold_build_usec
	cache_report["route_delta"] = route_cache_delta
	cache_report["cold_work_validation"] = {
		"correlated_stage_paths": correlated_stage_paths.keys(),
		"completed_model_paths": completed_model_paths.keys(),
		"completed_model_active_usec": completed_model_active_usec,
		"exactly_correlated": (
			regional_misses_delta == correlated_stage_paths.size()
			and regional_cold_builds_delta == completed_model_paths.size()
			and regional_cold_build_usec_delta == completed_model_active_usec
			and regional_misses_delta == reported_region_misses
			and regional_cold_builds_delta == reported_region_cold_builds
			and regional_cold_build_usec_delta == reported_region_cold_build_usec
		),
	}
	if regional_misses_delta > total_misses_delta or regional_cold_builds_delta > total_cold_builds_delta or regional_cold_build_usec_delta > total_cold_build_usec_delta:
		_fail("Regional cache counters exceed total cache deltas")
	if unscheduled_misses > 0:
		_fail("Unscheduled vehicle geometry cache miss occurred during the measured route")
	if unscheduled_cold_builds > 0 or unscheduled_cold_build_usec > 0:
		_fail("Unscheduled vehicle geometry cold build occurred during the measured route")
	if regional_misses_delta != correlated_stage_paths.size() or regional_misses_delta != reported_region_misses:
		_fail("Regional cache misses do not map one-to-one to correlated scheduled model paths")
	if regional_cold_builds_delta != completed_model_paths.size() or regional_cold_builds_delta != reported_region_cold_builds:
		_fail("Regional cold builds do not map one-to-one to completed correlated models")
	if regional_cold_build_usec_delta != completed_model_active_usec or regional_cold_build_usec_delta != reported_region_cold_build_usec:
		_fail("Regional cold-build CPU does not match correlated per-model active work")
	if not (cache_report.get("failed_models", []) as Array).is_empty():
		_fail("Regional vehicle preparation reported failed models")
	if (cache_report.get("regional_model_timings", []) as Array).is_empty():
		_fail("Regional prewarm produced no per-model stage timings")
	if int(regional_prewarm.get("max_jobs_in_frame", 0)) > 1:
		_fail("Regional prewarm executed more than one heavy job in one frame")
	var wanted_required_fraction := _driving_wanted_required_samples / float(maxi(1, _driving_actor_samples))
	if wanted_required_fraction < 0.90:
		_fail("Required wanted level was active for less than 90% of the input-driven route")

	var actor_counts := {
		"police_peak": _police_peak,
		"police_average": _police_sum / float(maxi(1, _actor_count_samples)),
		"traffic_peak": _traffic_peak,
		"traffic_average": _traffic_sum / float(maxi(1, _actor_count_samples)),
		"population_peak": _population_peak,
		"population_average": _population_sum / float(maxi(1, _actor_count_samples)),
		"wanted_peak": _wanted_peak,
		"wanted_required": _requested_wanted_level,
		"wanted_required_driving_fraction": wanted_required_fraction,
	}
	var incident_counts := {
		"deaths_observed": _unique_deaths.size(),
		"dead_peak": _dead_peak,
		"corpse_visuals_observed": _unique_corpses.size(),
		"corpse_visuals_peak": _corpse_peak,
		"blood_stains_observed": _unique_blood.size(),
		"blood_stains_peak": _blood_peak,
	}
	var memory_report := {
		"static_start_bytes": _memory_start_bytes,
		"static_end_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_peak_bytes": _memory_peak_bytes,
		"static_delta_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)) - _memory_start_bytes,
		"video_peak_bytes": _video_memory_peak_bytes,
	}
	var world_state_report := {
		"scenario": _scenario_mode,
		"weather": "rain" if _scenario_mode == "chaos" else "clear",
		"time": "night" if _scenario_mode == "chaos" else "day",
		"actors": actor_counts,
		"incidents": incident_counts,
		"memory": memory_report,
		"subviewports_latest": _subviewport_latest,
		"subviewports_peak": _subviewport_peak,
		"streaming": streaming,
		"crossed_before_ready": crossed_before_ready,
		"physical_transition": _physical_transition,
		"measurement_observer": {
			"extended_state_sample_interval_frames": TELEMETRY_SAMPLE_FRAMES,
			"observer_work_excluded_from_next_frame_wall_clock": true,
			"engine_frame_label": "completed_process_frame",
		},
	}
	_write_json_sidecar("real_route_scheduler_jobs.json", scheduler_report)
	_write_json_sidecar("real_route_regional_jobs.json", cache_report)
	_write_json_sidecar("real_route_world_state.json", world_state_report)

	var report := {
		"scenario": "real_gameplay_route_" + _scenario_mode,
		"scenario_mode": _scenario_mode,
		"suite_contract": {
			"requires_separate_results": true,
			"required_scenarios": [
				"normal:wanted2:day:dry",
				"chaos:wanted4:night:rain",
			],
			"this_result_covers": _scenario_mode,
			"single_result_certifies_full_suite": false,
		},
		"valid": _failures.is_empty(),
		"failures": _failures,
		"seconds": total / 1000.0,
		"frames": _samples.size(),
		"fps": _samples.size() * 1000.0 / total if total > 0.0 else 0.0,
		"average_ms": average_ms,
		"p50_ms": p50_ms,
		"p95_ms": p95_ms,
		"p99_ms": p99_ms,
		"max_ms": max_ms,
		"over_16_67ms": _over_16,
		"over_33_3ms": _over_33,
		"over_50ms": _over_50,
		"over_66_7ms": _over_66,
		"frame_time_contract_ms": {
			"average": MAX_AVG_FRAME_MS,
			"p95": MAX_P95_FRAME_MS,
			"p99": MAX_P99_FRAME_MS,
			"maximum": MAX_SINGLE_FRAME_MS,
			"acceptance_basis": "composed_route_frametime",
			"isolated_regional_job_is_not_acceptance": true,
			"scheduler_budget": SCHEDULER_BUDGET_USEC / 1000.0,
		},
		"stall_threshold_ms": _stall_threshold_ms,
		"stall_count": _stall_count,
		"stall_traces_written": _stall_traces,
		"stall_trace_path": _output.path_join("real_route_stalls.jsonl"),
		"stall_event_trace_enabled": _trace_stall_events,
		"phase_stats": report_phase_stats,
		"walk_start": str(_walk_start),
		"walk_end": str(_walk_end),
		"walk_required_distance": _walk_required_distance,
		"walk_detours": _walk_detours,
		"drive_recoveries": _drive_recovery_count,
		"vehicle_replacements": _vehicle_replacement_count,
		"drive_recovery_events": _drive_recovery_events,
		"boarding_completed": _boarding_completed,
		"route_completed": _route_completed,
		"route_waypoints_completed": _drive_waypoint_index,
		"waypoint_arrivals": _waypoint_arrivals,
		"teleport_events": _teleport_events,
		"max_physics_step_px": _physics_guard_max_step,
		"motion_source_audit": _forbidden_motion_write_findings(),
		"physical_transition": _physical_transition,
		"actors": actor_counts,
		"incidents": incident_counts,
		"memory": memory_report,
		"subviewports_latest": _subviewport_latest,
		"subviewports_peak": _subviewport_peak,
		"scheduler": scheduler_report,
		"vehicle_cache": cache_report,
		"crossed_before_ready": crossed_before_ready,
		"window_focus_fraction": focus_fraction,
		"window_focus_transitions": _focus_transitions,
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size),
		"vsync": DisplayServer.window_get_vsync_mode(),
		"max_fps": Engine.max_fps,
		"engine": Engine.get_version_info(),
		"args": OS.get_cmdline_user_args(),
		"sidecars": {
			"scheduler_jobs": _output.path_join("real_route_scheduler_jobs.json"),
			"regional_jobs": _output.path_join("real_route_regional_jobs.json"),
			"world_state": _output.path_join("real_route_world_state.json"),
		},
	}
	report["streaming"] = streaming
	var summary := FileAccess.open(_output.path_join("real_route.json"), FileAccess.WRITE)
	if summary != null:
		summary.store_string(JSON.stringify(_bounded_report_value(report), "\t"))
		summary.close()
	else:
		_fail("Could not write real_route.json")
	report["valid"] = _failures.is_empty()
	report["failures"] = _failures
	print("REAL_GAMEPLAY_ROUTE ", JSON.stringify(report))
	if is_instance_valid(world):
		world.queue_free()
		await process_frame
	quit(0 if _failures.is_empty() else 1)


func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty(): return 0.0
	return sorted[mini(sorted.size() - 1, int(sorted.size() * fraction))]


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)
	push_error("REAL_ROUTE: " + message)


func _validate_only() -> void:
	var failures: Array[String] = []
	# This path is deliberately structural: no HarborGame instantiation, no
	# singleton reads, no runtime-script reloads and no telemetry dependency.
	var route := _build_contract_drive_route()
	if _city_drive_waypoints.size() < 12: failures.append("urban route is too short")
	if route.size() <= _city_drive_waypoints.size(): failures.append("regional connector was not appended")
	if route[-1].x <= 7300.0: failures.append("route does not cross the ContinuousWorld seam")
	for failure in _validate_waypoint_contract(route, _city_drive_waypoints[0]):
		failures.append(failure)
	for finding in _forbidden_motion_write_findings():
		failures.append("forbidden actor repositioning: " + finding)
	var route_length := 0.0
	for index in range(1, route.size()):
		var segment := route[index].distance_to(route[index - 1])
		route_length += segment
	if route_length < MIN_DRIVE_DISTANCE: failures.append("route length is below motion coverage")
	print("REAL_ROUTE_VALIDATE structural_only=true runtime_state_used=false waypoints=%d route_length_px=%.1f seam_end=%s normal_wanted=2 chaos_wanted=4 chaos_night_rain=true scheduler_budget_usec=%d correlation_capacity=%d failures=%s" % [route.size(), route_length, route[-1], SCHEDULER_BUDGET_USEC, MAX_CORRELATION_SAMPLES, failures])
	print("REAL_ROUTE_VALIDATE is parse/contract evidence only; headless does not certify FPS")
	quit(0 if failures.is_empty() else 1)
