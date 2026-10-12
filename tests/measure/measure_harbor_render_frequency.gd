extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Diagnostic only: original30s -> render cap30fps for30s -> original30s.
## Physics remains60Hz/max3, all production systems stay active. No aggregate sink.
const FREQUENCY_WORK := preload("res://runtime/StallWorkTrace.gd")
const FREQUENCY_SEGMENT_USEC := 30000000
const FREQUENCY_BIN_USEC := 5000000
var _frequency_probe
var _frequency_tid := 0
var _frequency_original := -1
var _frequency_modes: Array[int] = []
var _frequency_segments: Array[Dictionary] = []
var _frequency_transitions: Array[Dictionary] = []
var _frequency_current: Dictionary = {}
var _frequency_transition: Dictionary = {}
var _frequency_frames: Array[float] = []
var _frequency_bin_frames: Array[float] = []
var _frequency_bin_start: Dictionary = {}
var _frequency_previous := 0
var _frequency_previous_focus := false
var _frequency_trace: Dictionary = {}
var _frequency_invalid: Array[String] = []
var _frequency_done := false
var _frequency_requested_seconds := 0.0
var _frequency_parent_invalid := ""

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args() or FREQUENCY_WORK.aggregate_enabled or OS.get_environment("HARBOR_STALL_LOG") != "1":
		push_error("RENDER_FREQUENCY_REQUIRES_LOGGER_NO_PROFILER_NO_AGGREGATE")
		quit(7)
		return
	var source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if source == null or not source.can_instantiate():
		push_error("RENDER_FREQUENCY_COMPILED_CPU_PROBE_REQUIRED")
		quit(7)
		return
	_frequency_probe = source.new()
	var anchor: PackedInt64Array = _frequency_probe.ClockAnchor()
	if anchor.size() != 6 or anchor[5] == 0:
		push_error("RENDER_FREQUENCY_NATIVE_MAIN_THREAD_REQUIRED")
		quit(7)
		return
	_frequency_tid = anchor[5]
	# Restore before the inherited240s deadline; _finalize also covers engine quit.
	create_timer(239.0).timeout.connect(_frequency_timeout)
	await super.run()
	_finish_frequency()
	var path := output.path_join(label+".json")
	if FileAccess.file_exists(path):
		var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if report is Dictionary: _frequency_parent_invalid = str(report.get("invalid",""))
	_export_frequency()

func _finalize() -> void:
	_restore_frequency()

