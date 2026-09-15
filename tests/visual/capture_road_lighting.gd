extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	create_timer(180).timeout.connect(func(): quit(2))
	var mountain_capture := "--mountain" in OS.get_cmdline_user_args()
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/road-lighting-0911/capture-saves/"
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag),true)
	var scene = load("res://world/harbor/HarborGame.tscn" if mountain_capture else "res://world/harbor/HarborPreview.tscn").instantiate()
	scene.review_mode = false
	root.add_child(scene)
	current_scene = scene
	for i in 20: await process_frame
	while not scene.world_build_ready: await process_frame
	if scene.has_node("RoadLighting"):
		while not scene.get_node("RoadLighting").ready_for_audit: await process_frame
	if mountain_capture:
		while not scene.gameplay_ready: await process_frame
		var stream = scene.get_node("ContinuousWorld")
		await stream.ensure_mountain()
		while not stream.ready_for_crossing: await process_frame
		while not stream.mountain.get_node("RoadLighting").ready_for_audit: await process_frame
		stream.set_process(false)
		stream.mountain.visible = true
		stream.mountain.process_mode = Node.PROCESS_MODE_INHERIT
		stream.mountain.parallax.hide()
	scene.weather.is_dynamic_time = false
	scene.weather.time_of_day = 0.0
	scene.weather.set_weather(0)
	scene.weather._update_lighting()
	for layer in root.find_children("*", "CanvasLayer", true, false): layer.hide()
	for camera in scene.find_children("*", "Camera2D", true, false): camera.enabled = false
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.zoom = Vector2.ONE * 1.05
	camera.make_current()
	var label := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	var shots := [{"id":"foundry", "point":Vector2(3740,400)}, {"id":"northbank", "point":Vector2(5550,1250)}, {"id":"northgate", "point":Vector2(5500,-1100)}, {"id":"connector", "point":Vector2(6650,-4510)}, {"id":"market", "point":Vector2(1670,1250)}, {"id":"port", "point":Vector2(4650,4770)}]
	if mountain_capture:
		shots = [{"id":"mountain-bridge","point":Vector2(8100,-4560)},{"id":"mountain-tunnel","point":Vector2(9660,-4560)},{"id":"mountain-curve","point":Vector2(10800,-5960)}]
		# Open the real tunnel cutaway for its interior lighting review.
		scene.get_node("MountainRegion/MountainTunnel").roof_canvas.modulate.a = .05
	for shot in shots:
		camera.position = shot.point
		camera.make_current()
		camera.reset_physics_interpolation()
		camera.force_update_scroll()
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var path := "D:/geteco/artifacts/road-lighting-0911/%s-%s.png" % [label,shot.id]
		root.get_texture().get_image().save_png(path)
		print("LIGHTING_CAPTURE ",path)
		if scene.has_node("RoadLighting"):
			var visible_pools := 0
			for pool in scene.find_children("*","PointLight2D",true,false):
				if pool.is_visible_in_tree() and pool.enabled: visible_pools += 1
			print("LIGHTING_RENDER ",shot.id," active_canvas_lights=",visible_pools," draw_calls=",RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	quit()
