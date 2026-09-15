extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	seed(4702)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		campaign.set_campaign_flag(flag,true)
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("residence_benchmark_%d" % Time.get_ticks_usec()) + "/"
	saves._save_directory_ready = false
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.get("gameplay_ready"): await process_frame
	var world := current_scene
	var player: Node2D = world.get_node("Player")
	player.set_physics_process(false)
	player.money = 100000
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .36
	world.weather._update_lighting()
	var manager: Node = world.get_node("ResidencePrototype")
	manager.purchase_home("westgate_garden")
	print("RESIDENCE_ENV ",RenderingServer.get_video_adapter_name()," vsync=",DisplayServer.window_get_vsync_mode()," cap=",Engine.max_fps)
	player.global_position = manager.properties.westgate_garden.checkpoint_position()
	await sample("exterior")
	manager.enter_home("westgate_garden")
	while world.get_node("Interiors").is_transitioning(): await process_frame
	await sample("interior")
	world.queue_free()
	await process_frame
	quit()

func sample(label: String) -> void:
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	var duration := float(previous-start)/1000000.0
	samples.sort()
	print("RESIDENCE_PERF ",label," ",JSON.stringify({"frames":samples.size(),"seconds":duration,"fps":samples.size()/duration,"p50":samples[int(samples.size()*.5)],"p95":samples[int(samples.size()*.95)],"p99":samples[int(samples.size()*.99)],"max":samples.back(),"over33":samples.filter(func(x):return x>33.3).size(),"over66":samples.filter(func(x):return x>66.7).size()}))
