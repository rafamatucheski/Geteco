extends "res://tests/test_meshy_dante.gd"

func run() -> void:
	OUT = "D:/geteco/artifacts/meshy-knuckles-0914"
	DirAccess.make_dir_recursive_absolute(OUT+"/motion")
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var player = load("res://Player.gd").new()
	player.use_meshy_dante = true
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.weapon_inventory["knuckles"] = true
	player.equip_weapon("knuckles")
	player.viewport_3d.size = Vector2i(512,512)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6
	cam.position = Vector3(0,1.05,-3)
	cam.look_at(Vector3(0,0.72,0))
	player.model_root.rotation.y = -0.45
	for i in 90: step(player,false,false)
	if "--hands-only" in OS.get_cmdline_user_args():
		await capture_hands(player,"knuckles")
		world.queue_free()
		await process_frame
		quit()
		return
	check(player.meshy_rig._skin_mesh.get_blend_shape_count() == 4,"Dedicated closed-fist morphs loaded")
	var left: Node3D = player.meshy_rig.left_knuckles
	check(is_instance_valid(left) and left.visible,"Left brass knuckles equipped")
	var left_identity := left.get_instance_id()
	var seen := {}
	var start_left := Vector3.ZERO
	var start_right := Vector3.ZERO
	var peaks := Image.create(2048,512,false,Image.FORMAT_RGBA8)
	var title := Label.new()
	title.position = Vector2(12,12)
	title.add_theme_font_size_override("font_size",20)
	player.viewport_3d.add_child(title)
	for frame in 360:
		if frame >= 30 and frame % 30 == 0:
			start_left = player.left_lower_arm.get_node("Palm").global_position
			start_right = player.right_lower_arm.get_node("Palm").global_position
			player.combat_pose.on_attack("knuckles")
		var moving := frame >= 240
		var running := frame >= 300
		step(player,moving,running)
		var variant: int = player.combat_pose.knuckle_variant
		title.text = ["Jab esquerdo","Direto direito","Gancho esquerdo","Golpe ascendente"][maxi(variant,0)] if frame >= 30 else "Soqueiras nas duas mãos"
		for side in ["Left","Right"]:
			var palm: Node3D = (player.left_lower_arm if side == "Left" else player.right_lower_arm).get_node("Palm")
			var piece: Node3D = left if side == "Left" else player.current_gun_mesh
			check(piece.global_position.distance_to(palm.global_position) < 0.001,side+" knuckles stay on the palm")
			check(piece.global_basis.z.normalized().dot(palm.global_basis.z.normalized()) > 0.999,side+" striking face stays forward")
			check(player.meshy_rig.palm_position(side).distance_to(palm.global_position) < 0.005,side+" skinned hand reaches target")
		check(player.meshy_rig._skin_mesh.get_blend_shape_value(2) == 1 and player.meshy_rig._skin_mesh.get_blend_shape_value(3) == 1,"Both fists remain closed")
		check(player.meshy_rig._skin_mesh.get_blend_shape_value(0) == 0 and player.meshy_rig._skin_mesh.get_blend_shape_value(1) == 0,"Fist morph does not add a second firearm curl")
		await process_frame
		await RenderingServer.frame_post_draw
		if frame >= 30 and frame % 30 == 4:
			var left_travel: float = player.left_lower_arm.get_node("Palm").global_position.distance_to(start_left)
			var right_travel: float = player.right_lower_arm.get_node("Palm").global_position.distance_to(start_right)
			check((left_travel if variant%2 == 0 else right_travel) > 0.07,"Striking hand extends in variant "+str(variant))
			check((right_travel if variant%2 == 0 else left_travel) < 0.045,"Other hand keeps its guard in variant "+str(variant))
			if not seen.has(variant):
				peaks.blit_rect(player.viewport_3d.get_texture().get_image(),Rect2i(0,0,512,512),Vector2i(variant*512,0))
			seen[variant] = true
		dump_clearance(player,frame)
		player.viewport_3d.get_texture().get_image().save_png(OUT+"/motion/%04d.png"%frame)
	check(seen.size() == 4,"All four alternating punches exercised")
	peaks.save_png(OUT+"/combo.png")
	player.weapon_inventory["pistol"] = true
	player.equip_weapon("pistol")
	check(not left.visible,"Offhand knuckles disappear immediately on weapon switch")
	player.equip_weapon("knuckles")
	step(player,false,false)
	check(player.meshy_rig.left_knuckles.get_instance_id() == left_identity,"Re-equipping reuses exactly one offhand model")
	check(player.meshy_rig.find_children("MeshyLeftKnuckles","",true,false).size() == 1,"No duplicate left knuckles")
	print("MESHY_KNUCKLES_RESULT variants=",seen.size()," frames=360 failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func step(player: Node2D, moving: bool, running: bool) -> void:
	player.velocity = Vector2(0,-90 if running else -27.6) if moving else Vector2.ZERO
	if moving: player.walk_clock = fposmod(player.walk_clock+TAU/(19.0 if running else 29.0),TAU)
	player._update_locomotion(1.0/30,moving,running)
	player.meshy_rig.prepare_pose(1.0/30,moving,running)
	player.combat_pose.update(player,1.0/30,true,running,player._gait_arm_swing())
	player.meshy_rig.update_pose(1.0/30,moving,running)
