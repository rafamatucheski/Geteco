extends SceneTree
## Diagnóstico renderizado do mesmo circuito de benchmark_west_route.gd.
## Os brackets são tempo de parede, e os spans instrumentados são inclusivos:
## nunca somar pai e filho nem chamar o tempo restante de custo do motor/GPU.
const WORK := preload("res://runtime/StallWorkTrace.gd")
const ROUTE := [Vector3(64, 0, 82), Vector3(150, 0, 82), Vector3(143, 0, 60), Vector3(84, 0, 60), Vector3(84, 0, 123), Vector3(65, 0, 113)]
const SPEED := 12.0
const WARMUP_LOOPS := 1
const MEASURE_LOOPS := 2
const PROBE_PRIORITY := 200000
const MAX_FRAMES := 120000
const MIN_MEASURE_SECONDS := 30.0

class ProcessProbe:
	extends Node
	var recorder: Variant
	var first := false
	func _process(_delta: float) -> void:
		if first: recorder.process_begin()
		else: recorder.process_end()

class PhysicsProbe:
	extends Node
	var recorder: Variant
	var first := false
	func _physics_process(_delta: float) -> void:
		if first: recorder.physics_begin()
		else: recorder.physics_end()

var label := "baseline"
var no_reflections := false
var no_shadows := false
var disabled_scripts: Array[String] = []
var world: Variant
var car: CharacterBody3D
var _route_lengths: Array[float] = []
var _route_total := 0.0
var _distance := 0.0
var _previous_process := 0
var _process_begin := 0
var _process_end := 0
var _process_frame := 0
var _deferred := 0
var _deferred_frame := 0
var _render_pre := 0
var _render_frame := 0
var _physics_begin := 0
var _physics_frame := 0
var _ticks: Array[Dictionary] = []
var _physics_mismatches := 0
var _previous_draw := 0
var _previous_draw_distance := 0.0
var _measurement_started := 0
var _measurement_finished := 0
var _telemetry_pending := 0
var _telemetry_total := 0
var _active := false
var _finished := false
var _samples: Array[Dictionary] = []
var _inventories: Array[Dictionary] = []
var _inventory_index := 0
var _viewports: Array[Dictionary] = []
var _probes: Array[Node] = []
var _invalid: Array[String] = []
var _priority_audit: Array[Dictionary] = []
var _disabled_nodes: Array[Dictionary] = []
var _startup_settings: Dictionary = {}
var _dropped_calls := 0
var _session_log_path := ""
var _trace_enabled := true
var _diagnostics: Node
var _session_profiler: Node
var _reflections: Node
var _previous_session_telemetry := 0
var _previous_session_profile_telemetry := 0
var _session_telemetry_start := 0
var _session_telemetry_end := 0
var _session_profile_telemetry_start := 0
var _session_profile_telemetry_end := 0
var _previous_draw_physics := 0

func _initialize() -> void:
	run.call_deferred()

func _arguments() -> void:
	_trace_enabled = OS.get_environment("HARBOR_WEST_CPU_TRACE") != "0"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
		elif argument == "--sem-reflexos": no_reflections = true
		elif argument == "--sem-sombras": no_shadows = true
		elif argument.begins_with("--disable-callbacks="):
			for value in argument.trim_prefix("--disable-callbacks=").split(",", false):
				disabled_scripts.append(value.strip_edges())
	# O rótulo não pode escapar da pasta de evidências.
	if label.is_empty() or label != label.validate_filename():
		_invalid.append("invalid_label")
	for index in ROUTE.size():
		var length: float = ROUTE[index].distance_to(ROUTE[(index + 1) % ROUTE.size()])
		_route_lengths.append(length)
		_route_total += length

func _route_point(distance: float) -> Dictionary:
	var along := fposmod(distance, _route_total)
	for index in ROUTE.size():
		if along <= _route_lengths[index]:
			var a: Vector3 = ROUTE[index]
			var b: Vector3 = ROUTE[(index + 1) % ROUTE.size()]
			return {"point":a.lerp(b, along / _route_lengths[index]), "yaw":atan2(-(b - a).x, -(b - a).z)}
		along -= _route_lengths[index]
	return {"point":ROUTE[0], "yaw":0.0}

