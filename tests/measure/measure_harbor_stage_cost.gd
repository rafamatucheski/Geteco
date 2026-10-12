extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Inclusive stage-cost diagnostic, not a clean FPS run. No script profiler.
## Opt in by selecting this runner; regular gameplay keeps aggregation disabled.
const STAGE_WORK := preload("res://runtime/StallWorkTrace.gd")
var _stage_started_usec := 0
var _stage_stopped_usec := 0
var _stage_start_frame := 0
var _stage_start_physics := 0
var _stage_end_frame := 0
var _stage_end_physics := 0
var _stage_totals: Dictionary = {}
var _stage_exported := false
var _stage_bins: Array[Dictionary] = []
var _bin_started_usec := 0
var _bin_start_frame := 0
var _bin_start_physics := 0
var _bin_previous: Dictionary = {}
var _bin_previous_dropped := 0
var _stage_cpu_probe
var _stage_thread_id := 0
var _bin_cpu_start := PackedInt64Array()
var _stage_cpu_invalid: Array[String] = []

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args():
		push_error("HARBOR_STAGE_COST_REQUIRES_PROFILER_DISABLED")
		quit(7)
		return
	var cpu_source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if cpu_source == null or not cpu_source.can_instantiate():
		push_error("HARBOR_STAGE_COST_COMPILED_THREAD_PROBE_UNAVAILABLE")
		quit(7)
		return
	_stage_cpu_probe = cpu_source.new()
	var initial_cpu: PackedInt64Array = _stage_cpu_probe.Sample()
	if initial_cpu.size() != 7 or initial_cpu[5] != 1:
		push_error("HARBOR_STAGE_COST_NATIVE_THREAD_COUNTERS_UNAVAILABLE")
		quit(7)
		return
	_stage_thread_id = initial_cpu[1]
	await super.run()
	_export_stage_cost()

func apply_load(now: int) -> void:
	super.apply_load(now)
	# The base appends frames only after its ten-second warm-up boundary.
	# Start on the next callback, excluding its first measured interval too.
	# Export our exact window rather than pretending it matches the base clock.
	if _stage_started_usec == 0 and not frames.is_empty():
		_stage_started_usec = Time.get_ticks_usec()
		_stage_start_frame = Engine.get_process_frames()
		_stage_start_physics = Engine.get_physics_frames()
		STAGE_WORK.start_aggregate()
		_bin_started_usec = _stage_started_usec
		_bin_start_frame = _stage_start_frame
		_bin_start_physics = _stage_start_physics
		_bin_cpu_start = _sample_stage_cpu()
	if _stage_started_usec > 0 and _stage_stopped_usec == 0:
		var sampled_usec := Time.get_ticks_usec()
		if sampled_usec-_bin_started_usec >= 5000000:
			_capture_stage_bin(sampled_usec,Engine.get_process_frames(),Engine.get_physics_frames())

func stats(values: Array[float]) -> Dictionary:
	# The base computes frame statistics immediately after its sample loop,
	# before report serialization and screenshot capture. Close the sink here.
	_stop_stage_cost()
	return super.stats(values)

func _stop_stage_cost() -> void:
	if _stage_started_usec == 0 or _stage_stopped_usec != 0: return
	_stage_stopped_usec = Time.get_ticks_usec()
	_stage_end_frame = Engine.get_process_frames()
	_stage_end_physics = Engine.get_physics_frames()
	_stage_totals = STAGE_WORK.stop_aggregate()
	_capture_stage_bin(_stage_stopped_usec,_stage_end_frame,_stage_end_physics)

