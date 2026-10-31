extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Só diagnóstico explícito: --reveal-ab-diagnostic --seconds=62 --no-save.
## ON antes do aquecimento herdado de10s, ON30s, quadro de transição reportado, OFF30s.
## Sem mudanças de logger/rastreio/qualidade/população. O runtime normal continua OFF depois.
const REVEAL_SEGMENT_USEC := 30000000
const REVEAL_WORK := preload("res://runtime/StallWorkTrace.gd")
var _reveal_segments: Array[Dictionary] = []
var _reveal_current: Dictionary = {}
var _reveal_frames: Array[float] = []
var _reveal_gpu: Array[float] = []
var _reveal_cpu: Array[float] = []
var _reveal_transition: Dictionary = {}
var _reveal_invalid: Array[String] = []
var _reveal_previous := 0
var _reveal_previous_focus := false
var _reveal_finished := false
var _reveal_requested_seconds := 0.0
var _reveal_armed_usec := 0
var _reveal_parent_invalid := ""
var _reveal_trace_mode: Dictionary = {}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--reveal-ab-diagnostic" in args or "--reveal-off" in args or "--profile" in args:
		push_error("REVEAL_AB_REQUIRES_EXPLICIT_DIAGNOSTIC_AND_NO_PROFILE_OR_REVEAL_OFF")
		quit(7)
		return
	if OS.get_environment("HARBOR_STALL_LOG") != "1" or REVEAL_WORK.aggregate_enabled:
		push_error("REVEAL_AB_REQUIRES_EXISTING_LOGGER_AND_NO_AGGREGATE")
		quit(7)
		return
	await super.run()
	_finish_reveal_ab()
	var parent_path := output.path_join(label + ".json")
	if FileAccess.file_exists(parent_path):
		var parent_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parent_report is Dictionary: _reveal_parent_invalid = str(parent_report.get("invalid",""))
	_export_reveal_ab()

func settle_load() -> bool:
	_reveal_requested_seconds = seconds
	seconds = maxf(seconds,62.0)
	var settled: bool = await super.settle_load()
	if settled:
		world.camera._exterior_reveal.enabled = true
		_reveal_armed_usec = Time.get_ticks_usec()
	return settled

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _reveal_finished: return
	if _reveal_current.is_empty():
		if not _reveal_transition.is_empty():
			# Nenhuma amostra é descartada: o intervalo inteiro que aplica OFF é reportado aqui.
			_reveal_transition.end_usec = now
			_reveal_transition.frame_ms = float(now-int(_reveal_transition.start_usec))/1000.0
			_reveal_transition.focused_end = DisplayServer.window_is_focused()
			_reveal_transition.process_end = Engine.get_process_frames()
			_reveal_transition.physics_end = Engine.get_physics_frames()
			_reveal_transition.gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			_reveal_transition.render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
			_open_reveal_segment(false,now)
		elif not frames.is_empty():
			var logger := root.get_node_or_null("StallLog")
			if logger == null or not bool(logger.get("_enabled")):
				_fail_reveal_ab("logger_not_active")
				return
			_reveal_trace_mode = {"work":REVEAL_WORK.enabled,"world":world.get_meta("benchmark_trace",false)}
			_open_reveal_segment(true,now)
		return
	if REVEAL_WORK.aggregate_enabled or REVEAL_WORK.enabled != _reveal_trace_mode.work or world.get_meta("benchmark_trace",false) != _reveal_trace_mode.world:
		_fail_reveal_ab("trace_configuration_changed")
		return
	if world.camera._exterior_reveal.enabled != bool(_reveal_current.enabled):
		_fail_reveal_ab("reveal_mode_changed_externally")
		return
	var focused_now := DisplayServer.window_is_focused()
	_reveal_frames.append(float(now-_reveal_previous)/1000.0)
	_reveal_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	_reveal_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	if focused_now and _reveal_previous_focus: _reveal_current.focused_intervals += 1
	else: _reveal_current.unfocused_intervals += 1
	if focused_now != _reveal_previous_focus: _reveal_current.focus_changes.append({"usec":now,"focused":focused_now})
	_reveal_previous = now
	_reveal_previous_focus = focused_now
	if now-int(_reveal_current.start_usec) < REVEAL_SEGMENT_USEC: return
	var was_enabled: bool = _reveal_current.enabled
	_close_reveal_segment(now,true)
	if was_enabled:
		_reveal_transition = {"start_usec":now,"parent_frame_index":frames.size()+1,
			"focused_start":focused_now,"process_start":Engine.get_process_frames(),
			"physics_start":Engine.get_physics_frames(),"release_start_usec":Time.get_ticks_usec()}
		world.camera._exterior_reveal.enabled = false
		_reveal_transition.release_end_usec = Time.get_ticks_usec()
		_reveal_transition.release_usec = int(_reveal_transition.release_end_usec)-int(_reveal_transition.release_start_usec)
	else:
		_finish_reveal_ab()

