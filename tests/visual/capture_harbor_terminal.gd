extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 12: await process_frame
	world.campaign_controller.skip_cinematic()
	await create_timer(0.45).timeout
	var camera := Camera2D.new()
	camera.position = Vector2(1700, 1150)
	camera.zoom = Vector2(2.1, 2.1)
	world.add_child(camera)
	camera.make_current()
	await create_timer(0.7).timeout
	await shot("D:/geteco/harbor-terminal-disembark.png")
	await create_timer(4.5).timeout
	for i in 4: world.campaign_controller.advance_dialogue()
	await create_timer(2.0).timeout
	await shot("D:/geteco/harbor-terminal-passengers.png")
	print("TERMINAL_VISUAL %s" % world.get_node("ArrivalStop").get_service_status())
	world.queue_free()
	await process_frame
	quit()
