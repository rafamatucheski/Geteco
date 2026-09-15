extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 900)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 30: await process_frame
	world.campaign_controller.skip_cinematic()
	world.set_process(false)
	world.campaign_controller.process_mode = Node.PROCESS_MODE_DISABLED
	var player = world.get_node("Player")
	world.campaign_controller.set_process(false)
	world.get_node("ArrivalStop").set_physics_process(false)
	player.set_physics_process(false)
	player.show()
	player.global_position = world.get_node("ArrivalStop").global_position + Vector2(9, -92)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = world.get_node("ArrivalStop").global_position + Vector2(70, -95)
	camera.zoom = Vector2.ONE * 1.8
	camera.make_current()
	camera.reset_smoothing()
	var art = world.get_node("ArrivalStop/TerminalArchitecture")
	assert(art.get_node("TerminalOverhead").z_index > player.z_index)
	assert(art.camera_3d.cull_mask & art.TERMINAL_MODEL.OVERHEAD_LAYER == 0)
	assert(art.floodlights.size() == 2)
	world.weather.time_of_day = 0.19
	world.weather.weather_state = 2
	world.weather.set_rain_intensity(0.9)
	world.weather._update_lighting()
	for i in 30: await process_frame
	camera.make_current()
	camera.reset_smoothing()
	camera.force_update_scroll()
	await process_frame
	for light in art.floodlights:
		assert(light.is_lit)
		for pool in light.pools: assert(pool.visible)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("D:/geteco/artifacts/terminal-lights-0911")
	root.get_texture().get_image().save_png("D:/geteco/artifacts/terminal-lights-0911/night-rain.png")
	world.weather.time_of_day = 0.45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0.0)
	world.weather._update_lighting()
	for i in 15: await process_frame
	camera.make_current()
	camera.force_update_scroll()
	for light in art.floodlights: assert(not light.is_lit)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/terminal-lights-0911/day.png")
	print("TERMINAL_LIGHTS_PASS: overhead ordering, two twin masts, night on / day off")
	quit()
