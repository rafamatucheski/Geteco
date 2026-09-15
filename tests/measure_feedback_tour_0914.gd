extends SceneTree
## Finite production tour sample, isolated saves and identical seeded scene.
var output := "D:/geteco/artifacts/feedback-0914-teste2/baseline-tour"
var samples: Array[float] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	create_timer(240, true, false, true).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves._save_dir = output.path_join("saves") + "/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	seed(14092026)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var state := root.get_node("CampaignState")
	state.reset_campaign()
	for key in ["harbor_arrival_seen","harbor_story_arrival_v2","harbor_police_briefed","harbor_arrival_call_complete"]:
		state.set_campaign_flag(StringName(key),true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null or not current_scene.gameplay_ready or not current_scene.world_build_ready: await process_frame
	while not current_scene.get_node("RoadLighting").ready_for_audit: await process_frame
	# Match production loading before measuring playable frames.
	paused = true
	await preload("res://VehicleGeometryCache.gd").prepare_common_models(self)
	await preload("res://VehicleGeometryCache.gd").prepare_resident_presentations(self)
	await root.get_node("EmergencyPool").prepare_presentations()
	await preload("res://audio/VehicleEngineSound.gd").prepare_catalog(self)
	paused = false
	var world := current_scene
	var intro: Node = world.campaign_controller.story_arrival
	var player: Node2D = world.get_node("Player")
	player.global_position = intro.car.seat(1) + Vector2(0,12)
	world.weather.set_weather(0)
	world.weather.time_of_day = .42
	world.weather.is_dynamic_time = false
	for i in 60: await process_frame
	var start := Time.get_ticks_usec()
	var last := start
	intro._board()
	var observations: Array = []
	var next_report := 0.0
	while Time.get_ticks_usec()-start < 90000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-last)/1000.0)
		last = now
		var seconds := float(now-start)/1000000.0
		if seconds >= next_report:
			var row := {"seconds":seconds,"position":str(intro.car.global_position),"phase":world.campaign_controller.phase,"travelled":intro.car.travelled,"obstacle":intro.car.last_obstacle,"pass_reason":intro.car.pass_reason,"pass_side":intro.car.pass_side,"pass_pending":intro.car.pass_plan != null}
			observations.append(row)
			row["heading"] = intro.car.heading
			row["cursor"] = intro.car.cursor
			row["target"] = str(intro.car.route[intro.car.cursor]) if intro.car.cursor < intro.car.route.size() else "end"
			row["driving"] = intro.car.driving
			row["exit_pending"] = intro.exit_pending
			row["maciota_position"] = str(intro.maciota.global_position)
			row["maciota_visible"] = intro.maciota.visible
			print("TOUR_SAMPLE ",JSON.stringify(row))
			next_report += 10.0
	var sorted := samples.duplicate()
	sorted.sort()
	var result := {"seconds":float(last-start)/1000000.0,"frames":samples.size(),"fps":samples.size()*1000000.0/(last-start),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted[-1],"over33":sorted.filter(func(v): return v>33.3).size(),"over66":sorted.filter(func(v): return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"observations":observations,"samples_ms":samples}
	FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(result))
	result.erase("samples_ms")
	print("TOUR_RESULT ",JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("final.png"))
	quit(0 if world.campaign_controller.phase == "meet_maciota" and not intro.riding and not intro.maciota.visible else 1)
