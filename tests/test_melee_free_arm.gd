extends SceneTree
var failures := 0
var player

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func pose(moving: bool, running: bool) -> void:
	if moving: player.walk_clock += TAU / 60.0
	player.velocity = Vector2(0,-90) if moving else Vector2.ZERO
	player._update_locomotion(1.0/60, moving, running)
	player.meshy_rig.prepare_pose(1.0/60, moving, running)
	player.combat_pose.update(player, 1.0/60, false, running, player._gait_arm_swing())
	player.meshy_rig.update_pose(1.0/60, moving, running)

func bone(name: String) -> Vector3:
	var skeleton: Skeleton3D = player.meshy_rig.skeleton
	return player.model_root.to_local(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin))

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	player = load("res://characters/Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	# Compare moving free arms against the production unarmed locomotion,
	# including bone roll: endpoint distance alone missed the twisted sleeve.
	var reference := {}
	for state in ["walk", "run"]:
		player.walk_clock = 0.0
		player.equip_weapon("fists")
		var samples: Array = []
		for frame in 180:
			pose(true, state == "run")
			var rotations: Array = []
			var skel: Skeleton3D = player.meshy_rig.skeleton
			for name in ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]:
				rotations.append(skel.get_bone_pose_rotation(skel.find_bone(name)))
			samples.append(rotations)
		reference[state] = samples
	for id in ["axe", "bat"]:
		player.weapon_inventory[id] = true
		player.equip_weapon(id)
		for state in ["idle", "walk", "run", "stop"]:
			player.walk_clock = 0.0
			var moving: bool = state in ["walk", "run"]
			var running: bool = state == "run"
			var flare := 0.0
			var low_angle := 180.0
			var high_angle := 0.0
			var low_z := INF
			var high_z := -INF
			var roll_error := 0.0
			var carry_start := Quaternion.IDENTITY
			var carry_arc := 0.0
			var head_back := INF
			for frame in 180:
				pose(moving, running)
				if frame < 60: continue
				var weapon: Node3D = player.current_gun_mesh
				var carry_rotation: Quaternion = (player.model_root.global_basis.inverse() * weapon.global_basis).get_rotation_quaternion()
				if frame == 60: carry_start = carry_rotation
				carry_arc = maxf(carry_arc, carry_start.angle_to(carry_rotation))
				head_back = minf(head_back, player.model_root.to_local(weapon.to_global(Vector3(0,0,-0.44))).z)
				if moving:
					var skel: Skeleton3D = player.meshy_rig.skeleton
					var names := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand"]
					for i in names.size():
						var actual := skel.get_bone_pose_rotation(skel.find_bone(names[i]))
						roll_error = maxf(roll_error, actual.angle_to(reference[state][frame][i]))
				var shoulder := bone("LeftArm")
				var elbow := bone("LeftForeArm")
				var wrist := bone("LeftHand")
				flare = maxf(flare, absf(elbow.x - shoulder.x))
				var angle := rad_to_deg((shoulder - elbow).angle_to(wrist - elbow))
				low_angle = minf(low_angle, angle)
				high_angle = maxf(high_angle, angle)
				low_z = minf(low_z, wrist.z)
				high_z = maxf(high_z, wrist.z)
			print(id, " ", state, " flare=", flare, " angle=", low_angle, "..", high_angle, " travel=", high_z-low_z)
			check(head_back > 0.08, id + " " + state + " weapon remains behind shoulder")
			check(carry_arc > 0.025 and carry_arc < 0.25 if moving else carry_arc < 0.001, id + " " + state + " subtle carry motion follows movement: " + str(carry_arc))
			if moving:
				check(roll_error < 0.001, id + " " + state + " all free-arm joint rotations match unarmed locomotion: " + str(roll_error))
			else:
				check(flare < 0.065, id + " " + state + " elbow stays beside torso")
			check(low_angle > 50.0 and high_angle < 179.5, id + " " + state + " elbow does not fold or lock")
			check(not player.meshy_rig._is_gripping("Left"), id + " " + state + " free hand stays relaxed")
			if running:
				check(high_z - low_z > 0.15, id + " free arm swings through the stride")
				check(high_angle - low_angle > 15.0, id + " elbow opens and closes during run")
		player.combat_pose.on_attack(id)
		for frame in 60: pose(true, true)
		check(not player.combat_pose.melee_support_active, id + " attack returns to free running arm")
	scene.queue_free()
	await process_frame
	print("MELEE_FREE_ARM failures=", failures)
	quit(0 if failures == 0 else 1)
