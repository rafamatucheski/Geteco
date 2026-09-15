extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var loader := root.get_node("GameLoading")
	root.get_node("SaveManager").set("_save_dir", "D:/geteco/artifacts/opening-freeze-0913/saves/")
	var initial_scene := current_scene
	var started := Time.get_ticks_msec()
	loader.begin("res://world/harbor/HarborGame.tscn", true)
	assert(loader.screen.get_script().resource_path == "res://ui/OpeningLoading.gd")
	assert(loader.screen.find_children("*", "ProgressBar", true, false).is_empty())
	while not is_instance_valid(loader.opening) or not loader.opening._running:
		await process_frame
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("CGI started after ", seconds, " seconds")
	assert(seconds < 7.0)
	assert(not loader.opening.show_studio_intro)
	assert(loader.active)
	# The city must not start building while image and audio are playing.
	var until := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < until:
		assert(current_scene == initial_scene)
		assert(not loader.phase_times_ms.has("scene_ready"))
		await process_frame
	loader.opening.skip()
	while not loader.opening_complete: await process_frame
	# The loader observes completion on the next process_frame as well.
	await process_frame
	assert(loader.screen.get_script().resource_path == "res://ui/LoadingScreen.gd")
	assert(AudioServer.is_bus_mute(0))
	await loader.finished
	await process_frame
	var arrival := current_scene.get_node("ArrivalMission")
	assert(arrival.phase == "disembark")
	assert(not paused)
	assert(loader.screen == null)
	print("OPENING_LOADING_PHASES ", JSON.stringify(loader.phase_times_ms))
	print("PASS New game: CGI within 7s, city waits for film, loading after skip, terminal handoff")
	quit()
