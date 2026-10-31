@tool
extends EditorPlugin
## Só para teste: o runner raiz habilita este plugin temporariamente no próprio editor.
## Ele nunca se habilita sozinho, não persiste configurações do projeto nem controla apps externos.

const RUN_ARGS := "editor/run/main_run_args"
const TOTAL_TIMEOUT_MS := 300000
const WARMUP_SECONDS := 45.0
const OBSERVATION_SECONDS := 30.0
var _output := ""
var _started_ms := 0
var _previous_args: Variant
var _had_args := false
var _args_changed := false
var _owns_play_request := false
var _owned_scene := ""
var _may_close_editor := true
var _finished := false
var _events: Array[Dictionary] = []
var _failures: Array[String] = []
var _completed_cycles := 0

func _enter_tree() -> void:
	set_process(false)
	_started_ms = Time.get_ticks_msec()
	_output = OS.get_environment("GETECO_USAGE_TEST_OUT")
	if _output.is_empty():
		push_error("Editor usage test requires GETECO_USAGE_TEST_OUT; no Play was requested.")
		_finished = true
		return
	if not _output.is_absolute_path(): _output = ProjectSettings.globalize_path("res://" + _output)
	if not _output.to_lower().ends_with(".json"): _output = _output.path_join("editor-flow.json")
	if FileAccess.file_exists(_output):
		push_error("Editor usage test refuses to overwrite existing evidence: " + _output)
		_finished = true
		return
	var error := DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
	if error != OK:
		push_error("Editor usage test cannot create its evidence directory: " + str(error))
		_finished = true
		return
	_run.call_deferred()

func _run() -> void:
	_record("driver_started", {"editor_pid": OS.get_process_id(), "engine": Engine.get_version_info().get("string", "")})
	if EditorInterface.is_playing_scene():
		_may_close_editor = false
		_fail("An existing play session is active; it was not stopped.")
		await _finish()
		return
	var scan_deadline := mini(_started_ms + TOTAL_TIMEOUT_MS, Time.get_ticks_msec() + 60000)
	while EditorInterface.get_resource_filesystem().is_scanning() and Time.get_ticks_msec() < scan_deadline:
		await get_tree().create_timer(0.25).timeout
	if EditorInterface.get_resource_filesystem().is_scanning():
		_fail("Resource scan exceeded its finite deadline.")
		await _finish()
		return
	_record("filesystem_ready")
	_had_args = ProjectSettings.has_setting(RUN_ARGS)
	_previous_args = ProjectSettings.get_setting(RUN_ARGS, "")
	var temporary_args := str(_previous_args)
	# Esta configuração é lida pelo editor; o separador põe estas chaves em
	# OS.get_cmdline_user_args() no filho. Os argumentos existentes ficam intactos.
	if not ("--" in temporary_args.split(" ", false)): temporary_args += " --"
	temporary_args += " --no-save --skip-arrival"
	ProjectSettings.set_setting(RUN_ARGS, temporary_args.strip_edges())
	_args_changed = true
	_record("temporary_run_args_set", {"previous": _previous_args, "temporary": temporary_args.strip_edges(), "persisted": false})
	for cycle in range(1, 3):
		if EditorInterface.is_playing_scene():
			_may_close_editor = false
			_fail("An unexpected play session appeared before our request.")
			break
		_owns_play_request = true
		_owned_scene = ""
		_record("play_requested", {"cycle": cycle})
		EditorInterface.play_main_scene()
		if not await _wait_playing(true, 60000):
			_fail("Play did not start before the finite deadline, cycle " + str(cycle))
			break
		_owned_scene = EditorInterface.get_playing_scene()
		_record("playing_observed", {"cycle": cycle, "scene": _owned_scene})
		if not await _hold_playing(WARMUP_SECONDS, "warmup", cycle): break
		if not await _hold_playing(OBSERVATION_SECONDS, "observation", cycle): break
		if not await _stop_owned(cycle): break
		_completed_cycles += 1
		# Deixa o recibo assíncrono de restauração assentar antes de outro Play.
		await get_tree().create_timer(5.0).timeout
		_record("between_cycles", {"cycle": cycle})
	await _finish()

