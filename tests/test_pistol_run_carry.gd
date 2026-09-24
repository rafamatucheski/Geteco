extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.weapon_inventory.pistol = true
	player.equip_weapon("pistol")
	for i in 90: pose_frame(player, false)
	var run_min := Vector3(INF, INF, INF)
	var run_max := Vector3(-INF, -INF, -INF)
	var run_contact_ok := true
	var run_free_hand_ok := true
	var run_elbow_ok := true
	for i in 120:
		pose_frame(player, true)
		if i < 45: continue
		var right: Vector3 = player.model_root.to_local(player.meshy_rig.palm_position("Right"))
		run_min = run_min.min(right)
		run_max = run_max.max(right)
		var grip_world: Vector3 = player.current_gun_mesh.to_global(player.combat_pose.GRIPS.pistol)
		run_contact_ok = run_contact_ok and player.meshy_rig.palm_position("Right").distance_to(grip_world) < 0.006
		var support_world: Vector3 = player.current_gun_mesh.to_global(player.combat_pose.SUPPORT_GRIPS.pistol)
		run_free_hand_ok = run_free_hand_ok and player.meshy_rig.palm_position("Left").distance_to(support_world) > 0.10
		var skeleton: Skeleton3D = player.meshy_rig.skeleton
		var shoulder: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("RightArm")).origin
		var elbow: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm")).origin
		var wrist: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
		var elbow_flare := absf(elbow.x) - maxf(absf(shoulder.x), absf(wrist.x))
		run_elbow_ok = run_elbow_ok and elbow.y < shoulder.y - 0.025 and elbow_flare < 0.06
	check(run_contact_ok, "running pistol grip remains locked inside right palm")
	check(run_free_hand_ok, "running relaxed pistol remains one-handed")
	check(run_elbow_ok, "running pistol elbow bends below the shoulder without flaring sideways")
	check(player.meshy_rig._uses_locomotion_arm_clip(), "running pistol preserves the authored arm chain instead of procedural IK")
	check(run_max.z - run_min.z < 0.06 and run_max.y - run_min.y < 0.08, "running pistol hand remains stable through the gait cycle")
	check(run_min.x > 0.23 and run_max.x < 0.31 and run_min.y > 0.70 and run_max.y < 0.85, "running pistol stays outside torso beside hip: %s..%s" % [run_min, run_max])
	var run_barrel: Vector3 = player.model_root.global_basis.inverse() * -player.weapon_mount_node.global_basis.z
	check(run_barrel.y < -0.60 and run_barrel.z < -0.45, "running pistol muzzle stays safely down-forward: " + str(run_barrel))
	scene.queue_free()
	await process_frame
	print("PISTOL_RUN_CARRY failures=", failures)
	quit(0 if failures == 0 else 1)

func pose_frame(player, running: bool) -> void:
	if running: player.walk_clock += 0.18
	player._update_locomotion(1.0 / 60.0, running, running)
	player.meshy_rig.prepare_pose(1.0 / 60.0, running, running)
	player.combat_pose.update(player, 1.0 / 60.0, false, running, player._gait_arm_swing())
	player.meshy_rig.update_pose(1.0 / 60.0, running, running)
