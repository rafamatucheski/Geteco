extends SceneTree

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var output := "D:/geteco/artifacts/weapon-realism-0913/after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var viewport: SubViewport = player.viewport_3d
	viewport.size = Vector2i(320, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := viewport.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.75
	cam.position = Vector3(0, 1.15, 3)
	cam.look_at(Vector3(0, 0.79, 0))
	var overview := Image.create(1280, 1440, false, Image.FORMAT_RGBA8)
	overview.fill(Color("28303a"))
	var weapon_index := 0
	for id in WeaponCatalog.ORDER:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		var atlas := Image.create(1280, 1080, false, Image.FORMAT_RGBA8)
		atlas.fill(Color("28303a"))
		for row in 3:
			player.model_root.rotation.y = [-PI/2, PI*0.80, -0.5][row]
			for col in 4:
				player._cancel_reload()
				player.weapon_ammo[id] = {"clip": 10, "reserve": 100}
				for frame in 60:
					player.walk_clock = frame * 0.12
					player._update_locomotion(1.0/60, col == 2, col == 2)
					player.combat_pose.update(player, 1.0/60, col == 1, col == 2, player._gait_arm_swing())
				if col == 3:
					player.weapon_ammo[id] = {"clip":0, "reserve":100}
					player._reload_active_weapon()
					if player.is_reloading():
						for frame in 30:
							player._process(player._reload_duration * 0.45 / 30)
							player.combat_pose.update(player, 1.0/60, false, false, 0)
					else:
						player.combat_pose.on_attack(id)
						for frame in 14: player.combat_pose.update(player, 1.0/60, true, false, 0)
				await process_frame
				await RenderingServer.frame_post_draw
				atlas.blend_rect(viewport.get_texture().get_image(), Rect2i(0,0,320,360), Vector2i(col*320,row*360))
				if row == 1 and col == 1:
					overview.blend_rect(viewport.get_texture().get_image(), Rect2i(0,0,320,360), Vector2i((weapon_index % 4)*320, (weapon_index / 4)*360))
		atlas.save_png(output.path_join(id + ".png"))
		weapon_index += 1
	overview.save_png(output.path_join("arsenal.png"))
	print("WEAPON_CAPTURE ", output)
	player._cancel_reload()
	world.queue_free()
	await process_frame
	quit()