func settle_load() -> bool:
	_frequency_requested_seconds = seconds
	seconds = maxf(seconds,92.0)
	return await super.settle_load()

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _frequency_done: return
	if _frequency_modes.is_empty():
		if frames.is_empty(): return
		var logger := root.get_node_or_null("StallLog")
		if logger == null or not bool(logger.get("_enabled")) or Engine.physics_ticks_per_second != 60 or Engine.max_physics_steps_per_frame != 3:
			_abort_frequency("logger_or_physics_configuration_mismatch")
			return
		_frequency_original = Engine.max_fps
		if _frequency_original > 0 and _frequency_original <= 30:
			_abort_frequency("original_cap_not_above_30")
			return
		_frequency_modes.assign([_frequency_original,30,_frequency_original])
		_frequency_trace = {"work":FREQUENCY_WORK.enabled,"world":world.get_meta("benchmark_trace",false)}
		_open_frequency(now)
		return
	if Engine.physics_ticks_per_second != 60 or Engine.max_physics_steps_per_frame != 3 or FREQUENCY_WORK.aggregate_enabled or FREQUENCY_WORK.enabled != _frequency_trace.work or world.get_meta("benchmark_trace",false) != _frequency_trace.world:
		_abort_frequency("physics_or_trace_configuration_changed")
		return
	if not _frequency_transition.is_empty():
		_frequency_transition.callback_end_usec = now
		_frequency_transition.frame_ms = float(now-int(_frequency_transition.callback_start_usec))/1000.0
		_frequency_transition.focused_end = DisplayServer.window_is_focused()
		_open_frequency(now)
		return
	if Engine.max_fps != int(_frequency_current.requested_max_fps):
		_abort_frequency("render_cap_changed_externally")
		return
	var focus := DisplayServer.window_is_focused()
	if _frequency_previous > 0:
		var ms := float(now-_frequency_previous)/1000.0
		_frequency_frames.append(ms)
		_frequency_bin_frames.append(ms)
		if focus and _frequency_previous_focus: _frequency_current.focused_intervals += 1
		else: _frequency_current.unfocused_intervals += 1
	else:
		_frequency_current.complete_frames_start_usec = now
		_frequency_current.first_frame_fringe_usec = now-int(_frequency_current.start.cpu[0])
	_frequency_previous = now
	_frequency_previous_focus = focus
	var elapsed := now-int(_frequency_current.start.cpu[0])
	var segment_end := elapsed >= FREQUENCY_SEGMENT_USEC
	if segment_end or now-int(_frequency_bin_start.cpu[0]) >= FREQUENCY_BIN_USEC:
		var boundary := _frequency_boundary(now)
		if boundary.is_empty():
			_abort_frequency("invalid_native_cpu_boundary")
			return
		var bin := _frequency_difference(_frequency_bin_start,boundary)
		bin["frame_summary"] = super.stats(_frequency_bin_frames)
		bin["partial_initial_frame_excluded"] = _frequency_current.bins.is_empty()
		_frequency_current.bins.append(bin)
		_frequency_bin_start = boundary
		_frequency_bin_frames.clear()
		if segment_end: _close_frequency(boundary,true)
		if not _frequency_invalid.is_empty():
			_abort_frequency("invalid_native_cpu_delta")
			return
		if segment_end:
			if _frequency_segments.size() == 3:
				_finish_frequency()
			else:
				_frequency_transition = {"callback_start_usec":now,"from":Engine.max_fps,
					"to":_frequency_modes[_frequency_segments.size()],"start":boundary,
					"focused_start":focus,"setter_start_usec":Time.get_ticks_usec()}
				Engine.max_fps = _frequency_modes[_frequency_segments.size()]
				_frequency_transition.setter_end_usec = Time.get_ticks_usec()

func _frequency_boundary(callback_usec: int) -> Dictionary:
	var before := Time.get_ticks_usec()
	var cpu: PackedInt64Array = _frequency_probe.Sample()
	var after := Time.get_ticks_usec()
	if cpu.size() != 7 or cpu[5] != 1 or cpu[1] != _frequency_tid: return {}
	return {"cpu":cpu,"sample_call_bracket_usec":[before,after],"callback_usec":callback_usec,
		"process_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),
		"frames_drawn":Engine.get_frames_drawn(),"state":state()}

func _open_frequency(now: int) -> void:
	var boundary := _frequency_boundary(now)
	if boundary.is_empty():
		_abort_frequency("invalid_native_cpu_start")
		return
	if not _frequency_transition.is_empty():
		_frequency_transition["end"] = boundary
		_frequency_transition["cpu_and_counters"] = _frequency_difference(_frequency_transition.start,boundary)
		_frequency_transitions.append(_frequency_transition)
		_frequency_transition = {}
	_frequency_current = {"index":_frequency_segments.size(),"diagnostic_only":true,
		"requested_max_fps":Engine.max_fps,"requested_duration_usec":FREQUENCY_SEGMENT_USEC,
		"start":boundary,"bins":[],"focused_intervals":0,"unfocused_intervals":0}
	_frequency_bin_start = boundary
	_frequency_frames.clear()
	_frequency_bin_frames.clear()
	_frequency_previous = 0
	_frequency_previous_focus = DisplayServer.window_is_focused()
	print("RENDER_FREQUENCY_SEGMENT ",JSON.stringify({"index":_frequency_segments.size(),"max_fps":Engine.max_fps,"cpu_wall_start_usec":boundary.cpu[0]}))