func _capture_stage_bin(ended_usec: int, end_frame: int, end_physics: int) -> void:
	if ended_usec <= _bin_started_usec: return
	var cpu_end := _sample_stage_cpu()
	var current := STAGE_WORK.aggregate_totals.duplicate(true)
	var rows: Array[Dictionary] = []
	for stage_label: String in current:
		var row: Dictionary = current[stage_label]
		var previous: Dictionary = _bin_previous.get(stage_label,{})
		var calls := int(row.calls)-int(previous.get("calls",0))
		var total_usec := int(row.total_usec)-int(previous.get("total_usec",0))
		if calls <= 0: continue
		rows.append({"label":stage_label,"calls":calls,"total_usec":total_usec,"mean_usec":float(total_usec)/calls})
	rows.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.total_usec)>int(b.total_usec))
	var bin := {"start_usec":_bin_started_usec,"end_usec":ended_usec,
		"seconds":float(ended_usec-_bin_started_usec)/1000000.0,
		"process_frames":end_frame-_bin_start_frame,"physics_steps":end_physics-_bin_start_physics,
		"dropped_calls":STAGE_WORK.aggregate_dropped-_bin_previous_dropped,"stages":rows,
		"thread_cpu_start":Array(_bin_cpu_start),"thread_cpu_end":Array(cpu_end),"thread_cpu_valid":false}
	if _valid_stage_cpu(_bin_cpu_start) and _valid_stage_cpu(cpu_end):
		var kernel_usec := cpu_end[2]-_bin_cpu_start[2]
		var user_usec := cpu_end[3]-_bin_cpu_start[3]
		var wall_usec := cpu_end[0]-_bin_cpu_start[0]
		if kernel_usec >= 0 and user_usec >= 0 and wall_usec > 0 and cpu_end[4] >= _bin_cpu_start[4]:
			bin["thread_cpu_valid"] = true
			bin["thread_kernel_usec"] = kernel_usec
			bin["thread_user_usec"] = user_usec
			bin["thread_cpu_usec"] = kernel_usec+user_usec
			bin["thread_sample_wall_usec"] = wall_usec
			bin["thread_cpu_fraction"] = float(kernel_usec+user_usec)/wall_usec
			bin["thread_cycles"] = cpu_end[4]-_bin_cpu_start[4]
		else:
			_stage_cpu_error("nonmonotonic_thread_cpu_sample")
	_stage_bins.append(bin)
	_bin_cpu_start = cpu_end
	_bin_previous = current
	_bin_previous_dropped = STAGE_WORK.aggregate_dropped
	_bin_started_usec = ended_usec
	_bin_start_frame = end_frame
	_bin_start_physics = end_physics

func _valid_stage_cpu(sample: PackedInt64Array) -> bool:
	return sample.size() == 7 and sample[5] == 1 and sample[1] == _stage_thread_id

func _stage_cpu_error(reason: String) -> void:
	if _stage_cpu_invalid.has(reason): return
	_stage_cpu_invalid.append(reason)
	push_error("HARBOR_STAGE_COST_"+reason.to_upper())

func _sample_stage_cpu() -> PackedInt64Array:
	var sample: PackedInt64Array = _stage_cpu_probe.Sample()
	if not _valid_stage_cpu(sample): _stage_cpu_error("invalid_thread_cpu_sample")
	return sample

func _export_stage_cost() -> void:
	if _stage_exported or _stage_started_usec == 0: return
	_stage_exported = true
	_stop_stage_cost()
	var totals := _stage_totals
	var rows: Array[Dictionary] = []
	for stage_label: String in totals.labels:
		var row: Dictionary = totals.labels[stage_label].duplicate()
		row["label"] = stage_label
		row["mean_usec"] = float(row.total_usec)/maxi(1,int(row.calls))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.total_usec)>int(b.total_usec))
	var report := {
		"label":label, "scenario":scenario,
		"start_usec":_stage_started_usec, "end_usec":_stage_stopped_usec,
		"seconds":float(_stage_stopped_usec-_stage_started_usec)/1000000.0,
		"process_frames":_stage_end_frame-_stage_start_frame,
		"physics_steps":_stage_end_physics-_stage_start_physics,
		"dropped_calls":totals.dropped_calls, "max_labels":STAGE_WORK.MAX_AGGREGATE_LABELS,
		"trace_events_enabled":STAGE_WORK.enabled, "stages":rows,
		"bins":_stage_bins,
		"thread_cpu_columns":["wall_usec","native_thread_id","kernel_usec","user_usec","cycles","valid","processor"],
		"thread_cpu_invalid":_stage_cpu_invalid,
		"thread_cpu_scope":"Native current-thread CPU counters bracket each bin independently from its stage timestamps. CPU time has OS accounting granularity; cycles are not elapsed time. Sparse sample/snapshot overhead belongs to the diagnostic run. Invalid samples are explicit and fail the runner; no GDScript counter fallback.",
		"bin_scope":"Approximately five-second wall-clock windows at process boundaries; exact timestamps and frame/physics counts are recorded. Calls are attributed to the window in which they complete. Counts/total times are differences of cumulative snapshots; global totals and maxima remain untouched. Per-bin maxima are intentionally omitted because cumulative maxima cannot be differenced.",
		"scope":"Inclusive wall-clock stage totals including nested script/native work; parent and child labels overlap and must not be summed. Counts include calls below the detailed-event threshold. Observer clock/dictionary overhead remains in the diagnostic run; no CPU/GPU exclusive attribution. Aggregation starts after warm-up and the first measured interval, ends when the base sample loop computes its report, before export/screenshot, and has its own exact window. take() and detailed logging are independent. Uninstrumented callbacks are outside this inventory."
	}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-stage-cost.json"),FileAccess.WRITE)
	if file == null:
		push_error("HARBOR_STAGE_COST_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	print("HARBOR_STAGE_COST ", JSON.stringify({"labels":rows.size(),"seconds":report.seconds,"dropped_calls":totals.dropped_calls}))
	if int(totals.dropped_calls)>0 or not _stage_cpu_invalid.is_empty(): quit(7)

func _finalize() -> void:
	_export_stage_cost()
