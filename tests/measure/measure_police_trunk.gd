extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): quit(2))
	seed(142)
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.player.teleport(Vector3(59,.1,121))
	world.session.controller.region.set_focus(world.player.position)
	world.session.weather.time_of_day = .45
	for i in 300: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		world.session.personal_car.nearest_action()
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	var elapsed := (previous-start)/1000000.0
	samples.sort()
	print("POLICE_TRUNK_PERF ",JSON.stringify({"frames":samples.size(),"seconds":elapsed,"fps":samples.size()/elapsed,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples.back(),"over33":samples.filter(func(v):return v>33.3).size(),"over66":samples.filter(func(v):return v>66.7).size()}))
	quit()
