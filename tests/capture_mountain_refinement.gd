extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var scene = load("res://district/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var actor = scene.player_instance
	actor.set_physics_process(false)
	for shot in [["tunnel", Vector2(5350,400)], ["shop", Vector2(5980,620)], ["summit", Vector2(6600,-2800)], ["cabin", Vector2(22500,20000)]]:
		actor.global_position = shot[1]
		actor.set_meta("mountain_interior", shot[0] == "cabin")
		scene.main_camera.reset_smoothing()
		for i in 35:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-" + shot[0] + "-refined.png")
	quit()
