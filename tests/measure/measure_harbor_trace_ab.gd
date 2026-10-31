extends "res://tests/measure/measure_harbor_idle_regression.gd"
## ABBA de diagnóstico num mundo vivo só. Selecione --seconds=121 (120 é estendido para121).
## O logger fica ligado; só o rastreio detalhado de trabalho/dispatch muda.
## Sem coletor agregado, profiler de script, reinício de população ou limitação da simulação.
const TRACE_WORK := preload("res://runtime/StallWorkTrace.gd")
const DISPATCH_TRACE := preload("res://gameplay/dispatch/DispatchTrace.gd")
const SEGMENT_USEC := 30000000
const MODES := [true, false, false, true]
var _ab_segments: Array[Dictionary] = []
var _ab_current: Dictionary = {}
var _ab_frames: Array[float] = []
var _ab_previous_usec := 0
var _ab_previous_focus := false
var _ab_invalid: Array[String] = []
var _ab_original: Dictionary = {}
var _ab_done := false
var _ab_requested_seconds := 0.0
var _ab_parent_invalid := ""
var _ab_cpu_probe
var _ab_main_thread_id := 0
var _ab_clock_anchor := PackedInt64Array()

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args() or TRACE_WORK.aggregate_enabled or OS.get_environment("HARBOR_STALL_AGGREGATE") == "1":
		push_error("TRACE_AB_REQUIRES_PROFILER_AND_AGGREGATE_DISABLED")
		quit(7)
		return
	if OS.get_environment("HARBOR_STALL_LOG") != "1":
		push_error("TRACE_AB_REQUIRES_EXISTING_STALL_LOG_ENABLED")
		quit(7)
		return
	var cpu_source := load("res://tests/measure/ThreadCpuProbe.cs") as Script
	if cpu_source == null or not cpu_source.can_instantiate():
		push_error("TRACE_AB_REQUIRES_COMPILED_THREAD_CPU_PROBE")
		quit(7)
		return
	_ab_cpu_probe = cpu_source.new()
	# run() roda na thread principal da SceneTree. Ancora o ID nativo dela antes do início;
	# o próprio Sample() é chamado exatamente duas vezes por segmento concluído, nunca por quadro.
	_ab_clock_anchor = _ab_cpu_probe.ClockAnchor()
	if _ab_clock_anchor.size() != 6 or _ab_clock_anchor[5] == 0:
		push_error("TRACE_AB_NATIVE_MAIN_THREAD_ID_UNAVAILABLE")
		quit(7)
		return
	_ab_main_thread_id = _ab_clock_anchor[5]
	await super.run()
	_finish_ab()
	var parent_path := output.path_join(label + ".json")
	if FileAccess.file_exists(parent_path):
		var parent_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parent_report is Dictionary: _ab_parent_invalid = str(parent_report.get("invalid", ""))
	_export_ab()

func settle_load() -> bool:
	# O parser herdado já rodou. Deixa o timeout total de 240s dele inalterado.
	_ab_requested_seconds = seconds
	seconds = maxf(seconds, 121.0)
	return await super.settle_load()

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _ab_done: return
	if _ab_current.is_empty():
		# O array de quadros do pai só começa depois do aquecimento de dez segundos.
		if frames.is_empty(): return
		var logger := root.get_node_or_null("StallLog")
		if logger == null or not bool(logger.get("_enabled")) or logger.get("_world") != world:
			_fail_ab("logger_not_active_or_world_not_acquired")
			return
		_ab_original = {"work":TRACE_WORK.enabled, "has_meta":world.has_meta("benchmark_trace"),
			"meta":world.get_meta("benchmark_trace",false)}
		_open_segment()
		return
	var mode: bool = _ab_current.enabled
	if TRACE_WORK.aggregate_enabled or TRACE_WORK.enabled != mode or bool(world.get_meta("benchmark_trace",false)) != mode or DISPATCH_TRACE.on != mode:
		_fail_ab("trace_toggle_not_controlling_all_gates")
		return
	var focus := DisplayServer.window_is_focused()
	if _ab_previous_usec == 0:
		# Este primeiro intervalo começou no meio de um quadro de render na troca.
		_ab_current.complete_start_usec = now
		_ab_current.start_fringe_usec = now - int(_ab_current.start_usec)
	else:
		_ab_frames.append(float(now - _ab_previous_usec) / 1000.0)
		if focus and _ab_previous_focus: _ab_current.focused_intervals += 1
		else: _ab_current.unfocused_intervals += 1
		if focus != _ab_previous_focus:
			_ab_current.focus_changes.append({"usec":now,"focused":focus})
	_ab_previous_usec = now
	_ab_previous_focus = focus
	if now - int(_ab_current.start_usec) >= SEGMENT_USEC:
		_close_segment(now, true)
		if not _ab_invalid.is_empty():
			_fail_ab("native_cpu_segment_invalid")
			return
		if _ab_segments.size() == MODES.size():
			_finish_ab()
			_export_ab()
		else:
			# Exporta só entre janelas, nunca serializa nem varre arrays por quadro.
			_export_ab()
			_open_segment()