func run() -> void:
	_arguments()
	if "--headless" in OS.get_cmdline_args(): _invalid.append("rendering_required")
	if "--no-save" not in OS.get_cmdline_user_args(): _invalid.append("no_save_required")
	if WORK.aggregate_enabled: _invalid.append("aggregate_sink_already_in_use")
	if not _invalid.is_empty():
		push_error("PROFILE_WEST_INVALID: " + str(_invalid))
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if world.production == null or not world.production.ready_for_play or world.session == null or not world.session.ready_for_play:
		_invalid.append("world_readiness_timeout")
		_write_report()
		quit(2)
		return
	_startup_settings = {"max_fps":Engine.max_fps, "vsync":DisplayServer.window_get_vsync_mode()}
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var weather: Variant = world.session.weather
	weather.time_of_day = 12.0 / 24.0
	if "weather_state" in weather: weather.weather_state = 0
	if "weather_timer" in weather: weather.weather_timer = 1.0e9
	var found := root.find_children("CoastalPlanarReflections", "", true, false)
	var reflections: Node = found[0] if not found.is_empty() else null
	_reflections = reflections
	_viewports.append({"name":"main", "rid":root.get_viewport_rid()})
	if reflections != null:
		if no_reflections: reflections.set_process(false)
		for view_name in ["ground_view", "facade_view"]:
			var view: SubViewport = reflections.get(view_name)
			if view != null:
				_viewports.append({"name":view_name, "rid":view.get_viewport_rid()})
				if no_reflections: view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if no_shadows:
		for light in root.find_children("*", "DirectionalLight3D", true, false):
			if light.get_world_3d() == root.world_3d: light.shadow_enabled = false
	car = world.driving.car
	car.set_physics_process(false)
	car.visible = true
	world.player.set_physics_process(false)
	world.player.visible = false
	world.camera.target = car
	_apply_callback_gates()
	_diagnostics = root.get_node_or_null("SessionDiagnostics")
	if _diagnostics != null:
		_session_log_path = str(_diagnostics.get("LogPath"))
		_session_profiler = _diagnostics.get_node_or_null("SystemProfile")
	for viewport in _viewports: RenderingServer.viewport_set_measure_render_time(viewport.rid, true)
	_priority_audit = _audit_priorities()
	_start_observers()
	while not _finished:
		await process_frame
	_stop_observers()
	_write_report()
	quit(0 if _invalid.is_empty() else 2)

func _apply_callback_gates() -> void:
	if disabled_scripts.is_empty(): return
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var script: Variant = node.get_script()
		if script != null and str(script.resource_path).get_file().get_basename() in disabled_scripts:
			_disabled_nodes.append({"path":str(node.get_path()), "script":str(script.resource_path), "process":node.is_processing(), "physics":node.is_physics_processing()})
			node.set_process(false)
			node.set_physics_process(false)
		for child in node.get_children(): pending.append(child)

func _audit_priorities() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node.process_priority != 0 or node.process_physics_priority != 0 or node.process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
			rows.append({"path":str(node.get_path()), "process":node.process_priority, "physics":node.process_physics_priority, "thread_group":node.process_thread_group})
		if absi(node.process_priority) >= PROBE_PRIORITY or absi(node.process_physics_priority) >= PROBE_PRIORITY or node.process_thread_group == Node.PROCESS_THREAD_GROUP_SUB_THREAD:
			_invalid.append("priority_not_bracketed: " + str(node.get_path()))
		for child in node.get_children(): pending.append(child)
	return rows

func _start_observers() -> void:
	for first in [true, false]:
		var process_probe := ProcessProbe.new()
		process_probe.recorder = self
		process_probe.first = first
		process_probe.name = "WestProcessBegin" if first else "WestProcessEnd"
		process_probe.process_mode = Node.PROCESS_MODE_ALWAYS
		process_probe.process_priority = -PROBE_PRIORITY if first else PROBE_PRIORITY
		root.add_child(process_probe)
		_probes.append(process_probe)
		var physics_probe := PhysicsProbe.new()
		physics_probe.recorder = self
		physics_probe.first = first
		physics_probe.name = "WestPhysicsBegin" if first else "WestPhysicsEnd"
		physics_probe.process_mode = Node.PROCESS_MODE_ALWAYS
		physics_probe.process_physics_priority = -PROBE_PRIORITY if first else PROBE_PRIORITY
		root.add_child(physics_probe)
		_probes.append(physics_probe)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	RenderingServer.frame_post_draw.connect(_post_draw)
	if _trace_enabled: WORK.start_aggregate()
	_active = true
	print("PROFILE_WEST_READY ", label, " route_m=", _route_total)

