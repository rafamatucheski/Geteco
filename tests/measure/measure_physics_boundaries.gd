extends "res://tests/measure/measure_performance_plan.gd"
## Opt-in by choosing this script. Keeps the base Main/scenario/warm-up/sample loop.
## Writes <label>-physics-boundaries.json after the base report. Not a clean FPS run.
const BOUNDARY_NODE := preload("res://tests/measure/PhysicsBoundaryProbe.gd")
const MAX_BOUNDARY_INTERVALS := 12000
const MAX_BOUNDARY_TICKS := 32
const BOUNDARY_PRIORITY := 1000000
const MAX_PRIORITY_ROWS := 128

var boundary_probe: RefCounted
var boundary_nodes: Array[Node] = []
var boundary_rows: Array[Dictionary] = []
var boundary_ticks: Array[Dictionary] = []
var boundary_priority_rows: Array[Dictionary] = []
var boundary_armed := false
var boundary_active := false
var boundary_exported := false
var boundary_error := ""
var boundary_previous := 0
var boundary_previous_physics := 0
var boundary_previous_cpu := PackedInt64Array()
var boundary_thread_id := 0
var boundary_tick_start := 0
var boundary_tick_id := 0
var boundary_tick_cpu := PackedInt64Array()
var boundary_tick_count := 0
var boundary_dropped_ticks := 0
var boundary_dropped_intervals := 0
var boundary_tick_mismatches := 0
var boundary_invalid_cpu := 0
var boundary_process_end_usec := 0
var boundary_process_cpu := PackedInt64Array()
var boundary_pre_usec := 0
var boundary_post_usec := 0
var boundary_pre_cpu := PackedInt64Array()
var boundary_post_cpu := PackedInt64Array()
var boundary_pending_overhead := 0
var boundary_pending_calls := 0

func run() -> void:
	# Do not silently stack the older observers on this bounded diagnostic.
	for key in ["HARBOR_PLAN_WARMUP_IDENTITY", "HARBOR_PLAN_STARTUP_ORPHANS", "HARBOR_STALL_AGGREGATE", "HARBOR_STALL_WORK", "HARBOR_STALL_TRACE", "HARBOR_WCT"]:
		if OS.get_environment(key) == "1":
			push_error("PHYSICS_BOUNDARIES_REQUIRES_DISABLED_OBSERVER: "+key)
			quit(7)
			return
	if "--profile" in OS.get_cmdline_user_args():
		push_error("PHYSICS_BOUNDARIES_REQUIRES_PROFILER_DISABLED")
		quit(7)
		return
	await super.run()
	_stop_boundaries()
	_export_boundaries()

func settle_load() -> bool:
	if not await super.settle_load(): return false
	if scenario not in ["idle", "chaos"]:
		boundary_error = "unsupported_scenario"
		return false
	if not _audit_callback_order(): return false
	var source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if source == null or not source.can_instantiate():
		boundary_error = "compiled_thread_probe_unavailable"
		return false
	boundary_probe = source.new()
	var sample := _boundary_sample()
	if sample.size() != 7 or sample[5] != 1:
		boundary_error = "native_thread_counters_unavailable"
		return false
	boundary_thread_id = sample[1]
	boundary_armed = true
	return true

func _audit_callback_order() -> bool:
	# One scan of the settled scene, before the ten-second warm-up; no node observer.
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var physics_priority := node.process_physics_priority
		var process_priority := node.process_priority
		var thread_group := node.process_thread_group
		if physics_priority != 0 or process_priority != 0 or thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
			if boundary_priority_rows.size() >= MAX_PRIORITY_ROWS:
				boundary_error = "priority_audit_overflow"
				return false
			boundary_priority_rows.append({"path":str(node.get_path()), "physics_priority":physics_priority,
				"process_priority":process_priority, "thread_group":thread_group})
		if absi(physics_priority) >= BOUNDARY_PRIORITY or process_priority >= BOUNDARY_PRIORITY or thread_group == Node.PROCESS_THREAD_GROUP_SUB_THREAD:
			boundary_error = "callback_order_not_bracketed: "+str(node.get_path())
			return false
		for child in node.get_children(): pending.append(child)
	return true

func state() -> Dictionary:
	var row := super.state()
	# First post-settle state is the base READY message, immediately before its loop.
	if boundary_armed and not boundary_active:
		boundary_armed = false
		_start_boundaries()
	row["physics_boundaries"] = {"active":boundary_active, "intervals":boundary_rows.size(),
		"dropped_intervals":boundary_dropped_intervals, "dropped_ticks":boundary_dropped_ticks,
		"tick_mismatches":boundary_tick_mismatches, "invalid_cpu_samples":boundary_invalid_cpu,
		"error":boundary_error, "scope":"Main-thread callback boundaries and native counters; not exclusive solver/GPU attribution or clean gameplay FPS."}
	return row

