extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func broken_callback() -> void:
	var missing: Variant = null
	missing.intentional_session_diagnostics_failure()

func run() -> void:
	var logger := root.get_node_or_null("SessionDiagnostics")
	if logger == null or str(logger.get("LogPath")).is_empty():
		push_error("DIAGNOSTICS_TEST: missing C# autoload")
		quit(1)
		return
	print("DIAGNOSTICS_TEST stdout marker")
	root.add_child(load("res://tests/diagnostics/SessionFailureProbe.cs").new())
	push_warning("DIAGNOSTICS_TEST warning marker")
	push_error("DIAGNOSTICS_TEST error marker")
	broken_callback.call_deferred()
	await create_timer(2.2).timeout
	paused = true
	await create_timer(1.2, true).timeout
	paused = false
	print("DIAGNOSTICS_TEST continued after script error and pause")
	print("DIAGNOSTICS_TEST_PATH ", logger.get("LogPath"))
	if not str(logger.get("WriterFailure")).is_empty():
		quit(2)
		return
	quit(0)
