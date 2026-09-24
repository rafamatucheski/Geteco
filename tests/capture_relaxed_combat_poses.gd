extends "res://tests/test_relaxed_combat_poses.gd"

func run() -> void:
	var output := OS.get_temp_dir().path_join("geteco-relaxed-combat.png")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="): output = arg.trim_prefix("output=")
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.viewport_3d.size = Vector2i(384, 384)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.85
	cam.position = Vector3(0, 1.05, -3)
	cam.look_at(Vector3(0, 0.80, 0))
	var atlas := Image.create(384 * 6, 384 * 3, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	var row := 0
	for id in ["knife", "grenade", "fists"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for col in 6:
			player.model_root.rotation.y = (PI * 0.5) if col >= 3 else 0.0
			for i in 90: step()
			if col % 3 > 0:
				player.combat_pose.on_attack(id)
				for i in (9 if col % 3 == 1 else 16): step()
			await process_frame
			await RenderingServer.frame_post_draw
			atlas.blend_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 384, 384), Vector2i(col * 384, row * 384))
		row += 1
	var error := atlas.save_png(output)
	print("RELAXED_COMBAT_CAPTURE ", output, " error=", error)
	scene.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
