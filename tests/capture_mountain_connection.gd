extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete",true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 20: await process_frame
	var cam := Camera2D.new()
	cam.position = Vector2(6710,-4100)
	cam.zoom = Vector2.ONE*0.40
	current_scene.add_child(cam)
	cam.make_current()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/harbor-mountain-connection.png")
	change_scene_to_file("res://district/mountain_pass/MountainPass.tscn")
	for i in 12: await process_frame
	var player: Node2D = current_scene.player_instance
	player.set_physics_process(false)
	for shot in [["forest-settlement",Vector2(8000,875)],["winter-patrol",Vector2(6610,-1230)],["bear-forest",Vector2(8220,-1150)]]:
		player.global_position = shot[1]+Vector2(0,90)
		current_scene.main_camera.reset_smoothing()
		for i in 25: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/"+shot[0]+".png")
	quit()
