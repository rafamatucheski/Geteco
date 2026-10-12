extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Explicit diagnostic: cap60 before warm-up, never write Settings or user files.
## All other Main behavior, physics60/max3, graphics and population stay intact.
const CAP_WORK := preload("res://runtime/StallWorkTrace.gd")
var _cap_original := -1
var _cap_applied_usec := 0
var _cap_restored_usec := 0
var _cap_trace: Dictionary = {}
var _cap_invalid: Array[String] = []
var _cap_finished := false

func run() -> void:
	if "--diagnostic-cap60" not in OS.get_cmdline_user_args():
		push_error("CAP60_REQUIRES_EXPLICIT_DIAGNOSTIC_FLAG")
		quit(7)
		return
	if "--profile" in OS.get_cmdline_user_args() or CAP_WORK.aggregate_enabled or OS.get_environment("HARBOR_STALL_LOG") != "1":
		push_error("CAP60_REQUIRES_LOGGER_NO_PROFILER_NO_AGGREGATE")
		quit(7)
		return
	create_timer(239.0).timeout.connect(_cap_timeout)
	await super.run()
	_cap_finished = true
	_restore_cap()
	_export_cap()

func _finalize() -> void:
	_restore_cap()

func settle_load() -> bool:
	var settled: bool = await super.settle_load()
	if not settled: return false
	var logger := root.get_node_or_null("StallLog")
	if Engine.physics_ticks_per_second != 60 or Engine.max_physics_steps_per_frame != 3 or logger == null or not bool(logger.get("_enabled")):
		_cap_invalid.append("logger_or_physics_configuration_mismatch")
		push_error("CAP60_REQUIRES_PHYSICS60_MAX3_AND_LOGGER")
		return false
	_cap_original = Engine.max_fps
	_cap_trace = {"work":CAP_WORK.enabled,"world":world.get_meta("benchmark_trace",false),
		"interpolation":physics_interpolation,"vsync":DisplayServer.window_get_vsync_mode(),
		"low_processor_usage_mode":OS.low_processor_usage_mode}
	# Setup only, before inherited native presentation gate and >=10s warm-up.
	_cap_applied_usec = Time.get_ticks_usec()
	Engine.max_fps = 60
	print("CAP60_DIAGNOSTIC_APPLIED ",JSON.stringify({"original":_cap_original,"temporary":Engine.max_fps,"engine_usec":_cap_applied_usec}))
	return true

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _cap_original < 0: return
	if Engine.max_fps != 60 or Engine.physics_ticks_per_second != 60 or Engine.max_physics_steps_per_frame != 3 or CAP_WORK.aggregate_enabled or CAP_WORK.enabled != bool(_cap_trace.work) or world.get_meta("benchmark_trace",false) != _cap_trace.world or physics_interpolation != bool(_cap_trace.interpolation) or DisplayServer.window_get_vsync_mode() != int(_cap_trace.vsync) or OS.low_processor_usage_mode != bool(_cap_trace.low_processor_usage_mode):
		if _cap_invalid.is_empty(): _cap_invalid.append("configuration_changed_during_measurement")

func _restore_cap() -> void:
	if _cap_original < 0 or _cap_restored_usec != 0: return
	Engine.max_fps = _cap_original
	_cap_restored_usec = Time.get_ticks_usec()

func _cap_timeout() -> void:
	if _cap_finished: return
	_cap_invalid.append("239_second_deadline_before_parent_timeout")
	_restore_cap()
	_export_cap()
	push_error("CAP60_DIAGNOSTIC_TIMEOUT")
	quit(7)

func _export_cap() -> void:
	if output.is_empty(): return
	var parent: Dictionary = {}
	var parent_path := output.path_join(label+".json")
	if FileAccess.file_exists(parent_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(parent_path))
		if parsed is Dictionary: parent = parsed
	if _cap_applied_usec == 0 and not _cap_invalid.has("temporary_cap_not_applied"): _cap_invalid.append("temporary_cap_not_applied")
	var parent_invalid := str(parent.get("invalid","missing_parent_report"))
	if not parent_invalid.is_empty() and not _cap_invalid.has("parent_invalid: "+parent_invalid): _cap_invalid.append("parent_invalid: "+parent_invalid)
	var report := {"label":label,"diagnostic_only":true,"invalid_for_product_fps":true,
		"invalid":_cap_invalid,"original_max_fps":_cap_original,"diagnostic_max_fps":60,
		"restored_max_fps":Engine.max_fps,"applied_usec":_cap_applied_usec,"restored_usec":_cap_restored_usec,
		"unchanged_configuration":_cap_trace,"parent_report":parent_path,
		"summary":parent.get("summary",{}),"gpu_ms":parent.get("gpu_ms",{}),
		"render_cpu_ms":parent.get("render_cpu_ms",{}),"clock":parent.get("clock",{}),
		"native_presentation":parent.get("native_presentation",{}),"states":parent.get("states",[]),
		"scope":"Explicit temporary cap60 diagnostic, set after production settling and before native foreground gate plus >=10s warm-up. No phase changes during measurement, no Settings/user-config writes, no changes to physics60/max3, interpolation, vsync, rendering quality, trace, movement or population. Original Engine.max_fps restored on normal finish,239s timeout and MainLoop finalization. Compare actual measured FPS/frame-time tails and physical-step rate against a separate normal144 baseline; cap30 results do not predict cap60 behavior. Parent states retain physics-frame counters for real tick-rate calculation. No extra per-event CPU observer. Existing StallLog remains active. This diagnostic does not approve a product frame cap or certify unmeasured scenarios."}
	DirAccess.make_dir_recursive_absolute(output)
	var file := FileAccess.open(output.path_join(label+"-cap60.json"),FileAccess.WRITE)
	if file == null:
		push_error("CAP60_DIAGNOSTIC_EXPORT_FAILED")
		quit(7)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if not _cap_invalid.is_empty(): quit(7)