func _cost(began: int) -> void:
	var elapsed := Time.get_ticks_usec() - began
	_telemetry_pending += elapsed
	_telemetry_total += elapsed

func physics_begin() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	if _physics_begin != 0: _physics_mismatches += 1
	_physics_begin = began
	_physics_frame = Engine.get_physics_frames()
	_cost(began)

func physics_end() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	if _physics_begin == 0 or _physics_frame != Engine.get_physics_frames():
		_physics_mismatches += 1
	else:
		_ticks.append({"start_usec":_physics_begin, "end_usec":began, "physics_frame":_physics_frame})
	_physics_begin = 0
	_cost(began)

func process_begin() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	_process_begin = began
	_process_frame = Engine.get_process_frames()
	_process_end = 0
	_deferred = 0
	_render_pre = 0
	# O benchmark original avança pelo intervalo real entre callbacks, limitado a 100 ms.
	if _previous_process != 0: _distance += SPEED * minf(float(began - _previous_process) / 1000.0, 100.0) / 1000.0
	_previous_process = began
	var point := _route_point(_distance)
	car.global_position = point.point + Vector3.UP * .1
	car.rotation = Vector3(0, point.yaw, 0)
	world.player.global_position = point.point
	# As três varreduras são do aquecimento; nenhuma entra nos percentis medidos.
	if _inventory_index < 3 and _distance >= _route_total * float(_inventory_index) / 3.0:
		_inventories.append(_inventory())
		_inventory_index += 1
	_cost(began)

func process_end() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	_process_end = began
	_deferred_end.call_deferred(_process_frame)
	_cost(began)

func _deferred_end(frame: int) -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	_deferred = began
	_deferred_frame = frame
	_cost(began)

func _pre_draw() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	_render_pre = began
	_render_frame = Engine.get_process_frames()
	_cost(began)

