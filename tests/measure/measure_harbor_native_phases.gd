extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Diagnostic CPU accounting by consecutive native boundary samples, not FPS certification.
const PHASE_WORK := preload("res://runtime/StallWorkTrace.gd")
const PHASE_DURATION := 30000000
const PHASE_BIN := 5000000
const PHASE_LIMIT := 65536
const PHASE_STRIDE := 16
const PHASE_PRIORITY := 2147483647
const PHASE_NAMES := ["window_start", "physics_signal", "physics_callbacks_end", "process_signal", "process_callbacks_end", "draw_pre", "draw_post", "window_end"]

class PhaseEndProbe extends Node:
	var observer: Callable
	func _physics_process(_delta: float) -> void: observer.call(2)
	func _process(_delta: float) -> void: observer.call(4)

var _phase_probe
var _phase_end_node: PhaseEndProbe
var _phase_tid := 0
var _phase_data := PackedInt64Array()
var _phase_count := 0
var _phase_active := false
var _phase_done := false
var _phase_inside := false
var _phase_start := 0
var _phase_end := 0
var _phase_next_state := 0
var _phase_states: Array[Dictionary] = []
var _phase_invalid: Array[String] = []
var _phase_priorities: Array[Dictionary] = []
var _phase_configuration: Dictionary = {}
var _phase_parent: Dictionary = {}
var _phase_observer_usec := 0
var _phase_sample_usec := 0
var _phase_max_observer_usec := 0
var _phase_max_sample_usec := 0
var _phase_reentrant := 0
var _phase_dropped := 0

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args() or PHASE_WORK.aggregate_enabled or OS.get_environment("HARBOR_STALL_LOG") != "1":
		push_error("NATIVE_PHASES_REQUIRE_LOGGER_NO_PROFILE_NO_AGGREGATE")
		quit(7)
		return
	var source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if source == null or not source.can_instantiate():
		push_error("NATIVE_PHASES_REQUIRE_COMPILED_THREAD_CPU")
		quit(7)
		return
	_phase_probe = source.new()
	var anchor: PackedInt64Array = _phase_probe.ClockAnchor()
	if anchor.size() != 6 or anchor[5] == 0:
		push_error("NATIVE_PHASES_REQUIRE_NATIVE_MAIN_THREAD")
		quit(7)
		return
	_phase_tid = anchor[5]
	_phase_data.resize(PHASE_LIMIT*PHASE_STRIDE)
	_phase_end_node = PhaseEndProbe.new()
	_phase_end_node.name = "DiagnosticNativePhaseEnd"
	_phase_end_node.process_priority = PHASE_PRIORITY
	_phase_end_node.process_physics_priority = PHASE_PRIORITY
	_phase_end_node.observer = _phase_event
	root.add_child(_phase_end_node)
	physics_frame.connect(_phase_event.bind(1))
	process_frame.connect(_phase_event.bind(3))
	RenderingServer.frame_pre_draw.connect(_phase_event.bind(5))
	RenderingServer.frame_post_draw.connect(_phase_event.bind(6))
	await super.run()
	_stop_phase()
	var parent_path := output.path_join(label+".json")
	if FileAccess.file_exists(parent_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parsed is Dictionary: _phase_parent = parsed
	_export_phases()

func settle_load() -> bool:
	# One second of parent margin permits a complete30s observer window, which
	# begins after the parent's first complete measured frame (never in warm-up).
	seconds = maxf(seconds,31.0)
	var settled: bool = await super.settle_load()
	if settled: _audit_phase_priorities("before_warmup")
	return settled

func _audit_phase_priorities(phase: String) -> void:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node == _phase_end_node: continue
		if node.process_priority != 0 or node.process_physics_priority != 0 or node.process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
			_phase_priorities.append({"phase":phase,"path":str(node.get_path()),"process_priority":node.process_priority,"physics_priority":node.process_physics_priority,"thread_group":node.process_thread_group})
		# Priority sorting is local to a process group; a separate MAIN_THREAD
		# group also prevents this root sentinel from proving callback ordering.
		if node.process_priority >= PHASE_PRIORITY or node.process_physics_priority >= PHASE_PRIORITY or node.process_thread_group != Node.PROCESS_THREAD_GROUP_INHERIT:
			_phase_error("callback_boundary_priority_or_thread_group: "+str(node.get_path()))
		for child in node.get_children(): pending.append(child)

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _phase_done: return
	if _phase_start == 0:
		if frames.is_empty(): return
		var logger := root.get_node_or_null("StallLog")
		if logger == null or not bool(logger.get("_enabled")) or Engine.physics_ticks_per_second != 60 or Engine.max_physics_steps_per_frame != 3:
			_phase_error("logger_or_physics_configuration_mismatch")
			_phase_done = true
			return
		_phase_configuration = _phase_config()
		_phase_start = Time.get_ticks_usec()
		_phase_active = true
		_phase_event(0)
		_phase_next_state = _phase_start
	# Scalar checks avoid allocating a configuration Dictionary every frame.
	if Engine.physics_ticks_per_second != int(_phase_configuration.physics_hz) or Engine.max_physics_steps_per_frame != int(_phase_configuration.max_physics_steps) or Engine.max_fps != int(_phase_configuration.max_fps) or physics_interpolation != bool(_phase_configuration.interpolation) or DisplayServer.window_get_vsync_mode() != int(_phase_configuration.vsync) or OS.low_processor_usage_mode != bool(_phase_configuration.low_processor_usage_mode) or PHASE_WORK.enabled != bool(_phase_configuration.work) or PHASE_WORK.aggregate_enabled != bool(_phase_configuration.aggregate) or world.get_meta("benchmark_trace",false) != _phase_configuration.world_trace:
		_phase_error("configuration_changed_during_measurement")
	if now-_phase_start >= PHASE_DURATION:
		_stop_phase()
		return
	if now >= _phase_next_state:
		_phase_next_state += PHASE_BIN
		_phase_states.append({"engine_usec":Time.get_ticks_usec(),"state":state(),"events":_phase_count})

func _phase_config() -> Dictionary:
	return {"physics_hz":Engine.physics_ticks_per_second,"max_physics_steps":Engine.max_physics_steps_per_frame,
		"max_fps":Engine.max_fps,"interpolation":physics_interpolation,"vsync":DisplayServer.window_get_vsync_mode(),
		"low_processor_usage_mode":OS.low_processor_usage_mode,"work":PHASE_WORK.enabled,
		"aggregate":PHASE_WORK.aggregate_enabled,"world_trace":world.get_meta("benchmark_trace",false)}

func _phase_error(reason: String) -> void:
	if not _phase_invalid.has(reason): _phase_invalid.append(reason)

func _phase_event(kind: int) -> void:
	if not _phase_active: return
	if _phase_inside:
		_phase_reentrant += 1
		return
	_phase_inside = true
	var before := Time.get_ticks_usec()
	var cpu: PackedInt64Array = _phase_probe.Sample()
	var after := Time.get_ticks_usec()
	if cpu.size() != 7 or cpu[5] != 1 or cpu[1] != _phase_tid:
		_phase_error("invalid_cpu_sample_or_wrong_native_thread")
		_phase_inside = false
		return
	if _phase_count >= PHASE_LIMIT:
		_phase_dropped += 1
		_phase_inside = false
		return
	var offset := _phase_count*PHASE_STRIDE
	_phase_data[offset] = kind
	_phase_data[offset+1] = before
	for i in 7: _phase_data[offset+2+i] = cpu[i]
	_phase_data[offset+9] = after
	_phase_data[offset+10] = Engine.get_process_frames()
	_phase_data[offset+11] = Engine.get_physics_frames()
	_phase_data[offset+12] = Engine.get_frames_drawn()
	_phase_data[offset+13] = int(DisplayServer.window_is_focused())
	_phase_data[offset+14] = int(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)
	_phase_count += 1
	var elapsed := Time.get_ticks_usec()-before
	_phase_data[offset+15] = before+elapsed
	_phase_observer_usec += elapsed
	_phase_sample_usec += after-before
	_phase_max_observer_usec = maxi(_phase_max_observer_usec,elapsed)
	_phase_max_sample_usec = maxi(_phase_max_sample_usec,after-before)
	_phase_inside = false

func _stop_phase() -> void:
	if _phase_done: return
	if _phase_active:
		_phase_event(7)
		_phase_end = Time.get_ticks_usec()
	_phase_active = false
	_phase_done = true
	if _phase_start == 0 or _phase_end-_phase_start < PHASE_DURATION: _phase_error("incomplete_30_second_window")
	if is_instance_valid(world): _phase_states.append({"engine_usec":Time.get_ticks_usec(),"state":state(),"events":_phase_count})
	_audit_phase_priorities("after_measurement")

func stats(values: Array[float]) -> Dictionary:
	_stop_phase()
	var result := super.stats(values)
	result["diagnostic_only"] = true
	return result

func _phase_empty_totals() -> Dictionary:
	return {"intervals":0,"wall_usec":0,"kernel_usec":0,"user_usec":0,"main_cpu_usec":0,"cycles":0,"cross_bin_intervals":0,"unfocused_intervals":0,"minimized_intervals":0,"phases":{}}

func _phase_accumulate(target: Dictionary, key: String, wall: int, kernel: int, user: int, cycles: int, crossing: bool, unfocused: bool, minimized: bool) -> void:
	target.intervals += 1
	target.wall_usec += wall
	target.kernel_usec += kernel
	target.user_usec += user
	target.main_cpu_usec += kernel+user
	target.cycles += cycles
	target.cross_bin_intervals += int(crossing)
	target.unfocused_intervals += int(unfocused)
	target.minimized_intervals += int(minimized)
	if not target.phases.has(key): target.phases[key] = {"intervals":0,"wall_usec":0,"main_cpu_usec":0,"kernel_usec":0,"user_usec":0,"cycles":0}
	var phase: Dictionary = target.phases[key]
	phase.intervals += 1
	phase.wall_usec += wall
	phase.kernel_usec += kernel
	phase.user_usec += user
	phase.main_cpu_usec += kernel+user
	phase.cycles += cycles

func _export_phases() -> void:
	if output.is_empty(): return
	if _phase_reentrant > 0: _phase_error("reentrant_observer")
	if _phase_dropped > 0: _phase_error("event_buffer_overflow")
	if not str(_phase_parent.get("invalid","")).is_empty(): _phase_error("parent_invalid: "+str(_phase_parent.invalid))
	var totals := _phase_empty_totals()
	var bins: Array[Dictionary] = []
	var rows: Array[PackedInt64Array] = []
	var first_usec := _phase_data[2] if _phase_count > 0 else 0
	for index in _phase_count:
		var offset := index*PHASE_STRIDE
		rows.append(_phase_data.slice(offset,offset+PHASE_STRIDE))
		if index == 0: continue
		var previous := offset-PHASE_STRIDE
		var wall := _phase_data[offset+2]-_phase_data[previous+2]
		var kernel := _phase_data[offset+4]-_phase_data[previous+4]
		var user := _phase_data[offset+5]-_phase_data[previous+5]
		var cycles := _phase_data[offset+6]-_phase_data[previous+6]
		if wall < 0 or kernel < 0 or user < 0 or cycles < 0:
			_phase_error("nonmonotonic_native_counters")
			continue
		var bin_index := int((_phase_data[offset+2]-first_usec)/PHASE_BIN)
		var previous_bin := int((_phase_data[previous+2]-first_usec)/PHASE_BIN)
		while bins.size() <= bin_index:
			var bin := _phase_empty_totals()
			bin["index"] = bins.size()
			bin["requested_start_usec"] = first_usec+bins.size()*PHASE_BIN
			bin["requested_end_usec"] = first_usec+(bins.size()+1)*PHASE_BIN
			bins.append(bin)
		var bin: Dictionary = bins[bin_index]
		if not bin.has("first_event_index"):
			bin["first_event_index"] = index-1
			bin["actual_start_usec"] = _phase_data[previous+2]
		bin["last_event_index"] = index
		bin["actual_end_usec"] = _phase_data[offset+2]
		var key := str(PHASE_NAMES[_phase_data[previous]])+" -> "+str(PHASE_NAMES[_phase_data[offset]])
		var unfocused := _phase_data[offset+13] == 0 or _phase_data[previous+13] == 0
		var minimized := _phase_data[offset+14] != 0 or _phase_data[previous+14] != 0
		_phase_accumulate(totals,key,wall,kernel,user,cycles,bin_index != previous_bin,unfocused,minimized)
		_phase_accumulate(bin,key,wall,kernel,user,cycles,bin_index != previous_bin,unfocused,minimized)
	for bin in bins:
		if not bin.has("first_event_index"): continue
		var start: PackedInt64Array = rows[int(bin.first_event_index)]
		var end: PackedInt64Array = rows[int(bin.last_event_index)]
		var duration := maxf(float(bin.wall_usec)/1000000.0,.000001)
		bin["process_frames"] = end[10]-start[10]
		bin["physics_ticks"] = end[11]-start[11]
		bin["drawn_frames"] = end[12]-start[12]
		bin["actual_process_fps"] = bin.process_frames/duration
		bin["actual_physics_hz"] = bin.physics_ticks/duration
		bin["main_cpu_seconds_per_wall_second"] = float(bin.main_cpu_usec)/1000000.0/duration
	if totals.unfocused_intervals > 0 or totals.minimized_intervals > 0: _phase_error("native_phase_window_lost_presentation")
	var report := {"label":label,"diagnostic_only":true,"invalid_for_product_fps":true,
		"invalid":_phase_invalid,"parent_invalid":_phase_parent.get("invalid","missing_parent_report"),
		"native_main_thread_id":_phase_tid,"configuration_unchanged":_phase_configuration,
		"requested_duration_usec":PHASE_DURATION,"observer_start_usec":_phase_start,"observer_end_usec":_phase_end,
		"event_names":PHASE_NAMES,"event_columns":["event","callback_enter_usec","cpu_wall_usec","native_tid","kernel_usec","user_usec","cycles","valid","processor","sample_return_usec","process_frame","physics_frame","frames_drawn","focused","minimized","callback_work_end_usec"],
		"events":rows,"event_count":_phase_count,"event_limit":PHASE_LIMIT,"dropped":_phase_dropped,"reentrant":_phase_reentrant,
		"sample_call_wall_usec":_phase_sample_usec,"sample_call_max_usec":_phase_max_sample_usec,
		"observer_body_wall_usec":_phase_observer_usec,"observer_body_max_usec":_phase_max_observer_usec,
		"totals":totals,"bins":bins,"states":_phase_states,"priority_audit":_phase_priorities,
		"parent_clock":_phase_parent.get("clock",{}),"native_presentation":_phase_parent.get("native_presentation",{}),
		"scope":"Diagnostic only, normal Main systems/motion/population, physics60Hz/max3, no cap/interpolation/trace changes. Signals and highest-priority Node callbacks delimit consecutive sample pairs; phases are literal boundaries, not exclusive engine subsystem claims. physics_signal->physics_callbacks_end includes script/native callbacks and signal observers; process_signal->process_callbacks_end includes parent observers and process callbacks. Remaining gaps may contain FTI, transform notifications, deferred calls, native physics, rendering, limiter sleep/spin and other work; do not label them exclusively. All pairs telescope without parent/child overlap, including multiple physics ticks. Windows thread CPU is coarse; short pairs can have zero or CPU greater than wall, so assess aggregate seconds, not per-event utilization. Cycles are not time. Bins assign each entire interval to its ending sample and report cross-bin pairs, exact edges and event indices; never prorate CPU. Observer sampling/body wall costs are included and reported, not subtracted; callback dispatch, guards/bookkeeping after timing and bin-state collection add unmeasured observer cost. state() runs only at5s boundaries; inherited1s census remains unchanged. Before/after priority audits cannot exclude transient priority/thread-group mutations; signal connection order and callbacks outside ordinary Node process groups limit exclusivity. Unexpected boundary pairs remain in raw data and totals. Initial/final partial-frame edges are retained as window_start/window_end pairs. Rendering signals are main-thread bracket events, not GPU completion. JSON is exported only after measurement; parent screenshot is outside this window."}
	if _phase_count > 0:
		report["start_fringe_usec"] = first_usec-_phase_start
		report["end_fringe_usec"] = _phase_end-rows[-1][2]
		var first: PackedInt64Array = rows[0]
		var last: PackedInt64Array = rows[-1]
		var duration := maxf(float(totals.wall_usec)/1000000.0,.000001)
		totals["process_frames"] = last[10]-first[10]
		totals["physics_ticks"] = last[11]-first[11]
		totals["drawn_frames"] = last[12]-first[12]
		totals["actual_process_fps"] = totals.process_frames/duration
		totals["actual_physics_hz"] = totals.physics_ticks/duration
		totals["main_cpu_seconds_per_wall_second"] = float(totals.main_cpu_usec)/1000000.0/duration
		totals["telescoping_cpu_check_usec"] = last[4]+last[5]-first[4]-first[5]-int(totals.main_cpu_usec)
		if int(totals.telescoping_cpu_check_usec) != 0: _phase_error("cpu_pair_totals_do_not_telescope")
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-native-phases.json"),FileAccess.WRITE)
	if file == null:
		push_error("NATIVE_PHASES_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("NATIVE_PHASES ",JSON.stringify({"events":_phase_count,"invalid":_phase_invalid,"totals":totals}))
	if not _phase_invalid.is_empty(): quit(7)
