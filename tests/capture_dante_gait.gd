extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for x in range(-800, 801, 16):
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(x, -800), Vector2(x, 800)])
		line.width = 0.3
		line.default_color = Color("495963")
		world.add_child(line)
	for y in range(-800, 801, 16):
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(-800, y), Vector2(800, y)])
		line.width = 0.3
		line.default_color = Color("495963")
		world.add_child(line)
	var player = load("res://characters/Player.gd").new()
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.zoom = Vector2.ONE * 6
	player.add_child(cam)
	world.add_child(player)
	cam.set_script(null)
	cam.zoom = Vector2.ONE * 6
	player.speed = 24.0
	player.equip_weapon("fists")
	player.viewport_3d.size = Vector2i(512, 512)
	player.sprite_3d_display.scale = Vector2.ONE * 0.06
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var label := Label.new()
	label.position = Vector2(30, 28)
	label.add_theme_font_size_override("font_size", 24)
	layer.add_child(label)
	var closeup := SubViewport.new()
	closeup.size = Vector2i(360, 480)
	closeup.world_3d = player.viewport_3d.find_world_3d()
	closeup.transparent_bg = true
	closeup.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.add_child(closeup)
	var close_camera := Camera3D.new()
	closeup.add_child(close_camera)
	close_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	close_camera.size = 1.65
	close_camera.position = Vector3(0, 1.15, 3)
	close_camera.look_at(Vector3(0, 0.72, 0))
	close_camera.make_current()
	var panel := TextureRect.new()
	panel.texture = closeup.get_texture()
	panel.position = Vector2(910, 180)
	panel.size = Vector2(360, 480)
	layer.add_child(panel)
	var output := "D:/geteco/artifacts/dante-gait-0913/motion"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
		if arg.begins_with("weapon="):
			var id := arg.trim_prefix("weapon=")
			player.weapon_inventory[id] = true
			player.equip_weapon(id)
	DirAccess.make_dir_recursive_absolute(output)
	for frame in 300:
		for action in ["move_right", "move_left", "move_up", "move_down", "sprint"]: Input.action_release(action)
		label.text = "Idle"
		if frame >= 30 and frame < 100:
			Input.action_press("move_right")
			label.text = "Walk"
		if frame >= 100 and frame < 165:
			Input.action_press("move_right")
			Input.action_press("sprint")
			label.text = "Run"
		if frame >= 165 and frame < 215:
			Input.action_press("move_up")
			label.text = "Walk / turn"
		if frame >= 215 and frame < 260:
			Input.action_press("move_down")
			Input.action_press("sprint")
			label.text = "Run / turn"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/frame_%03d.png" % frame)
	for action in ["move_right", "move_left", "move_up", "move_down", "sprint"]: Input.action_release(action)
	world.queue_free()
	await process_frame
	print("DANTE_GAIT_CAPTURE complete")
	quit()