func _open_segment() -> void:
	var mode: bool = MODES[_ab_segments.size()]
	TRACE_WORK.enabled = mode
	world.set_meta("benchmark_trace",mode)
	# A produção normalmente atualiza no próximo tick de física. Sincroniza o limite,
	# o que também limpa spans/contadores de diagnóstico quando o modo muda de fato.
	DISPATCH_TRACE.refresh(world)
	var context := state()
	var cpu_before := Time.get_ticks_usec()
	var cpu_start: PackedInt64Array = _ab_cpu_probe.Sample()
	var cpu_after := Time.get_ticks_usec()
	if not _valid_ab_cpu(cpu_start):
		_fail_ab("invalid_native_cpu_start")
		return
	var began := cpu_start[0]
	_ab_current = {"index":_ab_segments.size(),"enabled":mode,"requested_usec":SEGMENT_USEC,
		"start_usec":began,"process_start":Engine.get_process_frames(),
		"thread_cpu_start":cpu_start,"cpu_start_call_bracket_usec":[cpu_before,cpu_after],
		"physics_start":Engine.get_physics_frames(),"state_start":context,
		"focused_start":DisplayServer.window_is_focused(),"focused_intervals":0,
		"unfocused_intervals":0,"focus_changes":[],"complete_start_usec":0,
		"work_events_pending_start":TRACE_WORK.events.size(),
		"world_spans_pending_start":world.get_meta("perf_costs",[]).size()}
	_ab_frames.clear()
	_ab_previous_usec = 0
	_ab_previous_focus = DisplayServer.window_is_focused()
	print("HARBOR_TRACE_AB_SEGMENT ",JSON.stringify({"index":_ab_segments.size(),"enabled":mode,"start_usec":began}))

func _close_segment(ended: int, complete: bool) -> void:
	if _ab_current.is_empty(): return
	# Lê antes dos snapshots de estado, da ordenação de quadros e da serialização no limite.
	var cpu_before := Time.get_ticks_usec()
	var cpu_end: PackedInt64Array = _ab_cpu_probe.Sample()
	var cpu_after := Time.get_ticks_usec()
	var cpu_start: PackedInt64Array = _ab_current.thread_cpu_start
	_ab_current.thread_cpu_end = cpu_end
	_ab_current.cpu_end_call_bracket_usec = [cpu_before,cpu_after]
	_ab_current.end_usec = ended
	_ab_current.actual_usec = ended - int(_ab_current.start_usec)
	_ab_current.complete = complete
	_ab_current.process_end = Engine.get_process_frames()
	_ab_current.physics_end = Engine.get_physics_frames()
	_ab_current.process_frames = int(_ab_current.process_end) - int(_ab_current.process_start)
	_ab_current.physics_ticks = int(_ab_current.physics_end) - int(_ab_current.physics_start)
	var cpu_valid := _valid_ab_cpu(cpu_end)
	if cpu_valid:
		cpu_valid = cpu_end[0] > cpu_start[0] and cpu_end[2] >= cpu_start[2] and cpu_end[3] >= cpu_start[3] and cpu_end[4] >= cpu_start[4]
	_ab_current.thread_cpu_valid = cpu_valid
	if cpu_valid:
		var cpu_usec := cpu_end[2]-cpu_start[2]+cpu_end[3]-cpu_start[3]
		var cpu_wall_usec := cpu_end[0]-cpu_start[0]
		_ab_current.thread_cpu_usec = cpu_usec
		_ab_current.thread_kernel_usec = cpu_end[2]-cpu_start[2]
		_ab_current.thread_user_usec = cpu_end[3]-cpu_start[3]
		_ab_current.thread_cycles = cpu_end[4]-cpu_start[4]
		_ab_current.cpu_window_wall_usec = cpu_wall_usec
		_ab_current.thread_cpu_fraction = float(cpu_usec)/cpu_wall_usec
		_ab_current.cpu_window_start_fringe_usec = int(_ab_current.complete_start_usec)-cpu_start[0] if int(_ab_current.complete_start_usec) > 0 else -1
		_ab_current.cpu_window_end_fringe_usec = cpu_end[0]-ended
		# These normalize ALL main-thread work, not isolated physics/render costs.
		_ab_current.all_main_cpu_per_physics_tick_usec = float(cpu_usec)/maxi(1,int(_ab_current.physics_ticks))
		_ab_current.all_main_cpu_per_process_frame_usec = float(cpu_usec)/maxi(1,int(_ab_current.process_frames))
	else:
		_ab_invalid.append("invalid_or_nonmonotonic_native_cpu_end")
	_ab_current.frames_ms = _ab_frames.duplicate()
	_ab_current.summary = super.stats(_ab_frames)
	_ab_current.state_end = state()
	_ab_current.work_events_pending_end = TRACE_WORK.events.size()
	_ab_current.world_spans_pending_end = world.get_meta("perf_costs",[]).size()
	_ab_segments.append(_ab_current)
	_ab_current = {}

