extends SceneTree
const OPS := preload("res://runtime/SessionOperations.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sink := root.get_node("SessionDiagnostics")
	var probe := Node.new()
	root.add_child(probe)
	# Let the startup incident window finish before provoking a separate stall.
	await create_timer(2.5).timeout
	var token := OPS.begin(probe, "test_loader", "blocking_load", {"region":"fixture"})
	push_error("SESSION_DETAIL intentional error during load")
	# Writer watchdog must retain the active stage even while main thread is blocked.
	OS.delay_msec(6200)
	OPS.finish(token)
	await process_frame
	# Force consumption within a fast interval; details must not depend on frame_spike.
	var profiler := sink.get_node("SystemProfile")
	profiler.call("_process", 0.0)
	# This synthetic interval starts AFTER the manually invoked setup callback.
	# Real engine frame scheduling is covered by the rendered runner.
	profiler.set("_previous", Time.get_ticks_usec())
	var began := WORK.begin()
	OS.delay_msec(3)
	WORK.finish("fixture.small_work", began, {"region":"fixture", "queued_after":7})
	profiler.call("_process", 0.0)
	# More spans than the detail cap: aggregate calls survive, omissions are explicit.
	for i in 20:
		began = WORK.begin()
		OS.delay_msec(3)
		WORK.finish("fixture.bounded", began)
	profiler.call("_process", 0.0)
	began = WORK.begin()
	WORK.finish("retire.fixture", began, {"queued_after":7})
	profiler.call("_process", 0.0)
	sink.call("RecordProfile", "not valid json")
	await create_timer(1.2).timeout
	OPS.begin(probe, "test_loader", "unfinished", {})
	print("SESSION_DETAIL_PATH ", sink.get("LogPath"))
	probe.queue_free()
	quit()
