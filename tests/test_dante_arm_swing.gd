extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.active_weapon_id = "fists"
	player._update_equipped_weapon_3d_mesh()
	check(is_instance_valid(player.meshy_rig), "Visible Dante rig loads")
	if not is_instance_valid(player.meshy_rig):
		quit(1)
		return

	var max_elbow_flare := 0.0
	var min_elbow_angle := INF
	var max_elbow_angle := 0.0
	var min_hand_z := INF
	var max_hand_z := -INF
	var min_hand_from_shoulder_z := INF
	var max_hand_from_shoulder_z := -INF
	for frame in 180:
		player.walk_clock = frame * TAU / 120.0
		player._update_locomotion(1.0 / 60.0, true, true)
		player.meshy_rig.prepare_pose(1.0 / 60.0, true, true)
		player.combat_pose.update(player, 1.0 / 60.0, false, true, player._gait_arm_swing())
		player.meshy_rig.update_pose(1.0 / 60.0, true, true)
		if frame < 60:
			continue
		for side in ["Right", "Left"]:
			var skeleton: Skeleton3D = player.meshy_rig.skeleton
			var shoulder := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Arm")).origin
			var elbow := skeleton.get_bone_global_pose(skeleton.find_bone(side + "ForeArm")).origin
			var wrist := skeleton.get_bone_global_pose(skeleton.find_bone(side + "Hand")).origin
			max_elbow_flare = maxf(max_elbow_flare, absf(elbow.x - shoulder.x))
			var elbow_angle := rad_to_deg((shoulder - elbow).angle_to(wrist - elbow))
			min_elbow_angle = minf(min_elbow_angle, elbow_angle)
			max_elbow_angle = maxf(max_elbow_angle, elbow_angle)
			min_hand_z = minf(min_hand_z, wrist.z)
			max_hand_z = maxf(max_hand_z, wrist.z)
			min_hand_from_shoulder_z = minf(min_hand_from_shoulder_z, wrist.z - shoulder.z)
			max_hand_from_shoulder_z = maxf(max_hand_from_shoulder_z, wrist.z - shoulder.z)
			check(shoulder.is_finite() and elbow.is_finite() and wrist.is_finite(), "Running arm bones remain finite")

	check(max_elbow_flare < 0.14, "Authored sprint elbows stay close to the torso")
	check(min_elbow_angle > 50.0 and max_elbow_angle < 125.0, "Sprint elbows stay inside the authored running range")
	check(max_elbow_angle - min_elbow_angle > 20.0, "Sprint elbows open behind and close in front")
	check(max_hand_z - min_hand_z > 0.35, "Sprint hands complete the authored fore-aft swing")
	check(min_hand_from_shoulder_z < -0.02 and max_hand_from_shoulder_z > 0.08, "Sprint hands pass both behind and ahead of the shoulders")

	# Exercise the exact run -> stop -> run path. The imported skeleton's rest
	# pose is a T pose, so locomotion must never fade the visible arms toward it.
	var skeleton: Skeleton3D = player.meshy_rig.skeleton
	var left_hand := skeleton.find_bone("LeftHand")
	var right_hand := skeleton.find_bone("RightHand")
	check(skeleton.get_bone_pose_scale(left_hand).is_equal_approx(Vector3.ONE * 0.95), "Left hand keeps the requested five-percent reduction")
	check(skeleton.get_bone_pose_scale(right_hand).is_equal_approx(Vector3.ONE * 0.95), "Right hand keeps the requested five-percent reduction")
	var rest_hand_span := absf(skeleton.get_bone_global_rest(left_hand).origin.x - skeleton.get_bone_global_rest(right_hand).origin.x)
	var max_transition_hand_span := 0.0
	for frame in 120:
		var moving := frame < 30 or frame >= 75
		if moving:
			player.walk_clock += TAU / 120.0
		player._update_locomotion(1.0 / 60.0, moving, true)
		player.meshy_rig.prepare_pose(1.0 / 60.0, moving, true)
		player.combat_pose.update(player, 1.0 / 60.0, false, moving, player._gait_arm_swing())
		player.meshy_rig.update_pose(1.0 / 60.0, moving, true)
		var left_wrist := skeleton.get_bone_global_pose(left_hand).origin
		var right_wrist := skeleton.get_bone_global_pose(right_hand).origin
		max_transition_hand_span = maxf(max_transition_hand_span, absf(left_wrist.x - right_wrist.x))
		check(left_wrist.is_finite() and right_wrist.is_finite(), "Transition arm bones remain finite")
	check(max_transition_hand_span < rest_hand_span * 0.72, "Run/stop transition never exposes the skeleton T pose")
	print("DANTE_ARM_SWING flare=", max_elbow_flare, " angle_deg=", min_elbow_angle, "..", max_elbow_angle, " travel=", max_hand_z - min_hand_z, " shoulder_cross=", min_hand_from_shoulder_z, "..", max_hand_from_shoulder_z, " transition_span=", max_transition_hand_span, " rest_span=", rest_hand_span, " failures=", failures.size())
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
