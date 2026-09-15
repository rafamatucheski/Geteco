extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.active_weapon_id = "fists"
	player._update_equipped_weapon_3d_mesh()
	for sprinting in [false, true]:
		var folded_knee := 0.0
		var flight_frames := 0
		for frame in 240:
			player.walk_clock = frame * TAU / 120.0
			player._update_locomotion(1.0 / 60.0, true, sprinting)
			var swing: float = player._gait_arm_swing()
			player.combat_pose.update(player, 1.0 / 60.0, false, sprinting, swing)
			if frame > 60 and absf(cos(player.walk_clock)) > 0.4:
				var left_hand: Vector3 = player.left_lower_arm.to_global(Vector3(0, -0.20, 0))
				var right_hand: Vector3 = player.right_lower_arm.to_global(Vector3(0, -0.20, 0))
				var left_boot: Node3D = player.left_lower_leg.get_node("Foot")
				var right_boot: Node3D = player.right_lower_leg.get_node("Foot")
				check((left_hand.z - right_hand.z) * (left_boot.global_position.z - right_boot.global_position.z) < 0.0, "Arms oppose the same-side legs in both gaits")
			for side in 2:
				var upper: Node3D = player.left_upper_leg if side == 0 else player.right_upper_leg
				var lower: Node3D = player.left_lower_leg if side == 0 else player.right_lower_leg
				var foot: Node3D = lower.get_node("Foot")
				check(lower.rotation.x <= 0.0, "Knees never bend forward")
				check(foot.global_basis.y.dot(Vector3.UP) > 0.969, "Soles stay level through the stride")
				var sole_y: float = foot.to_global(Vector3(0, -0.043, 0)).y
				check(sole_y >= -0.002, "Boots never penetrate the floor")
				if fposmod(player.walk_clock + side * PI, TAU) < TAU * lerpf(0.5, 0.34, player._sprint_weight):
					check(sole_y < 0.008, "Supporting foot stays on the floor")
				check(lower.position.is_equal_approx(Vector3(0, -0.34, 0)), "Knee joint never separates from thigh")
			if frame >= 120:
				folded_knee = maxf(folded_knee, -player.left_lower_leg.rotation.x)
				var a: Node3D = player.left_lower_leg.get_node("Foot")
				var b: Node3D = player.right_lower_leg.get_node("Foot")
				if minf(a.global_position.y, b.global_position.y) > 0.055: flight_frames += 1
			check(player.head_node.position.distance_to(player.torso_node.transform * Vector3(0, 0.36, 0)) < 0.001, "Head follows the neck through torso motion")
			check(player.torso_node.basis.y.z <= 0.0 and player.torso_node.basis.y.dot(Vector3.UP) > 0.96, "Torso leans slightly forward instead of backward")
		if sprinting:
			check(folded_knee > PI * 0.5, "Sprint folds the recovering knee past a right angle")
			check(flight_frames >= 18, "Sprint has sustained flight distinct from walking support")
			print("RUN_SIGNATURE knee_degrees=", rad_to_deg(folded_knee), " flight_frames=", flight_frames, "/120")
	for frame in 90:
		player._update_locomotion(1.0 / 60.0, false, false)
		player.combat_pose.update(player, 1.0 / 60.0, false, false, 0.0)
	check(is_zero_approx(player._move_weight) and is_zero_approx(player._sprint_weight), "Stop settles both motion blends")
	for upper in [player.left_upper_arm, player.right_upper_arm]:
		var elbow: Vector3 = upper.to_global(Vector3(0, -0.22, 0))
		check(absf(elbow.x) < 0.25, "Idle elbows remain close to the ribcage")
	var settled: Transform3D = player.left_upper_leg.transform
	player._update_locomotion(0.5, false, false)
	check(settled.is_equal_approx(player.left_upper_leg.transform), "Idle feet remain stable")
	var resting_hand: Vector3 = player.right_lower_arm.to_global(Vector3(0, -0.20, 0))
	for frame in 60:
		player._update_locomotion(1.0 / 60.0, false, true)
		player.combat_pose.update(player, 1.0 / 60.0, false, true, 0.0)
	check(player.right_lower_arm.to_global(Vector3(0, -0.20, 0)).distance_to(resting_hand) < 0.001, "Holding sprint at rest keeps arms relaxed")
	# Equal phase intervals must move the supporting sole equal distances.
	# A cosine pendulum slows at both ends and visibly slides during support.
	var contacts: Array[float] = []
	for phase in [0.4, 0.8, 1.2, 1.6]:
		player._pose_stride_leg(player.left_upper_leg, player.left_lower_leg, phase, 0.19, 0.045, -0.033)
		var contact: Node3D = player.left_lower_leg.get_node("Foot")
		contacts.append(contact.global_position.z)
	check(absf((contacts[1] - contacts[0]) - (contacts[3] - contacts[2])) < 0.001, "Supporting foot travels uniformly instead of swinging like a pendulum")
	for outfit in ["dante_suit", "dante_classic"]:
		player.apply_outfit(outfit)
		player._update_locomotion(1.0 / 60.0, false, false)
		check(player.left_lower_leg.has_node("Foot") and player.right_lower_leg.has_node("Foot"), "Outfit rebuild preserves animated ankles")
		check(player.head_node.has_node("Face") and player.head_node.has_node("ShortBeard"), "Outfits retain Dante's face and beard")
	check(player.mat_black_jacket.albedo_texture != null, "Canonical flannel restored")
	var jacket_before: Color = player.mat_black_jacket.albedo_color
	player.take_damage(5)
	await create_timer(0.4).timeout
	check(player.mat_black_jacket.albedo_color.is_equal_approx(jacket_before), "Damage restores flannel without permanently darkening it")
	var max_slide := 0.0
	for action in ["move_right", "move_up"]:
		for running in [false, true]:
			player.set_physics_process(true)
			Input.action_press(action)
			if running: Input.action_press("sprint")
			var last_contact := Vector2.ZERO
			var last_support := false
			for frame in 120:
				await physics_frame
				if frame == 60:
					check(is_equal_approx(player.velocity.length(), 72.0 if running else 24.0), "Native sprint is 72 pixels per second while walking speed is preserved")
				var cam: Camera3D = player.viewport_3d.get_camera_3d()
				var foot: Node3D = player.left_lower_leg.get_node("Foot")
				var contact: Vector2 = player.global_position + cam.unproject_position(foot.global_position) * player.sprite_3d_display.scale
				var support: bool = frame > 35 and player.walk_clock > 0.3 and player.walk_clock < TAU * lerpf(0.5, 0.34, player._sprint_weight) - 0.3
				if support and last_support:
					max_slide = maxf(max_slide, contact.distance_to(last_contact))
				last_contact = contact
				last_support = support
			Input.action_release(action)
			Input.action_release("sprint")
			player.set_physics_process(false)
	check(max_slide < 0.15, "Supporting boot stays planted in world space at walking and running speed")
	print("DANTE_GROUND_CONTACT max_slide_px_per_tick=", max_slide)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	# Native input must stop the gait at a collision as well as when released.
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 5.0
	collision.shape = shape
	player.add_child(collision)
	var wall := StaticBody2D.new()
	var wall_collision := CollisionShape2D.new()
	var wall_shape := RectangleShape2D.new()
	wall_shape.size = Vector2(10, 100)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	wall.position = Vector2(30, 0)
	scene.add_child(wall)
	player.set_physics_process(true)
	Input.action_press("move_right")
	for frame in 90: await physics_frame
	check(player.global_position.x > 10.0 and player.global_position.x < 25.0, "Native movement reaches the wall before stopping")
	var blocked_clock: float = player.walk_clock
	for frame in 30: await physics_frame
	Input.action_release("move_right")
	check(absf(player.walk_clock - blocked_clock) < 0.01, "Blocked movement stops the walk cycle")
	check(player._move_weight < 0.01, "Blocked movement settles to idle")
	for frame in 20: await physics_frame
	var idle_yaw: float = player.model_root.rotation.y
	Input.warp_mouse(Vector2(600, 400))
	for frame in 20: await physics_frame
	check(absf(angle_difference(idle_yaw, player.model_root.rotation.y)) < 0.001, "Idle body does not spin to follow the cursor")
	scene.queue_free()
	await process_frame
	print("DANTE_NATURAL_GAIT failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