func _post_draw() -> void:
	if not _active or _finished: return
	var began := Time.get_ticks_usec()
	# Só este sink independente é consumido. SessionSystemProfile conserva take_session().
	var spans: Dictionary = WORK.aggregate_totals.duplicate(true) if _trace_enabled else {}
	var dropped: int = WORK.aggregate_dropped if _trace_enabled else 0
	if _trace_enabled:
		WORK.aggregate_totals.clear()
		WORK.aggregate_dropped = 0
	_dropped_calls += dropped
	# Os contadores da sessão são lidos somente nas bordas da janela, evitando outra
	# chamada ao bridge C# em cada quadro. O custo do perfil GDScript já entra nos brackets.
	if _trace_enabled and _reflections != null and _reflections.is_processing() and _reflections.can_process() and "--benchmark" in OS.get_cmdline_user_args():
		for entry in [["reflection.process", "last_process_usec"], ["reflection.batch", "last_batch_usec"], ["reflection.dynamic", "last_dynamic_usec"], ["reflection.registration", "last_registration_usec"]]:
			var usec: int = int(_reflections.get(entry[1]))
			spans[entry[0]] = {"calls":1, "total_usec":usec, "max_usec":usec}
	if _previous_draw != 0:
		var phase := "warmup"
		if _previous_draw_distance >= _route_total * WARMUP_LOOPS: phase = "measurement"
		elif _distance >= _route_total * WARMUP_LOOPS: phase = "boundary"
		var valid := _process_begin >= _previous_draw and _process_end >= _process_begin and _deferred >= _process_end and _deferred <= _render_pre and _render_pre <= began and _deferred_frame == _process_frame
		var physics_ms := 0.0
		for tick in _ticks:
			physics_ms += float(tick.end_usec - tick.start_usec) / 1000.0
			if int(tick.start_usec) < _previous_draw or int(tick.end_usec) > _process_begin: valid = false
		var timings: Array[Dictionary] = []
		var cpu_total := 0.0
		var gpu_total := 0.0
		for viewport in _viewports:
			var cpu := RenderingServer.viewport_get_measured_render_time_cpu(viewport.rid)
			var gpu := RenderingServer.viewport_get_measured_render_time_gpu(viewport.rid)
			cpu_total += cpu
			gpu_total += gpu
			timings.append({"name":viewport.name, "cpu_ms":cpu, "gpu_ms":gpu})
		var row := {"phase":phase, "process_frame":_process_frame, "physics_frame":Engine.get_physics_frames(), "render_frame":_render_frame,
			"interval_start_usec":_previous_draw, "interval_end_usec":began, "frame_ms":float(began - _previous_draw) / 1000.0,
			"process_begin_usec":_process_begin, "process_end_usec":_process_end, "deferred_usec":_deferred,
			"render_pre_usec":_render_pre, "render_post_usec":began, "phase_valid":valid,
			"physics_steps":_ticks.size(), "physics_steps_engine":Engine.get_physics_frames() - _previous_draw_physics,
			"render_process_counter_offset":_render_frame - _process_frame,
			"physics_ticks":_ticks, "physics_callback_ms":physics_ms,
			"process_callback_ms":float(_process_end - _process_begin) / 1000.0,
			"process_to_deferred_ms":float(_deferred - _process_end) / 1000.0,
			"deferred_to_render_pre_ms":float(_render_pre - _deferred) / 1000.0,
			"render_bracket_ms":float(began - _render_pre) / 1000.0,
			"post_draw_to_physics_ms":float(int(_ticks[0].start_usec) - _previous_draw) / 1000.0 if not _ticks.is_empty() else 0.0,
			"pre_process_gap_ms":float(_process_begin - _previous_draw) / 1000.0 - physics_ms,
			"spans":spans, "span_dropped_calls":dropped, "viewport_timings":timings, "viewport_cpu_total_ms":cpu_total, "viewport_gpu_total_ms":gpu_total,
			"distance_m":_distance, "route_loop":int(_distance / _route_total),
			"position":[car.global_position.x, car.global_position.y, car.global_position.z],
			"telemetry_usec":_telemetry_pending, "focused":DisplayServer.window_is_focused(), "paused":paused,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"monitor_process_ms":Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"monitor_physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"vehicles":world.production.vehicles.size(), "people":world.people.size(),
			"density_scale":world.production.density_scale, "area_density_scale":[world.production.area_density_scale.x, world.production.area_density_scale.y]}
		_samples.append(row)
		if phase == "measurement":
			if _measurement_started == 0:
				_measurement_started = _previous_draw
				_session_telemetry_start = _previous_session_telemetry
				_session_profile_telemetry_start = _previous_session_profile_telemetry
			_measurement_finished = began
			if not valid and "phase_order_invalid" not in _invalid: _invalid.append("phase_order_invalid")
		if _samples.size() >= MAX_FRAMES:
			_invalid.append("sample_capacity_exceeded")
			_finished = true
	_previous_draw = began
	_previous_draw_distance = _distance
	_previous_draw_physics = Engine.get_physics_frames()
	if _measurement_started == 0:
		_previous_session_telemetry = int(_diagnostics.get("TelemetryUsec")) if _diagnostics != null else 0
		_previous_session_profile_telemetry = int(_session_profiler.get("_telemetry_total_usec")) if _session_profiler != null else 0
	_ticks = []
	_telemetry_pending = 0
	# Capturar o quadro custa tempo no próximo intervalo e não deve sumir do próprio relatório.
	_cost(began)
	if _distance >= _route_total * (WARMUP_LOOPS + MEASURE_LOOPS) and _measurement_started > 0 and float(_measurement_finished - _measurement_started) / 1000000.0 >= MIN_MEASURE_SECONDS:
		_session_telemetry_end = int(_diagnostics.get("TelemetryUsec")) if _diagnostics != null else 0
		_session_profile_telemetry_end = int(_session_profiler.get("_telemetry_total_usec")) if _session_profiler != null else 0
		_finished = true

