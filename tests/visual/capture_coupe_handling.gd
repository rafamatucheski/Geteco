extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1000,700)
	root.content_scale_size = root.size
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 8: await physics_frame
	var car = scene.get_node("PlayerCar")
	car.global_position = Vector2(1700,425)
	car.rotation = PI
	scene._drive()
	var camera := car.get_node("Camera") as Camera2D
	camera.set_process(false)
	camera.zoom = Vector2.ONE * 3
	camera.reset_smoothing()
	if scene.get_node_or_null("ReviewUI") != null: scene.get_node("ReviewUI").hide()
	for i in 80: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/coupe-handling-street.png")
	# Record a short native-input turn as successive rendered frames, without
	# teleporting along a prescribed visual path.
	Input.action_press("ui_up")
	Input.action_press("ui_right")
	for i in 30: await physics_frame
	Input.action_release("ui_up")
	Input.action_release("ui_right")
	print("CAPTURE_TURN health=%d exploding=%s" % [car.health, car.is_exploding])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/coupe-handling-turn.png")
	scene.queue_free()
	await process_frame
	quit()
