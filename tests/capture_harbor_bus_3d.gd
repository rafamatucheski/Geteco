extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 12:
		await process_frame
	world.campaign_controller.skip_cinematic()
	while world.campaign_controller.phase != "phone":
		await process_frame
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = world.get_node("ArrivalStop").bus.global_position + Vector2(0, -45)
	camera.zoom = Vector2.ONE * 3.0
	camera.make_current()
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/harbor-bus-terminal-3d.png")
	world.queue_free()
	await process_frame
	quit()