func _valid_ab_cpu(sample: PackedInt64Array) -> bool:
	return sample.size() == 7 and sample[5] == 1 and sample[1] == _ab_main_thread_id

func _fail_ab(reason: String) -> void:
	_ab_invalid.append(reason)
	_finish_ab()
	_export_ab()
	push_error("TRACE_AB_INVALID: " + reason)
	quit(7)

func _finish_ab() -> void:
	if _ab_done: return
	_ab_done = true
	if not _ab_current.is_empty(): _close_segment(Time.get_ticks_usec(),false)
	if _ab_segments.size() != MODES.size(): _ab_invalid.append("four_segments_not_completed")
	for row in _ab_segments:
		if not row.complete: _ab_invalid.append("partial_segment")
	if not _ab_original.is_empty() and is_instance_valid(world):
		TRACE_WORK.enabled = _ab_original.work
		if _ab_original.has_meta: world.set_meta("benchmark_trace",_ab_original.meta)
		else: world.remove_meta("benchmark_trace")
		DISPATCH_TRACE.refresh(world)

func stats(values: Array[float]) -> Dictionary:
	_finish_ab()
	return super.stats(values)

func _export_ab() -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"label":label,"modes":MODES,"segment_target_usec":SEGMENT_USEC,
		"requested_seconds":_ab_requested_seconds,"effective_parent_seconds":seconds,
		"parent_timeout_seconds":240,"parent_invalid":_ab_parent_invalid,"invalid":_ab_invalid,
		"segments":_ab_segments,"finished":_ab_done,"logger_enabled":OS.get_environment("HARBOR_STALL_LOG") == "1",
		"aggregate_enabled":false,"source_original_mode":_ab_original,
		"native_main_thread_id":_ab_main_thread_id,"startup_clock_anchor":_ab_clock_anchor,
		"thread_columns":["wall_usec","native_thread_id","kernel_usec","user_usec","cycles","valid","processor"],
		"cpu_scope":"Two native main-thread Sample calls per complete segment, before boundary summaries/export. CPU window is thread_cpu_start[0]..thread_cpu_end[0]; complete frame statistics exclude the reported initial partial-frame fringe. CPU includes that fringe and the small ending callback fringe; no extra readings split their CPU. Kernel/user accounting is coarse and cycles are not time. Per-tick/per-frame normalization divides ALL main-thread CPU, not isolated physics/render CPU. Call brackets expose timestamp uncertainty. Mismatched native thread, failed counters or nonmonotonic samples invalidate the diagnostic; there is no fallback.",
		"configuration":{"max_physics_steps":Engine.max_physics_steps_per_frame,
			"physics_hz":Engine.physics_ticks_per_second,"max_fps":Engine.max_fps,
			"vsync":DisplayServer.window_get_vsync_mode(),"resolution":str(root.size)},
		"scope":"Same-process ABBA diagnostic only, not an FPS certification or deterministic A/B. Live traffic/population, temperature and external load can change. Logger/frame collection remains on; detailed STALL_WORK and benchmark_trace change together. Complete frame intervals exclude the partial first frame after each toggle. State/export work occurs between windows. Pending trace events and async spans can cross toggles; their buffers are retained for the logger. DispatchTrace.refresh resets spans on actual transitions; consecutive off segments do not reset gameplay. Original modes are restored after collection. Parent focus validity and 240s timeout remain in force."}
	FileAccess.open(output.path_join(label + "-trace-ab.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