func _frequency_difference(start: Dictionary, end: Dictionary) -> Dictionary:
	var a: PackedInt64Array = start.cpu
	var b: PackedInt64Array = end.cpu
	var wall := b[0]-a[0]
	var kernel := b[2]-a[2]
	var user := b[3]-a[3]
	var valid := wall > 0 and kernel >= 0 and user >= 0 and b[4] >= a[4]
	if not valid: _frequency_invalid.append("nonmonotonic_native_counters")
	var elapsed := maxf(float(wall)/1000000.0,.000001)
	var render_frames := int(end.process_frame)-int(start.process_frame)
	var physics_ticks := int(end.physics_frame)-int(start.physics_frame)
	return {"start":start,"end":end,"native_counters_valid":valid,"wall_usec":wall,
		"main_cpu_usec":kernel+user,"kernel_usec":kernel,"user_usec":user,"cycles":b[4]-a[4],
		"main_cpu_seconds_per_wall_second":float(kernel+user)/1000000.0/elapsed,
		"process_frames":render_frames,"physics_ticks":physics_ticks,
		"actual_process_fps":render_frames/elapsed,"actual_physics_hz":physics_ticks/elapsed,
		"actual_draw_fps":(int(end.frames_drawn)-int(start.frames_drawn))/elapsed,
		"all_main_cpu_per_physics_tick_usec":float(kernel+user)/maxi(1,physics_ticks)}

func _close_frequency(boundary: Dictionary, complete: bool) -> void:
	_frequency_current["totals"] = _frequency_difference(_frequency_current.start,boundary)
	_frequency_current["complete"] = complete
	_frequency_current["frames_ms"] = _frequency_frames.duplicate()
	_frequency_current["frame_summary"] = super.stats(_frequency_frames)
	_frequency_current["end_callback_fringe_usec"] = int(boundary.cpu[0])-int(boundary.callback_usec)
	_frequency_segments.append(_frequency_current)
	_frequency_current = {}

func _restore_frequency() -> void:
	if _frequency_original >= 0: Engine.max_fps = _frequency_original

func _finish_frequency() -> void:
	if _frequency_done:
		_restore_frequency()
		return
	_frequency_done = true
	_restore_frequency()
	if not _frequency_current.is_empty():
		var boundary := _frequency_boundary(Time.get_ticks_usec())
		if not boundary.is_empty(): _close_frequency(boundary,false)
	if _frequency_segments.size() != 3: _frequency_invalid.append("three_complete_segments_required")
	for segment in _frequency_segments:
		if not segment.complete: _frequency_invalid.append("partial_segment")

func _abort_frequency(reason: String) -> void:
	_frequency_invalid.append(reason)
	_finish_frequency()
	_export_frequency()
	push_error("RENDER_FREQUENCY_INVALID: "+reason)
	quit(7)

func _frequency_timeout() -> void:
	if _frequency_done: return
	_abort_frequency("239_second_deadline_before_parent_timeout")

func stats(values: Array[float]) -> Dictionary:
	_finish_frequency()
	var result := super.stats(values)
	result["diagnostic_only"] = true
	result["invalid_for_product_fps"] = true
	return result

func _export_frequency() -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"label":label,"diagnostic_only":true,"invalid_for_product_fps":true,
		"invalid":_frequency_invalid,"parent_invalid":_frequency_parent_invalid,
		"original_max_fps":_frequency_original,"restored_max_fps":Engine.max_fps,
		"segments":_frequency_segments,"transitions":_frequency_transitions,
		"unfinished_transition":_frequency_transition,"trace_unchanged":_frequency_trace,
		"requested_seconds":_frequency_requested_seconds,"effective_parent_seconds":seconds,
		"native_main_thread_id":_frequency_tid,"physics_hz":Engine.physics_ticks_per_second,
		"max_physics_steps":Engine.max_physics_steps_per_frame,
		"thread_columns":["wall_usec","native_thread_id","kernel_usec","user_usec","cycles","valid","processor"],
		"scope":"Temporary render-frequency sensitivity diagnostic, never a product FPS certification. Original30s/cap30fps30s/original30s; no systems, population, quality, traces or physics settings are disabled. Compare ACTUAL frames and physics ticks per wall second with population/moving-traffic state at every5s boundary, not requested frequencies. Native CPU covers all main-thread work and includes boundary observer cost; cycles are not time. Complete-frame summaries exclude the initial partial interval, whose fringe is reported; native CPU includes it. Full callback transition interval, native CPU/counters and setter timestamps are retained. No file exports between segments. Restore max_fps on normal finish, failure,239s diagnostic deadline and MainLoop finalization. Counter failures never fall back to estimated CPU."}
	FileAccess.open(output.path_join(label+"-render-frequency.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
