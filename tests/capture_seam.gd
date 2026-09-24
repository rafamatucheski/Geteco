extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var scene = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	
	# Wait for stream/mountain to be ready
	var stream = scene.get_node("ContinuousWorld")
	stream.ensure_mountain()
	while not stream.ready_for_crossing:
		await process_frame
	
	# Position player/camera at seam
	var car = scene.get_node("PersonalCarManager").car
	car.global_position = Vector2(7250, -4560)
	var cam = scene.get_node("PlayerCarCamera")
	if cam:
		cam.global_position = Vector2(7250, -4560)
		cam.zoom = Vector2(1.0, 1.0)
	
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	
	var img = root.get_texture().get_image()
	img.save_png("d:/geteco/seam_capture.png")
	print("Captured seam to d:/geteco/seam_capture.png")
	quit(0)
