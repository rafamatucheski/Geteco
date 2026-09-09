extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1280,720)
	change_scene_to_file("res://world/mountain_pass/MountainPass.tscn")
	for i in 10: await physics_frame
	var vista: Node2D = current_scene.get_node("MountainExpedition/SummitVista")
	var player: Node2D = current_scene.player_instance
	player.global_position = vista.global_position
	await process_frame
	vista._open()
	var ok: bool = player.is_control_disabled and player.is_in_dialogue and paused
	for i in 12: await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/mountain-city-vista.png")
	vista._close()
	ok = ok and not paused and not player.is_control_disabled and not player.is_in_dialogue
	print("VISTA CONTROLS RESTORED: ",ok)
	current_scene.queue_free()
	for i in 4: await process_frame
	quit(0 if ok else 1)
