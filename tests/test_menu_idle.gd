extends SceneTree
## A populated save list must not start a world before the player clicks.
## No --no-save flag: it masked the previous automatic-preload regression.
## Every slot is redirected to a unique fixture directory before menu creation.
class IsolatedLaunch extends "res://runtime/SessionLaunch.gd":
	var folder := ""
	func slot_path(id: String) -> String:
		return folder.path_join(id + ".json") if id in ["progress"] + SLOT_IDS else ""

var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" in OS.get_cmdline_user_args():
		push_error("This regression needs the normal menu flags and isolated fixture slots.")
		quit(2)
		return
	var measuring := "--measure" in OS.get_cmdline_user_args()
	if measuring and DisplayServer.get_name() == "headless":
		quit(2)
		return
	var label := "idle"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	var folder := "res://evidence/menu-on-demand-20261002/" + label
	DirAccess.make_dir_recursive_absolute(folder)
	var original := root.get_node("V2Launch")
	root.remove_child(original)
	original.free()
	var launch := IsolatedLaunch.new()
	launch.name = "V2Launch"
	launch.folder = folder.path_join("slots_%d" % Time.get_ticks_usec())
	launch.direct_start_consumed = true
	root.add_child(launch)
	var store = load("res://runtime/SaveStore.gd").new()
	store.path = launch.slot_path("slot_01")
	var state = load("res://runtime/GameState.gd").new()
	if store.save(state) != OK:
		quit(2)
		return
	var save_hash := FileAccess.get_sha256(store.path)
	var settings = root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.vsync = true
	settings.fps_limit = 1
	settings.apply_settings()
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	var started := last
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	var built_world := false
	while Time.get_ticks_usec() - started < (30000000 if measuring else 1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		built_world = built_world or menu.sky.loading or is_instance_valid(menu.sky.world)
	if menu.latest_save.is_empty() or not menu.btn_continue.visible: failures.append("fixture must offer Continue")
	if built_world: failures.append("world/prewarm started before click")
	if FileAccess.get_sha256(store.path) != save_hash: failures.append("menu changed save bytes")
	var sorted := frames.duplicate()
	sorted.sort()
	var elapsed := float(last - started) / 1000000.0
	var summary := {"seconds": elapsed, "frames": frames.size(), "fps": frames.size() / elapsed,
		"p50_ms": sorted[int((sorted.size()-1)*.5)], "p95_ms": sorted[int((sorted.size()-1)*.95)],
		"p99_ms": sorted[int((sorted.size()-1)*.99)], "max_ms": sorted[-1],
		"over_33_3_ms": frames.filter(func(ms): return ms > 33.3).size(),
		"over_66_7_ms": frames.filter(func(ms): return ms > 66.7).size()}
	if measuring:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("menu.png"))
	var report := {"summary": summary, "frames_ms": frames, "failures": failures,
		"world_started": built_world, "engine": Engine.get_version_info().string,
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MENU_IDLE ", JSON.stringify(summary), " failures=", failures)
	menu.queue_free()
	for frame in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
