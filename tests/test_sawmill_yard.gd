extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	seed(912)
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/sawmill-props-0913/saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	for flag in [&"intro_completed", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	while current_scene == null: await process_frame
	var scene = current_scene
	while not scene.gameplay_ready: await process_frame
	var stream = scene.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	scene.weather.is_dynamic_time = false
	scene.weather.time_of_day = 0.45
	scene.weather.set_weather(0)
	scene.weather._update_lighting()

	var camp: Node2D = stream.mountain.find_child("LoggingCamp",true,false)
	var details: Node2D = camp.get_node("SawmillYardDetails")
	player.global_position = camp.to_global(Vector2(-8,110))
	for i in 60: await physics_frame
	print("SAWMILL active ",details.can_process()," scale ",camp.global_scale)
	var npc: CharacterBody2D = get_nodes_in_group("winter_resident")[0]
	npc.set_physics_process(false)
	var failures := 0
	for actor in [player,npc]:
		
		# Sweep the real body through both long edges and both ends.
		for trial in [[Vector2(40,42),Vector2(0,85)],[Vector2(40,120),Vector2(0,-85)],[Vector2(-15,76),Vector2(110,0)],[Vector2(98,76),Vector2(-110,0)]]:
			actor.global_position = camp.to_global(trial[0])
			await physics_frame
			var blocked: bool = actor.test_move(actor.global_transform,trial[1])
			print("SAWMILL solid sweep ",actor.name," ",trial[0]," ",blocked)
			if not blocked: failures += 1
		actor.global_position = camp.to_global(Vector2(-8,110))
		await physics_frame
		var clear: bool = not actor.test_move(actor.global_transform,Vector2(95,0))
		print("SAWMILL front circulation ",actor.name," ",clear)
		if not clear: failures += 1
		actor.global_position = camp.to_global(Vector2(-140,150))
	var truck: Node2D = camp.get_node("SawmillRanchPickup3D")
	for logger in get_nodes_in_group("winter_resident"):
		if logger.role != "logger": continue
		if logger.work_station.global_position.distance_to(truck.global_position)>150: continue
		logger.set_physics_process(false)
		for side in [-1,1]:
			logger.global_position = logger.work_station.global_position+Vector2(side*13,0)
			await physics_frame
			var collision: bool = logger.test_move(logger.global_transform,Vector2(.01,0),null,.08,true)
			print("SAWMILL logger work side ",side," free=",not collision)
			if collision: failures += 1
	if DisplayServer.get_name() != "headless":
		var camera := Camera2D.new()
		scene.add_child(camera)
		camera.global_position = camp.to_global(Vector2(30,75))
		camera.zoom = Vector2.ONE*3
		camera.make_current()
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/sawmill-props-0913/final.png")
	print("SAWMILL_YARD failures=",failures)
	quit(0 if failures==0 else 1)