func _start_boundaries() -> void:
	for first in [true, false]:
		var probe := BOUNDARY_NODE.new()
		probe.name = "PhysicsBoundaryStart" if first else "PhysicsBoundaryEnd"
		probe.recorder = self
		probe.first = first
		probe.process_physics_priority = -BOUNDARY_PRIORITY if first else BOUNDARY_PRIORITY
		probe.process_priority = BOUNDARY_PRIORITY
		root.add_child(probe)
		if first: probe.set_process(false)
		boundary_nodes.append(probe)
	RenderingServer.frame_pre_draw.connect(_boundary_pre_draw)
	RenderingServer.frame_post_draw.connect(_boundary_post_draw)
	boundary_previous = Time.get_ticks_usec()
	boundary_previous_physics = Engine.get_physics_frames()
	boundary_previous_cpu = _boundary_sample()
	boundary_active = true

func _boundary_sample() -> PackedInt64Array:
	var result: PackedInt64Array = boundary_probe.Sample() if boundary_probe != null else PackedInt64Array()
	if result.size() != 7 or result[5] != 1 or (boundary_thread_id != 0 and result[1] != boundary_thread_id):
		boundary_invalid_cpu += 1
	return result

func _boundary_cost(began: int) -> void:
	boundary_pending_overhead += Time.get_ticks_usec()-began
	boundary_pending_calls += 1

func boundary_physics_begin() -> void:
	if not boundary_active: return
	var began := Time.get_ticks_usec()
	if boundary_tick_start != 0: boundary_tick_mismatches += 1
	boundary_tick_start = began
	boundary_tick_id = Engine.get_physics_frames()
	boundary_tick_cpu = _boundary_sample()
	_boundary_cost(began)

func boundary_physics_end() -> void:
	if not boundary_active: return
	var began := Time.get_ticks_usec()
	boundary_tick_count += 1
	if boundary_tick_start == 0 or boundary_tick_id != Engine.get_physics_frames():
		boundary_tick_mismatches += 1
	elif boundary_ticks.size() < MAX_BOUNDARY_TICKS:
		boundary_ticks.append({"physics_frame":boundary_tick_id, "start_usec":boundary_tick_start,
			"end_usec":began, "thread_start":boundary_tick_cpu, "thread_end":_boundary_sample()})
	else:
		boundary_dropped_ticks += 1
	boundary_tick_start = 0
	_boundary_cost(began)

func boundary_process_end() -> void:
	if not boundary_active: return
	var began := Time.get_ticks_usec()
	boundary_process_end_usec = began
	boundary_process_cpu = _boundary_sample()
	_boundary_cost(began)

func _boundary_pre_draw() -> void:
	if not boundary_active: return
	var began := Time.get_ticks_usec()
	boundary_pre_usec = began
	boundary_pre_cpu = _boundary_sample()
	_boundary_cost(began)

func _boundary_post_draw() -> void:
	if not boundary_active: return
	var began := Time.get_ticks_usec()
	boundary_post_usec = began
	boundary_post_cpu = _boundary_sample()
	_boundary_cost(began)

func apply_load(now: int) -> void:
	if boundary_active: _capture_boundaries(now)
	super.apply_load(now)

func _capture_boundaries(now: int) -> void:
	var began := Time.get_ticks_usec()
	var cpu_now := _boundary_sample()
	var physics_now := Engine.get_physics_frames()
	if physics_now-boundary_previous_physics != boundary_tick_count:
		boundary_tick_mismatches += 1
	if boundary_rows.size() < MAX_BOUNDARY_INTERVALS:
		var row := {"start_usec":boundary_previous, "end_usec":now, "process_frame":Engine.get_process_frames(),
			"focused":DisplayServer.window_is_focused(), "physics_steps":physics_now-boundary_previous_physics,
			"completed_ticks":boundary_tick_count, "physics_ticks":boundary_ticks,
			"process_callbacks_end_usec":boundary_process_end_usec, "draw_pre_usec":boundary_pre_usec, "draw_post_usec":boundary_post_usec,
			"draw_pair_valid":boundary_pre_usec >= boundary_previous and boundary_post_usec >= boundary_pre_usec and boundary_post_usec <= now,
			"thread_start":boundary_previous_cpu, "thread_end":cpu_now, "thread_process_end":boundary_process_cpu,
			"thread_draw_pre":boundary_pre_cpu, "thread_draw_post":boundary_post_cpu,
			"pipelines":[Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)],
			"observer_wall_usec":boundary_pending_overhead, "observer_calls":boundary_pending_calls}
		boundary_rows.append(row)
		row["capture_usec"] = Time.get_ticks_usec()-began
	else:
		boundary_dropped_intervals += 1
	boundary_previous = now
	boundary_previous_cpu = cpu_now
	boundary_previous_physics = physics_now
	boundary_ticks = []
	boundary_tick_count = 0
	boundary_process_end_usec = 0
	boundary_pre_usec = 0
	boundary_post_usec = 0
	boundary_process_cpu = PackedInt64Array()
	boundary_pre_cpu = PackedInt64Array()
	boundary_post_cpu = PackedInt64Array()
	boundary_pending_overhead = 0
	boundary_pending_calls = 0
	# Capture runs after the interval's timestamp, so its cost belongs to the next.
	_boundary_cost(began)