func _inventory() -> Dictionary:
	var began := Time.get_ticks_usec()
	var groups: Dictionary = {}
	var pending: Array[Node] = [root]
	var nodes := 0
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		nodes += 1
		var script: Variant = node.get_script()
		var path: String = str(script.resource_path) if script != null else "<native>"
		var key := path + "|" + node.get_class()
		if not groups.has(key): groups[key] = {"script":path, "class":node.get_class(), "nodes":0, "process_enabled":0, "physics_enabled":0, "can_process":0, "process_active":0, "physics_active":0, "internal_process_enabled":0, "internal_physics_enabled":0, "audio_playing":0}
		var row: Dictionary = groups[key]
		row.nodes += 1
		if node.is_processing(): row.process_enabled += 1
		if node.is_physics_processing(): row.physics_enabled += 1
		if node.is_processing_internal(): row.internal_process_enabled += 1
		if node.is_physics_processing_internal(): row.internal_physics_enabled += 1
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			if node.playing: row.audio_playing += 1
		if node.can_process():
			row.can_process += 1
			if node.is_processing(): row.process_active += 1
			if node.is_physics_processing(): row.physics_active += 1
		for child in node.get_children(): pending.append(child)
	var rows := groups.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.nodes > b.nodes)
	return {"index":_inventory_index, "phase":"warmup", "engine_usec":began, "distance_m":_distance,
		"position":[car.global_position.x, car.global_position.y, car.global_position.z], "nodes":nodes,
		"scripts":rows, "cost_usec":Time.get_ticks_usec() - began,
		"scope":"scene_tree_callback_enablement_not_visibility_or_callback_invocations; inventory_cost_outside_measurement"}

func _stop_observers() -> void:
	_active = false
	if _trace_enabled: WORK.aggregate_enabled = false
	if RenderingServer.frame_pre_draw.is_connected(_pre_draw): RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_post_draw): RenderingServer.frame_post_draw.disconnect(_post_draw)
	for probe in _probes:
		if is_instance_valid(probe): probe.free()
	_probes.clear()
	if _physics_mismatches > 0: _invalid.append("physics_probe_pair_mismatch")
	if _dropped_calls > 0: _invalid.append("aggregate_labels_overflow")

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var above33 := 0
	var above67 := 0
	for value in sorted:
		total += value
		if value > 33.3: above33 += 1
		if value > 66.7: above67 += 1
	var count := sorted.size()
	return {"count":count, "mean":total / count, "p50":sorted[count / 2], "p95":sorted[mini(count - 1, int(count * .95))],
		"p99":sorted[mini(count - 1, int(count * .99))], "max":sorted[-1], "total":total,
		"above_33_3":above33, "above_66_7":above67}

