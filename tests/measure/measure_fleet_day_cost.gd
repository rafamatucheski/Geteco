extends "res://tests/measure/measure_fleet_redesign.gd"
## Diagnostic BAAB only: inherited real Main/setup/acceptance/visuals unchanged.
## Observers add measured cost; these samples do not certify clean FPS.
const COST_CAPACITY := 18000
const LOAD_CAPACITY := 256
const COST_FIELDS := ["observer_begin_usec", "thread_sample_usec", "process_frame",
	"physics_frame", "physics_steps", "wall_interval_usec", "native_thread_id",
	"thread_kernel_usec", "thread_user_usec", "thread_cycles", "thread_sample_valid",
	"processor_number", "gc_gen0", "gc_gen1", "gc_gen2", "gc_pause_usec",
	"thread_allocated_bytes", "focused", "minimized", "observer_usec"]
const LOAD_FIELDS := ["begin_usec", "end_usec", "process_frame", "physics_frame", "probe_usec"]
var _cost_probe
var _gc_probe
var _cost_data := PackedInt64Array()
var _load_data := PackedInt64Array()
var _cost_count := 0
var _load_count := 0
var _cost_overflow := 0
var _load_overflow := 0
var _cost_invalid := 0
var _cost_tid := 0
var _cost_previous_usec := 0
var _cost_previous_physics := 0
var _cost_armed := false
var _cost_phase := "idle"
var _cost_name := ""
var _cost_observer_total := 0
var _cost_observer_max := 0

func run() -> void:
	var confirm_args: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--confirm="): confirm_args.append(arg)
	if confirm_args != ["--confirm=day"]:
		push_error("Fleet day cost requires exactly --confirm=day (four finite BAAB windows)")
		quit(2)
		return
	var cpu_source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	var gc_source := load("res://tests/measure/FleetDayGcProbe.cs") as Script
	if cpu_source == null or gc_source == null or not cpu_source.can_instantiate() or not gc_source.can_instantiate():
		push_error("Fleet day cost requires compiled .NET ThreadCpuProbe and FleetDayGcProbe")
		quit(2)
		return
	_cost_probe = cpu_source.new()
	_gc_probe = gc_source.new()
	var sample: PackedInt64Array = _cost_probe.Sample()
	var gc_sample: PackedInt64Array = _gc_probe.Sample()
	if sample.size() != 7 or sample[5] != 1 or gc_sample.size() != 5:
		push_error("Fleet day cost requires valid native Windows main-thread counters")
		quit(2)
		return
	_cost_tid = sample[1]
	await super.run()

