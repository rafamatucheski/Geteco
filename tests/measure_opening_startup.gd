extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("SaveManager").set("_save_dir", "D:/geteco/artifacts/opening-freeze-0913/saves/")
	var loader := root.get_node("GameLoading")
	loader.begin("res://world/harbor/HarborGame.tscn", true)
	var deadline := Time.get_ticks_msec() + 45000
	while not is_instance_valid(loader.opening) or not loader.opening._running:
		if Time.get_ticks_msec() > deadline: quit(1); return
		await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 32000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	var duration := (previous - start) / 1000000.0
	var output := FileAccess.open("D:/geteco/artifacts/opening-freeze-0913/latest-frames.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(samples))
	output.close()
	samples.sort()
	var slow := 0
	var stalled := 0
	for sample in samples:
		if sample > 33.3: slow += 1
		if sample > 66.7: stalled += 1
	print("OPENING_METRICS ", JSON.stringify({"frames":samples.size(), "seconds":duration, "fps":samples.size()/duration, "p50":samples[int(samples.size()*.5)], "p95":samples[int(samples.size()*.95)], "p99":samples[int(samples.size()*.99)], "max":samples.back(), "over33":slow, "over66":stalled, "city_started":current_scene != null, "film_seconds":loader.opening._total_elapsed}))
	quit()
