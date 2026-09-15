extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://characters/Player.gd").new()
	# Regressão do rig procedural original; o Dante Meshy (padrão desde 14/09)
	# tem cobertura própria em test_meshy_dante e test_meshy_outfits.
	player.use_meshy_dante = false
	player.name = "Player"
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	var atlas := Image.create(4 * 256, ceili(player.combat_pose.PROFILES.size() / 4.0) * 256, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	var index := 0
	for id in WeaponCatalog.ORDER:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for frame in 90:
			player.combat_pose.update(player, 1.0 / 60.0, true, false, 0.0)
		var mount: Node3D = player.weapon_mount_node
		check(mount.global_transform.is_finite(), "%s finite mount" % id)
		var hand_pos: Vector3 = player.right_lower_arm.to_global(Vector3(0, -0.20, 0))
		check(hand_pos.distance_to(mount.global_position) < 0.001, "%s grip on glove" % id)
		check(hand_pos.distance_to(player.current_gun_mesh.to_global(player.combat_pose.GRIPS[id])) < 0.001, "%s actual handle in palm" % id)
		var local_barrel: Vector3 = player.model_root.global_basis.inverse() * -mount.global_basis.z
		if id in ["axe", "bat"]:
			check(local_barrel.y > 0.5, "%s guard raises striking end above hands" % id)
		else:
			check(local_barrel.dot(Vector3.FORWARD) > 0.99, "%s aimed barrel alignment" % id)
		var support: Vector3 = player.combat_pose.SUPPORT_GRIPS.get(id, Vector3.ZERO)
		if support != Vector3.ZERO:
			var left_hand: Vector3 = player.left_lower_arm.to_global(Vector3(0, -0.20, 0))
			check(left_hand.distance_to(player.current_gun_mesh.to_global(support)) < 0.035, "%s support grip" % id)
		player.combat_pose.on_attack(id)
		var peak: float = player.combat_pose.recoil
		for frame in 90:
			player.combat_pose.update(player, 1.0 / 60.0, true, false, 0.0)
		check(player.combat_pose.recoil <= peak * 0.01 + 0.0001, "%s recoil recovery" % id)
		var aimed_hand: Vector3 = mount.position
		var aimed_basis: Basis = mount.global_basis
		for frame in 60:
			player.combat_pose.update(player, 1.0 / 60.0, false, true, 0.2)
		if id != "fists":
			check(not mount.global_basis.is_equal_approx(aimed_basis), "%s sprint differs from aim" % id)
		check(mount.position.is_equal_approx(aimed_hand), "%s grip stable while sprinting" % id)
		for frame in 120:
			if frame == 30: player.combat_pose.on_attack(id)
			player.model_root.rotation.y = frame * TAU / 120.0
			player._sync_upper_body_anchors(-0.18)
			player.combat_pose.update(player, 1.0 / 60.0, frame > 20, frame < 20, sin(frame * 0.2) * 0.5)
			var palm: Node3D = player.right_lower_arm.get_node("Palm")
			check(palm.global_position.distance_to(player.current_gun_mesh.to_global(player.combat_pose.GRIPS[id])) < 0.001, "%s moving handle contact frame %d" % [id, frame])
			if support != Vector3.ZERO:
				var support_pos: Vector3 = support
				if id == "shotgun": support_pos.z += player.current_gun_mesh.get_node("Pump").position.z + 0.16
				var left_palm: Node3D = player.left_lower_arm.get_node("Palm")
				check(left_palm.global_position.distance_to(player.current_gun_mesh.to_global(support_pos)) < 0.035, "%s moving support contact frame %d" % [id, frame])
		# Exercise the actual attack entry point, not just the pose callback.
		player.weapon_ammo[id] = {"clip": 5, "reserve": 10}
		player._shoot_towards(player.global_position + Vector2(250, 0))
		check(player.combat_pose.action_age == 0.0, "%s attack drives animation" % id)
		for frame in 90:
			player.combat_pose.update(player, 1.0 / 60.0, true, false, 0.0)
		if DisplayServer.get_name() != "headless":
			player.viewport_3d.size = Vector2i(256, 256)
			player.model_root.rotation.y = -0.65
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			player.muzzle_flash_3d.hide()
			player.muzzle_light_3d.hide()
			await process_frame
			await RenderingServer.frame_post_draw
			var shot: Image = player.viewport_3d.get_texture().get_image()
			atlas.blit_rect(shot, Rect2i(0, 0, 256, 256), Vector2i(index % 4, index / 4) * 256)
		index += 1
	if DisplayServer.get_name() != "headless":
		atlas.save_png("D:/geteco/combat_pose_review.png")
	print("COMBAT_POSE_RESULT weapons=%d failures=%d" % [index, failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
