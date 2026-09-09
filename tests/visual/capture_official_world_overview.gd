extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 1080)
	root.content_scale_size = root.size
	create_timer(120).timeout.connect(func(): quit(2))
	var saves = root.get_node("SaveManager")
	saves._save_dir = "D:/geteco/artifacts/world-overview-capture/saves/"
	saves._save_directory_ready = false
	saves.clear_pending_save()
	var state = root.get_node("CampaignState")
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		state.set_campaign_flag(StringName(flag), true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 5: await process_frame
	print("CAPTURE world loaded")
	var world = current_scene
	var stream = world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	print("CAPTURE mountain prepared")
	while not stream.ready_for_crossing: await process_frame
	stream.set_process(false)
	stream.mountain.visible = true
	stream.mountain.process_mode = Node.PROCESS_MODE_INHERIT
	stream.mountain.parallax.hide()
	world.weather.time_of_day = 0.45
	world.weather.is_dynamic_time = false
	for camera in world.find_children("*", "Camera2D", true, false):
		camera.enabled = false
	var camera := Camera2D.new()
	camera.name = "OfficialWorldCaptureCamera"
	world.add_child(camera)
	camera.position = Vector2(6000, -2700)
	camera.zoom = Vector2.ONE * 0.29
	camera.position_smoothing_enabled = false
	camera.make_current()
	root.size = Vector2i(4800, 3660)
	root.content_scale_size = root.size
	for i in 5: await process_frame
	print("CAPTURE drawing overview")
	for layer in root.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	paused = true
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	var path := "D:/geteco/artifacts/geteco-mapa-oficial-completo.png"
	print("OFFICIAL_WORLD_CAPTURE size=", picture.get_size(), " result=", picture.save_png(path))
	quit()
