extends SceneTree
const OPS := preload("res://runtime/SessionOperations.gd")
var world
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(120).timeout.connect(func(): push_error("OBSERVABILITY_TIMEOUT"); quit(3))
	var logger := root.get_node("SessionDiagnostics")
	var token := OPS.begin(logger, "fixture", "parent")
	var child := OPS.begin(logger, "fixture", "child", {}, token)
	OPS.finish(child)
	OPS.finish(token)
	var profiler := logger.get_node("SystemProfile")
	var base := Time.get_ticks_usec()
	profiler.set("_previous", base)
	var coverage: Dictionary = profiler.call("_coverage", base+10000, [
		{"start_usec":base-1000,"end_usec":base+6000},
		{"start_usec":base+2000,"end_usec":base+4000},
		{"start_usec":base+8000,"end_usec":base+12000}])
	assert(coverage.retained_slow_spans_union_ms == 8.0 and coverage.unobserved_ms == 2.0, "nested/clipped spans must not double count")
	world = OPS.instantiate(OPS.load_resource("res://Main.tscn", logger), logger)
	world.set_meta("skip_arrival", true)
	OPS.attach(root, world, logger)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.ready_for_play:
		await process_frame
	while true:
		var snapshot: Dictionary = JSON.parse_string(logger.call("RuntimeSnapshot"))
		var loading := false
		for operation in snapshot.active_operations:
			if operation.system == "world" and operation.operation == "startup": loading = true
		if not loading: break
		await process_frame
	await create_timer(1.2).timeout
	var context: Dictionary = profiler.get("_context")
	assert(context.region == "harbor" and context.world_ready)
	assert(context.has("streaming") and context.has("vehicle") and context.has("population"))
	assert(context.inventory.classes.get("MeshInstance3D",0) > 0)
	assert(context.inventory.classes.get("CollisionShape3D",0) > 0)
	var native = load("res://world/places/NativePlace.gd").new()
	native.definition = load("res://world/places/PlaceCatalog.gd").get_definition("sewer_pipe")
	OPS.attach(world, native, logger)
	await create_timer(.6).timeout
	native.queue_free()
	await process_frame
	paused = true
	await create_timer(.2, true).timeout
	paused = false
	var old_cap := Engine.max_fps
	Engine.max_fps = 60
	await create_timer(.2).timeout
	Engine.max_fps = old_cap
	print("OBSERVABILITY_PATH ", logger.get("LogPath"))
	assert(str(logger.get("WriterFailure")).is_empty())
	world.queue_free()
	await process_frame
	print("PASS observability production startup, native lifecycle, inventory, pause/configuration recovery")
	quit()
