extends "res://tests/measure/measure_harbor_idle_regression.gd"
## Só diagnóstico: perfil de script/nativo a cada quadro; o receptor acumula os quadros.
## --native-profile-cap=2048 precisa bater com --function-cap do receptor. Não use --profile.
var _native_cap := 2048
var _native_started := 0
var _native_stopped := 0
var _native_start_frame := 0
var _native_stop_frame := 0

func run() -> void:
	if "--profile" in OS.get_cmdline_user_args():
		push_error("Use this runner without --profile; it owns profiler boundaries")
		quit(7)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--native-profile-cap="):
			_native_cap = int(arg.trim_prefix("--native-profile-cap="))
	if _native_cap < 1 or _native_cap > int(ProjectSettings.get_setting("debug/settings/profiler/max_functions",16384)) or not EngineDebugger.is_active():
		push_error("Native profile requires a connected debugger and valid function cap")
		quit(7)
		return
	await super.run()
	_stop_native_profile()
	if _native_started > 0:
		var parent_report: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.path_join(label+".json")))
		var report := {"label":label,"function_cap":_native_cap,"save_native_calls":true,
			"start_usec":_native_started,"end_usec":_native_stopped,
			"start_frame":_native_start_frame,"end_frame":_native_stop_frame,
			"parent_invalid":parent_report.get("invalid","missing_parent_validity") if parent_report is Dictionary else "missing_parent_report",
			"scope":"Diagnostic profiler enabled after warm-up and first measured interval, stopped before report/screenshot. Use receiver per-frame aggregate; final native summary is not cumulative. Profiler overhead and parent validity apply; not a clean FPS benchmark."}
		FileAccess.open(output.path_join(label+"-native-profile-window.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))

func apply_load(now: int) -> void:
	super.apply_load(now)
	if _native_started == 0 and not frames.is_empty():
		_native_started = Time.get_ticks_usec()
		_native_start_frame = Engine.get_process_frames()
		EngineDebugger.profiler_enable("servers",true,[_native_cap,true])
		print("HARBOR_NATIVE_PROFILE_READY ",JSON.stringify({"pid":OS.get_process_id(),"cap":_native_cap,"start_usec":_native_started,"start_frame":_native_start_frame}))

func stats(values: Array[float]) -> Dictionary:
	_stop_native_profile()
	return super.stats(values)

func _stop_native_profile() -> void:
	if _native_started == 0 or _native_stopped != 0: return
	_native_stopped = Time.get_ticks_usec()
	_native_stop_frame = Engine.get_process_frames()
	EngineDebugger.profiler_enable("servers",false,[])

func _finalize() -> void:
	_stop_native_profile()
