extends SceneTree
## Rode duas vezes depois do build C#: ambiente padrão e depois HARBOR_SESSION_PROFILE=1.
## Os marcadores esperados de aviso/erro exercitam a retenção; não são falhas da fixture.
const OPS := preload("res://runtime/SessionOperations.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")
const MARKER := "SESSION_LOGGING_MODES"
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func run() -> void:
	var detailed := OS.get_environment("HARBOR_SESSION_PROFILE") == "1"
	var sink := root.get_node_or_null("SessionDiagnostics")
	if sink == null or str(sink.get("LogPath")).is_empty():
		push_error(MARKER + " missing C# session sink")
		quit(1)
		return
	check(sink.has_node("SystemProfile") == detailed, "SystemProfile opt-in mismatch")
	check(WORK.session_enabled == detailed, "Work instrumentation opt-in mismatch")
	var token := OPS.begin(sink, "logging_mode_fixture", "operation")
	check((token != 0) == detailed, "Operation token opt-in mismatch")
	OPS.finish(token)
	sink.call("RecordProfile", JSON.stringify({"type":"logging_mode_probe"}))
	print(MARKER + " stdout retained")
	push_warning(MARKER + " expected warning")
	push_error(MARKER + " expected error")
	# The writer flushes once per second. Let two complete flush intervals pass.
	await create_timer(2.2).timeout
	var folder := str(sink.get("LogPath"))
	var types: Dictionary = {}
	var stdout_found := false
	var warning_found := false
	var error_found := false
	for filename in DirAccess.get_files_at(folder):
		if not filename.begins_with("session-") or not filename.ends_with(".jsonl"): continue
		var file := FileAccess.open(folder.path_join(filename), FileAccess.READ)
		if file == null: continue
		while not file.eof_reached():
			var line := file.get_line()
			if line.strip_edges().is_empty(): continue
			var envelope: Variant = JSON.parse_string(line)
			if not envelope is Dictionary: continue
			var record: Dictionary = envelope.get("data", {})
			var kind := str(record.get("type", ""))
			types[kind] = true
			if kind == "stdout" and str(record.get("message", "")).contains(MARKER + " stdout retained"):
				stdout_found = true
			if kind == "error" and str(record.get("code", "")).contains(MARKER):
				if int(record.get("error_type", -1)) == 1: warning_found = true
				if int(record.get("error_type", -1)) == 0: error_found = true
		file.close()
	check(types.has("session_start"), "Session start missing")
	check(stdout_found and warning_found and error_found, "Essential stdout/warning/error retention failed")
	for kind in ["metrics", "context_update", "system_metrics", "logging_mode_probe", "operation_begin"]:
		check(types.has(kind) == detailed, "Unexpected record availability: " + kind)
	if not detailed:
		for kind in ["frame_history", "frame_spike", "perf_window"]:
			check(not types.has(kind), "Detailed record leaked into essentials: " + kind)
	check(str(sink.get("WriterFailure")).is_empty(), "Writer failure")
	print(MARKER + " path ", folder)
	if failures.is_empty():
		print("PASS ", MARKER, " detailed=", detailed)
		quit(0)
	else:
		for failure in failures: push_error(MARKER + " FAILED: " + failure)
		quit(1)
