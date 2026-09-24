extends SceneTree
var player
var failures := 0
var output := "user://tests/shoulder-melee"

func _initialize() -> void: run.call_deferred()

func step() -> void:
	var running := "--running" in OS.get_cmdline_user_args()
	var moving := running or "--walking" in OS.get_cmdline_user_args()
	if moving:
		player.walk_clock += TAU / 40.0
		player.velocity = Vector2(0,-90)
		player._update_locomotion(1.0/60.0, true, running)
	player.meshy_rig.prepare_pose(1.0/60.0, moving, running)
	player.combat_pose.update(player, 1.0/60.0, false, running, player._gait_arm_swing() if moving else 0.0)
	player.meshy_rig.update_pose(1.0/60.0, moving, running)
	for side in ["Right", "Left"]:
		if side == "Left" and player.meshy_rig._left_visible_clip_weight > 0.0: continue
		var arm: Node3D = player.right_lower_arm if side == "Right" else player.left_lower_arm
		var error: float = player.meshy_rig.palm_position(side).distance_to(arm.get_node("Palm").global_position)
		if error > 0.005:
			failures += 1
			push_error("Melee hand loses contact: " + side + " error=" + str(error))

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output)
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://characters/Player.gd").new()
	player.use_meshy_dante = true
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.viewport_3d.size = Vector2i(384,384)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.85
	cam.position = Vector3(0,1.05,-3)
	cam.look_at(Vector3(0,0.80,0))
	var atlas := Image.create(384*6,384*6,false,Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	var row := 0
	for id in ["axe", "bat"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for angle in [0.0, -PI/2, PI]:
			player.model_root.rotation.y = angle
			for col in 6:
				for i in 90: step()
				if col > 0:
					player.combat_pose.on_attack(id)
					for i in ([8,14,18,26,43] if id == "axe" else [6,11,15,22,35])[col-1]: step()
				if DisplayServer.get_name() != "headless":
					await process_frame
					await RenderingServer.frame_post_draw
					atlas.blit_rect(player.viewport_3d.get_texture().get_image(),Rect2i(0,0,384,384),Vector2i(col,row)*384)
			row += 1
	atlas.save_png(output.path_join("shoulder-melee.png"))
	if "--motion" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
		player.model_root.rotation.y = -0.85
		for id in ["axe", "bat"]:
			player.equip_weapon(id)
			for i in 90: step()
			for frame in 75:
				if frame == 12 and "--carry-only" not in OS.get_cmdline_user_args(): player.combat_pose.on_attack(id)
				step()
				step()
				await process_frame
				await RenderingServer.frame_post_draw
				player.viewport_3d.get_texture().get_image().save_png(output.path_join("frames/%s_%03d.png" % [id, frame]))
	# Exercise the same hand constraints with the moving shoulders and legs.
	for id in ["axe", "bat"]:
		player.equip_weapon(id)
		for sprinting in [false, true]:
			for frame in 90:
				player.walk_clock += TAU / 40.0
				player.velocity = Vector2(0,-90)
				player._update_locomotion(1.0/60.0, true, sprinting)
				player.meshy_rig.prepare_pose(1.0/60.0, true, sprinting)
				if frame == 30: player.combat_pose.on_attack(id)
				player.combat_pose.update(player, 1.0/60.0, false, sprinting, player._gait_arm_swing())
				player.meshy_rig.update_pose(1.0/60.0, true, sprinting)
				for side in ["Right", "Left"]:
					if side == "Left" and player.meshy_rig._left_visible_clip_weight > 0.0: continue
					var arm: Node3D = player.right_lower_arm if side == "Right" else player.left_lower_arm
					if player.meshy_rig.palm_position(side).distance_to(arm.get_node("Palm").global_position) > 0.005: failures += 1
	print("SHOULDER_MELEE contact_failures=", failures)
	scene.queue_free()
	await process_frame
	quit(failures)