func _open_reveal_segment(mode: bool, began: int) -> void:
	_reveal_current = {"enabled":mode,"start_usec":began,"requested_usec":REVEAL_SEGMENT_USEC,
		"parent_frame_start_index":frames.size()+1,"process_start":Engine.get_process_frames(),
		"physics_start":Engine.get_physics_frames(),"focused_intervals":0,"unfocused_intervals":0,
		"focus_changes":[],"state_start":state()}
	_reveal_frames.clear()
	_reveal_gpu.clear()
	_reveal_cpu.clear()
	_reveal_previous = began
	_reveal_previous_focus = DisplayServer.window_is_focused()
	print("HARBOR_REVEAL_AB_SEGMENT ",JSON.stringify({"enabled":mode,"start_usec":began}))

func _close_reveal_segment(ended: int, complete: bool) -> void:
	if _reveal_current.is_empty(): return
	_reveal_current.end_usec = ended
	_reveal_current.actual_usec = ended-int(_reveal_current.start_usec)
	_reveal_current.complete = complete
	_reveal_current.parent_frame_end_exclusive = frames.size()+1
	_reveal_current.process_end = Engine.get_process_frames()
	_reveal_current.physics_end = Engine.get_physics_frames()
	_reveal_current.physics_ticks = int(_reveal_current.physics_end)-int(_reveal_current.physics_start)
	_reveal_current.process_frames = int(_reveal_current.process_end)-int(_reveal_current.process_start)
	_reveal_current.frames_ms = _reveal_frames.duplicate()
	_reveal_current.gpu_ms = _reveal_gpu.duplicate()
	_reveal_current.render_cpu_ms = _reveal_cpu.duplicate()
	_reveal_current.summary = super.stats(_reveal_frames)
	_reveal_current.gpu_summary = metric_stats(_reveal_gpu,"ms")
	_reveal_current.render_cpu_summary = metric_stats(_reveal_cpu,"ms")
	_reveal_current.state_end = state()
	_reveal_segments.append(_reveal_current)
	_reveal_current = {}

func _fail_reveal_ab(reason: String) -> void:
	_reveal_invalid.append(reason)
	_finish_reveal_ab()
	_export_reveal_ab()
	push_error("REVEAL_AB_INVALID: "+reason)
	quit(7)

func _finish_reveal_ab() -> void:
	if _reveal_finished: return
	_reveal_finished = true
	if not _reveal_current.is_empty(): _close_reveal_segment(Time.get_ticks_usec(),false)
	if _reveal_segments.size() != 2: _reveal_invalid.append("two_segments_not_completed")
	for row in _reveal_segments:
		if not row.complete: _reveal_invalid.append("partial_segment")
	if is_instance_valid(world): world.camera._exterior_reveal.enabled = false

func stats(values: Array[float]) -> Dictionary:
	_finish_reveal_ab()
	return super.stats(values)

func _export_reveal_ab() -> void:
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	var report := {"label":label,"segments":_reveal_segments,"transition":_reveal_transition,
		"finished":_reveal_finished,"invalid":_reveal_invalid,"parent_invalid":_reveal_parent_invalid,
		"armed_before_warmup_usec":_reveal_armed_usec,"inherited_warmup_seconds":10,
		"requested_seconds":_reveal_requested_seconds,"effective_parent_seconds":seconds,
		"parent_timeout_seconds":240,"trace_mode_unchanged":_reveal_trace_mode,
		"configuration":{"max_physics_steps":Engine.max_physics_steps_per_frame,
			"physics_hz":Engine.physics_ticks_per_second,"max_fps":Engine.max_fps,
			"vsync":DisplayServer.window_get_vsync_mode(),"resolution":str(root.size)},
		"scope":"Explicit same-process diagnostic, not an FPS certification. Live traffic/population and external load vary. ON precedes inherited10s warmup; full ON/OFF30s windows use process callback boundaries. The intervening whole frame includes state/statistics overhead, synchronous release and the next engine frame; it is reported separately, never hidden. No file export between windows. Parent frame indexes are zero-based, end-exclusive for complete segments. GPU/renderCPU are root viewport measurements, not exclusive main-thread time. Logger, detailed traces, quality, physics frequency and population stay unchanged. ExteriorReveal is OFF afterward; CityLook silhouette is untouched."}
	FileAccess.open(output.path_join(label+"-reveal-ab.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
