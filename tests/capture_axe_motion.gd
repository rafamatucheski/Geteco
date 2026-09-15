extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var output := "D:/geteco/artifacts/axe-0913"
	var before := "--before" in OS.get_cmdline_user_args()
	var scene := Node2D.new()
	scene.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(scene)
	current_scene = scene
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	var pose_driver: RefCounted = load(output + "/before/PlayerCombatPose.gd").new() if before else player.combat_pose
	player.weapon_inventory.axe = true
	player.equip_weapon("axe")
	if "--no-trail" in OS.get_cmdline_user_args(): player.current_gun_mesh.get_node("AxeSwingTrail").free()
	if before:
		player.current_gun_mesh.position = -pose_driver.GRIPS.axe
		for child in player.current_gun_mesh.get_children(): child.free()
		load(output + "/before/scripts/player/WeaponPresentation3D.gd").build(player.current_gun_mesh,"axe")
	player.viewport_3d.size = Vector2i(384,384)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera3d: Camera3D = player.viewport_3d.get_camera_3d()
	camera3d.position = Vector3(0,1.9,3.1)
	camera3d.look_at(Vector3(0,0.92,0),Vector3.UP)
	camera3d.fov = 38
	# Warm the transparent material with real rendered frames before snapshots.
	for warmup in 90:
		if warmup == 20: pose_driver.on_attack("axe")
		pose_driver.update(player,1.0/60,true,false,0)
		await process_frame
	var atlas := Image.create(384*5,384*(3 if before else 6),false,Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	for side in (3 if before else 6):
		player.model_root.rotation.y = [2.49, 1.57, 0.0][side % 3]
		for pose in 5:
			for frame in 60: pose_driver.update(player,1.0/60,true,false,0)
			if not before: pose_driver.axe_variant = int(side / 3) - 1
			pose_driver.on_attack("axe")
			var frames: int = [1,10,17,24,44][pose]
			for frame in frames: pose_driver.update(player,1.0/60,true,false,0)
			for settle in 3: await process_frame
			await RenderingServer.frame_post_draw
			atlas.blit_rect(player.viewport_3d.get_texture().get_image(),Rect2i(0,0,384,384),Vector2i(pose,side)*384)
	atlas.save_png(output + ("/before-poses.png" if before else "/poses.png"))
	if not before:
		DirAccess.make_dir_recursive_absolute(output + "/frames")
		player.model_root.rotation.y = 2.49
		pose_driver.axe_variant = -1
		for i in 96:
			if i in [15,54]: pose_driver.on_attack("axe")
			pose_driver.update(player,1.0/30,true,false,0)
			await process_frame
			await RenderingServer.frame_post_draw
			player.viewport_3d.get_texture().get_image().save_png(output + "/frames/%04d.png" % i)
	scene.queue_free()
	await process_frame
	quit()