func scenario(night: bool, name_override := "") -> Dictionary:
	_cost_name = name_override
	_cost_phase = "warmup_then_sample"
	_cost_count = 0
	_load_count = 0
	_cost_overflow = 0
	_load_overflow = 0
	_cost_invalid = 0
	_cost_observer_total = 0
	_cost_observer_max = 0
	_cost_data.resize(COST_CAPACITY * COST_FIELDS.size())
	_load_data.resize(LOAD_CAPACITY * LOAD_FIELDS.size())
	var start_anchor: PackedInt64Array = _cost_probe.ClockAnchor()
	var first_sample: PackedInt64Array = _cost_probe.Sample()
	_cost_previous_usec = Time.get_ticks_usec()
	_cost_previous_physics = Engine.get_physics_frames()
	print("FLEET_DAY_COST_PHASE ", JSON.stringify({"phase":"window_begin", "scenario":_cost_name,
		"variant":active_variant, "pid":OS.get_process_id(), "clock_anchor":start_anchor,
		"process_frame":Engine.get_process_frames()}))
	_cost_armed = true
	process_frame.connect(_observe_cost_frame)
	var report: Dictionary = await super.scenario(night, name_override)
	_cost_armed = false
	process_frame.disconnect(_observe_cost_frame)
	_cost_phase = "export_after_window"
	var end_anchor: PackedInt64Array = _cost_probe.ClockAnchor()
	var last_sample: PackedInt64Array = _cost_probe.Sample()
	var rows := _cost_data.slice(0, _cost_count * COST_FIELDS.size())
	var loads := _load_data.slice(0, _load_count * LOAD_FIELDS.size())
	var first_accepted_frame := int(loads[2]) if _load_count > 0 else -1
	var last_accepted_frame := int(loads[(_load_count - 1) * LOAD_FIELDS.size() + 2]) if _load_count > 0 else -1
	var exact_range: bool = report.discarded_focus_frames == 0 and report.sample_complete and _load_overflow == 0
	var report_valid := _cost_overflow == 0 and _load_overflow == 0 and _cost_invalid == 0
	var cost_report := {"scenario":_cost_name, "variant":active_variant, "phase":_cost_phase,
		"purpose":"diagnose CPU running time, wall delay, physics catchup and GC; not clean FPS certification",
		"pid":OS.get_process_id(), "main_thread_id":_cost_tid, "night":night,
		"clock_anchor_fields":["qpc_before", "engine_usec", "utc_filetime_100ns", "qpc_after", "qpc_frequency", "native_thread_id"],
		"clock_anchor_start":start_anchor, "clock_anchor_end":end_anchor,
		"thread_counter_fields":["engine_usec", "native_thread_id", "kernel_usec", "user_usec", "cycles", "valid", "processor"],
		"thread_counters_before":first_sample, "thread_counters_after":last_sample,
		"row_fields":COST_FIELDS, "row_stride":COST_FIELDS.size(), "rows":rows,
		"row_count":_cost_count, "row_capacity":COST_CAPACITY, "overflow_frames":_cost_overflow,
		"invalid_thread_samples":_cost_invalid, "diagnostic_capture_valid":report_valid,
		"load_probe_fields":LOAD_FIELDS, "load_probe_stride":LOAD_FIELDS.size(), "load_probes":loads,
		"load_probe_count":_load_count, "load_probe_overflow":_load_overflow,
		"accepted_frame_range_exact":exact_range,
		"accepted_first_process_frame":first_accepted_frame, "accepted_last_process_frame":last_accepted_frame,
		"parent_summary":report.summary, "parent_sample_complete":report.sample_complete,
		"parent_focus_discards":report.discarded_focus_frames,
		"observer_total_usec":_cost_observer_total, "observer_max_usec":_cost_observer_max,
		"observer_mean_usec":float(_cost_observer_total) / maxi(1, _cost_count),
		"notes":["Observer starts before super.scenario and includes warmup; rows outside accepted range are retained as phase context.",
			"Range uses first/last in-loop load probe process-frame IDs; exact only for complete windows without focus discards and no probe overflow.",
			"Observer callback runs before inherited process-frame continuation; its measured overhead contributes to the parent's current interval and the observer's following interval.",
			"CPU accounting may be coarse; cycles are not milliseconds. Never subtract or sum viewport CPU/GPU to assign unmeasured work.",
			"GC counters are cumulative; allocations include the test probes and existing diagnostics. No forced GC or GetGCMemoryInfo.",
			"Observer cost excludes its final overhead-field assignment/return. load_snapshot duration measures the inherited scan plus timestamp bookkeeping.",
			"SessionSystemProfile remains the existing source of game-system spans; this runner does not enable another profiler.",
			"All packed buffers are finite; overflow is reported and invalidates diagnosis, without dropping parent benchmark frames."]}
	write_json(_cost_name + "-cost", cost_report)
	print("FLEET_DAY_COST_PHASE ", JSON.stringify({"phase":"window_end", "scenario":_cost_name,
		"variant":active_variant, "pid":OS.get_process_id(), "clock_anchor":end_anchor,
		"diagnostic_capture_valid":report_valid, "rows":_cost_count, "observer_max_usec":_cost_observer_max}))
	return report

func _observe_cost_frame() -> void:
	var began := Time.get_ticks_usec()
	if not _cost_armed: return
	if _cost_count >= COST_CAPACITY:
		_cost_overflow += 1
		return
	var cpu: PackedInt64Array = _cost_probe.Sample()
	var gc: PackedInt64Array = _gc_probe.Sample()
	if cpu.size() != 7 or gc.size() != 5:
		_cost_invalid += 1
		return
	if cpu[5] != 1 or cpu[1] != _cost_tid: _cost_invalid += 1
	var physics_now := Engine.get_physics_frames()
	var offset := _cost_count * COST_FIELDS.size()
	_cost_data[offset] = began
	_cost_data[offset + 1] = cpu[0]
	_cost_data[offset + 2] = Engine.get_process_frames()
	_cost_data[offset + 3] = physics_now
	_cost_data[offset + 4] = physics_now - _cost_previous_physics
	_cost_data[offset + 5] = began - _cost_previous_usec
	for index in range(1, 7): _cost_data[offset + 5 + index] = cpu[index]
	for index in range(5): _cost_data[offset + 12 + index] = gc[index]
	_cost_data[offset + 17] = int(DisplayServer.window_is_focused())
	_cost_data[offset + 18] = int(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)
	_cost_previous_usec = began
	_cost_previous_physics = physics_now
	_cost_count += 1
	var overhead := Time.get_ticks_usec() - began
	_cost_observer_total += overhead
	_cost_observer_max = maxi(_cost_observer_max, overhead)
	_cost_data[offset + 19] = overhead

func load_snapshot() -> Dictionary:
	var began := Time.get_ticks_usec()
	var snapshot := super.load_snapshot()
	if _cost_armed:
		if _load_count < LOAD_CAPACITY:
			var offset := _load_count * LOAD_FIELDS.size()
			_load_data[offset] = began
			_load_data[offset + 2] = Engine.get_process_frames()
			_load_data[offset + 3] = Engine.get_physics_frames()
			var ended := Time.get_ticks_usec()
			_load_data[offset + 1] = ended
			_load_data[offset + 4] = ended - began
			_load_count += 1
		else:
			_load_overflow += 1
	return snapshot