func _stop_boundaries() -> void:
	boundary_active = false
	if RenderingServer.frame_pre_draw.is_connected(_boundary_pre_draw): RenderingServer.frame_pre_draw.disconnect(_boundary_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_boundary_post_draw): RenderingServer.frame_post_draw.disconnect(_boundary_post_draw)
	for node in boundary_nodes:
		if is_instance_valid(node): node.free()
	boundary_nodes.clear()

func _export_boundaries() -> void:
	if boundary_exported or output.is_empty(): return
	boundary_exported = true
	var base_report: Variant = null
	var base_path := output.path_join(label+".json")
	if FileAccess.file_exists(base_path): base_report = JSON.parse_string(FileAccess.get_file_as_string(base_path))
	var clock: Dictionary = base_report.get("clock", {}) if base_report is Dictionary else {}
	var sample_rows: Array[Dictionary] = []
	for row in boundary_rows:
		row["phase"] = "warmup"
		if not clock.is_empty() and int(row.start_usec) >= int(clock.measurement_start_usec) and int(row.end_usec) <= int(clock.measurement_end_usec):
			row["phase"] = "measurement"
			sample_rows.append(row)
		elif not clock.is_empty() and int(row.end_usec) > int(clock.measurement_start_usec):
			row["phase"] = "boundary"
	var invalid: Array[String] = []
	if not boundary_error.is_empty(): invalid.append(boundary_error)
	if clock.is_empty(): invalid.append("base_report_missing_clock")
	elif not str(base_report.get("invalid", "")).is_empty(): invalid.append("base_report_invalid: "+str(base_report.invalid))
	if sample_rows.is_empty(): invalid.append("no_measured_boundary_intervals")
	elif sample_rows.size() != int(base_report.get("summary", {}).get("frames", -1)): invalid.append("measured_interval_count_mismatch")
	if boundary_dropped_intervals > 0: invalid.append("interval_overflow")
	if boundary_dropped_ticks > 0: invalid.append("physics_tick_overflow")
	if boundary_tick_mismatches > 0: invalid.append("physics_tick_mismatch")
	if boundary_invalid_cpu > 0: invalid.append("invalid_thread_cpu_sample")
	var report := {"label":label, "scenario":scenario, "invalid":invalid, "clock":clock,
		"intervals":boundary_rows, "measured_intervals":sample_rows.size(), "priority_audit":boundary_priority_rows,
		"max_intervals":MAX_BOUNDARY_INTERVALS, "max_ticks_per_interval":MAX_BOUNDARY_TICKS,
		"dropped_intervals":boundary_dropped_intervals, "dropped_ticks":boundary_dropped_ticks,
		"tick_mismatches":boundary_tick_mismatches, "invalid_cpu_samples":boundary_invalid_cpu,
		"thread_fields":["wall_usec", "native_thread_id", "kernel_usec", "user_usec", "cycles", "valid", "logical_processor"],
		"scope":"Rendered Main with unchanged base scenario. Normal first/last main-thread callbacks bracket script work; native sync/flush/solver outside callbacks remains in gaps. Draw boundaries are wall time, not GPU execution. CPU accounting is coarse, cycles are not time or retired instructions, processor endpoints do not reveal intervening migrations. Observer costs are included, never subtracted; self-timing excludes dispatch overhead. Only intervals within the base clock are measurements; screenshot/serialization tail is excluded. No WCT, per-method aggregates, node observer or manual callback invocation."}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-physics-boundaries.json"), FileAccess.WRITE)
	if file == null:
		push_error("PHYSICS_BOUNDARIES_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PHYSICS_BOUNDARIES ", JSON.stringify({"invalid":invalid, "intervals":boundary_rows.size(), "measured_intervals":sample_rows.size()}))
	if not invalid.is_empty():
		push_error("PHYSICS_BOUNDARIES_INVALID: "+str(invalid))
		quit(7)

func _finalize() -> void:
	_stop_boundaries()
	_export_boundaries()