func _write_report() -> void:
	var fields := ["frame_ms", "physics_callback_ms", "physics_steps", "process_callback_ms", "process_to_deferred_ms", "deferred_to_render_pre_ms", "render_bracket_ms", "pre_process_gap_ms", "viewport_cpu_total_ms", "viewport_gpu_total_ms", "telemetry_usec"]
	var series: Dictionary = {}
	for field in fields: series[field] = []
	var definitions: Dictionary = {}
	var measured := 0
	for row in _samples:
		for span in row.spans:
			definitions[span] = {"kind":"instrumented_aggregate", "inclusive":true, "parent":null, "phase":"unknown",
				"scope":"finish-time assignment; no span timestamps; parentage requires source review; never sum overlapping labels"}
			if str(span).begins_with("reflection."):
				definitions[span] = {"kind":"existing_reflection_benchmark_counter", "inclusive":true, "parent":"reflection.process" if span != "reflection.process" else null, "phase":"process", "source":"res://world/city_look/CoastalPlanarReflections.gd", "scope":"same process callback; batch/dynamic/registration nested in process"}
		if row.phase != "measurement": continue
		measured += 1
		for field in fields: series[field].append(float(row[field]))
	var stats: Dictionary = {}
	for field in fields:
		var values: Array[float] = []
		values.assign(series[field])
		stats[field] = _stats(values)
	var frame_stats: Dictionary = stats.frame_ms
	var elapsed := float(_measurement_finished - _measurement_started) / 1000000.0 if measured > 0 else 0.0
	if elapsed < MIN_MEASURE_SECONDS: _invalid.append("measurement_shorter_than_30_seconds")
	var environment: Dictionary = {}
	for key in ["GETECO_BUILDING_BATCH", "GETECO_PROP_INSTANCING", "GETECO_GROUND_STACK", "HARBOR_SESSION_LOG", "HARBOR_SESSION_PROFILE", "HARBOR_STALL_LOG", "HARBOR_STALL_WORK", "HARBOR_STALL_AGGREGATE", "HARBOR_WEST_CPU_TRACE", "HARBOR_WEST_CPU_SPANS"]:
		environment[key] = OS.get_environment(key)
	var report := {"schema_version":1, "label":label, "invalid":_invalid, "diagnostic_only":true,
		"engine":Engine.get_version_info(), "build":"editor" if OS.has_feature("editor") else ("export_release" if OS.has_feature("release") else "export_debug"),
		"hardware":{"cpu":OS.get_processor_name(), "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method()},
		"settings":{"args":OS.get_cmdline_user_args(), "env":environment, "sem_reflexos":no_reflections, "sem_sombras":no_shadows,
			"trace_enabled":_trace_enabled, "session_profile_present":_session_profiler != null,
			"disabled_scripts":disabled_scripts, "disabled_nodes":_disabled_nodes, "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps,
			"resolution":[root.size.x, root.size.y], "startup":_startup_settings,
			"physics_ticks_per_second":Engine.physics_ticks_per_second, "max_physics_steps_per_frame":Engine.max_physics_steps_per_frame},
		"route":{"points":ROUTE.map(func(point: Vector3) -> Array: return [point.x, point.y, point.z]), "speed_mps":SPEED, "length_m":_route_total,
			"warmup_loops":WARMUP_LOOPS, "measurement_loops":MEASURE_LOOPS, "distance_cap_per_frame_ms":100, "completed_distance_m":_distance},
		"clock":{"measurement_start_usec":_measurement_started, "measurement_end_usec":_measurement_finished, "measured_seconds":elapsed},
		"frames":measured, "fps":float(measured) / maxf(elapsed, .000001), "frame_ms":frame_stats, "stats":stats,
		"samples":_samples, "inventories":_inventories, "span_definitions":definitions, "root_names":[],
		"priority_audit":_priority_audit, "probe_priority":PROBE_PRIORITY, "physics_probe_mismatches":_physics_mismatches,
		"aggregate_dropped_calls":_dropped_calls, "telemetry_total_usec":_telemetry_total, "session_log_path":_session_log_path,
		"session_telemetry":{"start_usec":_session_telemetry_start, "end_usec":_session_telemetry_end, "measured_usec":_session_telemetry_end - _session_telemetry_start,
			"profile_start_usec":_session_profile_telemetry_start, "profile_end_usec":_session_profile_telemetry_end,
			"profile_measured_usec":_session_profile_telemetry_end - _session_profile_telemetry_start,
			"scope":"self-reported callback body cost, excludes native dispatch and writer-thread overhead; boundary access only during measurement"},
		"scope":"Rendered Main; same route/day/weather/camera as benchmark_west_route. Intervals use consecutive frame_post_draw callback entries; current physics and process are bracketed by main-thread probes at priorities -/+200000, including SessionSystemProfile -/+100000. Physics ticks and process are separate; pre_process_gap excludes only callback brackets and includes unobserved work/waits. call_deferred is a queue sentinel after the late process callback, not proof that the message queue is empty. frame_pre_draw/post_draw is a wall bracket, not GPU execution/completion. Viewport/Performance monitors are latest available asynchronous values, not exact spike attribution. StallWorkTrace aggregate is independent and never consumes take_session or logger events; labels are inclusive and may nest, with completion assigned to this interval. No sum of parents/children, no attribution of residual to engine/driver/GPU. Three inventories run only in warmup. Profiler costs stay included; callback bodies are self-timed but dispatch/instrumentation overhead is not completely captured. JSON/stat computation after measurement. Diagnostic instrumentation and uncapped presentation differ from ordinary play; this is not product FPS certification."}
	var folder := "res://evidence/profile-west-cpu-20261013"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join(label + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("PROFILE_WEST_EXPORT_FAILED: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PROFILE_WEST ", JSON.stringify({"label":label, "invalid":_invalid, "frames":measured, "seconds":elapsed, "fps":report.fps, "frame_ms":frame_stats, "output":folder.path_join(label + ".json")}))
