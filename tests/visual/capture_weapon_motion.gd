extends SceneTree

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var output := "D:/geteco/artifacts/weapon-realism-0913/motion"
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
	var view: SubViewport = player.viewport_3d
	view.size = Vector2i(640, 640)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := view.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.95
	cam.position = Vector3(0, 1.15, 3)
	cam.look_at(Vector3(0, 0.8, 0))
	var counter := 0
	for id in ["pistol", "shotgun", "hunting_rifle", "rpg", "flamethrower", "bat", "axe"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		player.weapon_ammo[id] = {"clip": 10, "reserve": 100}
		for frame in 120:
			var aiming := frame >= 30 and frame < 75
			var running := frame >= 90
			player.walk_clock = frame * 0.20
			player.model_root.rotation.y = lerpf(-PI/2, -PI*1.15, frame / 119.0)
			player._update_locomotion(1.0/30, running, running)
			if frame == 42 or frame == 61: player.combat_pose.on_attack(id)
			if frame == 75:
				player.weapon_ammo[id].clip = 0
				player._reload_active_weapon()
			if player.is_reloading(): player._process(player._reload_duration / 35.0)
			player.combat_pose.update(player, 1.0/30, aiming, running, player._gait_arm_swing())
			await process_frame
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(output.path_join("%04d.png" % counter))
			counter += 1
		player._cancel_reload()
	world.queue_free()
	await process_frame
	print("WEAPON_MOTION frames=", counter)
	quit()
