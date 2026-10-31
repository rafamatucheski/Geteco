extends SceneTree
## Rendered Windows test: animation must keep presenting during a blocked main thread.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless": quit(2); return
	root.title = "Geteco Loading Presenter Test"
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	DisplayServer.window_move_to_foreground()
	var curtain = load("res://runtime/StartupCurtain.gd").new()
	root.add_child(curtain)
	curtain.set_stage(.25,"Teste de apresentação")
	await curtain.prepare_presentation()
	if not is_instance_valid(curtain._presenter):
		push_error("Independent presenter did not initialize")
		quit(1)
		return
	DisplayServer.window_move_to_foreground()
	print("NATIVE_LOADING_READY focus=",root.has_focus()," helper_processing=",curtain._presenter.is_processing()," cover_visible=",curtain._root.is_visible_in_tree()," alpha=",curtain._root.modulate.a)
	var focus_deadline := Time.get_ticks_msec()+30000
	while not bool(curtain._presenter.Snapshot().visibility.shown) and Time.get_ticks_msec()<focus_deadline:
		await process_frame
	if not bool(curtain._presenter.Snapshot().visibility.shown):
		push_error("Loading test requires its game window in foreground")
		quit(3)
		return
	print("NATIVE_LOADING_FOCUSED")
	await create_timer(8.0).timeout
	var world := Node3D.new()
	root.add_child(world)
	curtain.reparent(world)
	await process_frame
	var before: Dictionary = curtain._presenter.Snapshot()
	# Diagnostic only: a deliberate synchronous pause, not a simulated FPS result.
	OS.delay_msec(3000)
	var after: Dictionary = curtain._presenter.Snapshot()
	var frames := int(after.frames)-int(before.frames)
	var ok: bool = frames >= 140 and after.failure.is_empty()
	print("NATIVE_LOADING_BLOCK ","PASS" if ok else "FAIL"," frames_during_3s_main_pause=",frames," p95_ms=",after.p95_ms," max_ms=",after.max_ms," failure=",after.failure," visibility=",after.get("visibility",{}))
	root.size = Vector2i(960,540)
	await create_timer(1.0).timeout
	var resized: Dictionary = curtain._presenter.Snapshot()
	ok = ok and int(resized.width) == 960 and int(resized.height) == 540
	root.mode = Window.MODE_FULLSCREEN
	var fullscreen_start: Dictionary = curtain._presenter.Snapshot()
	await create_timer(30.0).timeout
	var fullscreen: Dictionary = curtain._presenter.Snapshot()
	var steady: Array = Array(fullscreen.intervals_ms).slice(int(fullscreen_start.frames))
	var sorted := steady.duplicate()
	sorted.sort()
	var p95: float = sorted[int((sorted.size()-1)*.95)] if not sorted.is_empty() else INF
	var p99: float = sorted[int((sorted.size()-1)*.99)] if not sorted.is_empty() else INF
	ok = ok and steady.size() >= 1400 and p95 <= 25.0 and p99 <= 33.3
	ok = ok and is_equal_approx(float(fullscreen.displayed_progress), .25)
	ok = ok and float(fullscreen.animation_seconds)-float(fullscreen_start.animation_seconds) >= 28.0
	print("NATIVE_LOADING_FULLSCREEN frames=",steady.size()," p95_ms=",p95," p99_ms=",p99," progress=",fullscreen.displayed_progress)
	var physical := DisplayServer.window_get_size()
	# O host de tela cheia do Windows tem 2 pixels extras de cliente neste motor;
	# a cobertura precisa incluir a tela visível inteira, só com essa margem.
	ok = ok and int(fullscreen.width) == physical.x and int(fullscreen.height) in [physical.y,physical.y+2]
	print("NATIVE_LOADING_RESIZE ",resized.width,"x",resized.height," fullscreen=",fullscreen.width,"x",fullscreen.height," expected=",physical)
	var report: Dictionary = {}
	curtain.presentation_finished.connect(func(result: Dictionary): report.assign(result))
	curtain.lift(1)
	await create_timer(1.5).timeout
	ok = ok and not is_instance_valid(curtain) and not report.is_empty()
	world.queue_free()
	var output := "res://artifacts/loading-smooth-20261022/presenter-block-test.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): output = arg.trim_prefix("--report=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var hashes := {}
	for path in ["ui/LoadingPresenter.cs","ui/LoadingCanvas.cs","runtime/StartupCurtain.gd","ui/MainMenu.gd","ui/SkyMenu.gd","runtime/ProductionWorld.gd","tests/test_loading_presenter.gd",".godot/mono/temp/bin/Debug/Harbor.dll"]:
		hashes[path] = FileAccess.get_sha256("res://"+path)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":ok,"source_hashes":hashes,"frames_during_3s_main_pause":frames,"fullscreen_p95_ms":p95,"fullscreen_p99_ms":p99,"presentation":report,"resized":resized,"fullscreen":fullscreen},"\t"))
	print("NATIVE_LOADING_LIFECYCLE ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