func _wait_playing(expected: bool, timeout_ms: int) -> bool:
	var deadline := mini(_started_ms + TOTAL_TIMEOUT_MS, Time.get_ticks_msec() + timeout_ms)
	while Time.get_ticks_msec() < deadline:
		if EditorInterface.is_playing_scene() == expected: return true
		await get_tree().create_timer(0.25).timeout
	return EditorInterface.is_playing_scene() == expected

func _hold_playing(seconds: float, phase: String, cycle: int) -> bool:
	_record(phase + "_begin", {"cycle": cycle, "seconds": seconds})
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if Time.get_ticks_msec() >= _started_ms + TOTAL_TIMEOUT_MS:
			_fail("The overall 300-second deadline expired.")
			return false
		if not EditorInterface.is_playing_scene():
			_owns_play_request = false
			_fail("The requested game stopped during " + phase + ", cycle " + str(cycle))
			return false
		if EditorInterface.get_playing_scene() != _owned_scene:
			_owns_play_request = false
			_may_close_editor = false
			_fail("The playing scene changed outside the driver; it was not stopped.")
			return false
		await get_tree().create_timer(0.25).timeout
	_record(phase + "_end", {"cycle": cycle})
	return true

func _stop_owned(cycle: int) -> bool:
	if not _owns_play_request: return true
	if not EditorInterface.is_playing_scene():
		_owns_play_request = false
		return true
	if not _owned_scene.is_empty() and EditorInterface.get_playing_scene() != _owned_scene:
		_owns_play_request = false
		_may_close_editor = false
		_fail("Refused to stop a play session different from the one observed.")
		return false
	_record("stop_requested", {"cycle": cycle, "scene": EditorInterface.get_playing_scene()})
	EditorInterface.stop_playing_scene()
	if not await _wait_playing(false, 20000):
		_fail("Editor Stop did not complete before the deadline.")
		return false
	_owns_play_request = false
	_record("stopped_observed", {"cycle": cycle})
	return true

func _restore_args() -> void:
	if not _args_changed: return
	if _had_args: ProjectSettings.set_setting(RUN_ARGS, _previous_args)
	else: ProjectSettings.set_setting(RUN_ARGS, null)
	_args_changed = false
	_record("run_args_restored", {"persisted": false})

func _finish() -> void:
	if _owns_play_request: await _stop_owned(0)
	_restore_args()
	_finished = true
	_record("driver_finished", {"completed_cycles": _completed_cycles, "editor_quit_requested": _may_close_editor})
	if _may_close_editor:
		get_tree().quit(0 if _failures.is_empty() and _completed_cycles == 2 else 1)

func _fail(message: String) -> void:
	_failures.append(message)
	_record("failure", {"message": message})
	push_error(message)

func _record(event: String, detail: Dictionary = {}) -> void:
	_events.append({"event": event, "utc": Time.get_datetime_string_from_system(true, true) + "Z", "unix_seconds": Time.get_unix_time_from_system(), "elapsed_ms": Time.get_ticks_msec() - _started_ms, "detail": detail})
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("Editor usage test could not write evidence: " + _output)
		return
	file.store_string(JSON.stringify({"schema": 1, "editor_pid": OS.get_process_id(), "completed_cycles": _completed_cycles, "finished": _finished, "ok": _finished and _completed_cycles == 2 and _failures.is_empty(), "failures": _failures, "events": _events, "limits": ["Two Play/Stop cycles through the real editor API; window-close/natural child exit is not exercised.", "Readiness uses a fixed 45-second warmup; the external validator must confirm Main/session readiness and inspect the following 30 seconds.", "No FPS collector, screenshots, per-frame callback, quality changes or ProjectSettings.save() are used by this driver.", "The driver records only its editor PID; the external runner owns child PID, process and save-hash observations."]}, "\t"))
	file.close()
	print("EDITOR_USAGE_TEST ", event, " ", JSON.stringify(detail))

func _exit_tree() -> void:
	if _output.is_empty() or _finished: return
	_restore_args()
	_failures.append("Driver removed before its finite sequence completed.")
	_finished = true
	_record("driver_interrupted")
