extends SceneTree

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var scene := load("res://world/harbor/HarborPreview.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	scene._panel.visible = false
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.position = Vector2(735, 1050)
	camera.zoom = Vector2.ONE * 2.5
	camera.make_current()
	camera.reset_physics_interpolation()
	for i in 4: await physics_frame
	camera.force_update_scroll()
	var weather := get_first_node_in_group("day_night_manager")
	weather.is_dynamic_time = false
	weather.weather_state = 0
	weather.time_of_day = 0.4
	weather.is_dark = false
	weather.color = Color.WHITE
	for node in get_nodes_in_group("procedural_building"): node.queue_redraw()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/shopfronts-district.png")
	scene.queue_free()
	await process_frame
	quit()
