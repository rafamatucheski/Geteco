extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	seed(914)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world: Node = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 180: await process_frame
	world.weather.time_of_day = 0.45
	world.weather.set_weather(0)
	world.weather.set_process(false)
	var rows: Array = []
	for point in [Vector2(700,425), Vector2(-600,1790)]:
		world.get_node("Player").global_position = point
		for i in 120: await process_frame
		var samples: Array[float] = []
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec() - start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now-last)/1000.0)
			last = now
		var total := float(last-start)/1000.0
		var raw := samples.duplicate()
		samples.sort()
		var result := {"point":str(point), "fps":samples.size()*1000.0/total, "frames":samples.size(), "duration_ms":total,
			"p50":samples[int(samples.size()*.5)], "p95":samples[int(samples.size()*.95)], "p99":samples[int(samples.size()*.99)],
			"max":samples[-1], "over_33":samples.filter(func(x): return x>33.3).size(), "over_66":samples.filter(func(x): return x>66.7).size(),
			"gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(),
			"resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "cap":Engine.max_fps, "samples":raw}
		rows.append(result)
		var summary := result.duplicate()
		summary.erase("samples")
		print("CORONER_PERF ", JSON.stringify(summary))
	var suffix := "baseline" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	FileAccess.open("D:/geteco/artifacts/coroner-"+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	quit()
