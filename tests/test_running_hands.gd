extends SceneTree
## Real Dante rig: moving punch must preserve gait; held grenade stays exposed.
const ACTOR = preload("res://scripts/Actor.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("RUNNING_HANDS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func run() -> void:
	var actor = ACTOR.new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(2.5, 1.9, -3.5)
	if "--front" in OS.get_cmdline_user_args(): camera.position = Vector3(0, 1.65, -4)
	if "--side" in OS.get_cmdline_user_args(): camera.position = Vector3(4, 1.65, 0)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.3
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-40, -35, 0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("637180")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var mount := Node3D.new()
	root.add_child(mount)
	actor.set_combat_weapon_mount(mount, DATA.GRIPS.grenade)
	preload("res://gameplay/ArsenalWeapon3D.gd").build(mount, "grenade")
	var label := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): label = arg.trim_prefix("--capture=")
	var output := ProjectSettings.globalize_path("res://evidence/running-hands-20260928")
	if label != "": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var stationary := "--standing" in OS.get_cmdline_user_args()
	for id in ["fists", "grenade"]:
		if stationary and id == "fists": continue
		var pose = POSE.new()
		var worst_foot_shift := 0.0
		var previous: Array = []
		var worst_angle := 0.0
		var minimum_elbow_back := INF
		for tick in 210:
			actor.combat_facing = NAN
			var speed := 0.0 if stationary else 6.5
			actor._pose_locomotion(Vector3.FORWARD, speed, Vector3.FORWARD * speed / 60.0, speed)
			var feet: Array[Vector3] = []
			for side in ["Left", "Right"]:
				feet.append(actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(side + "Foot")).origin)
			if tick == 60 or tick == 90: pose.attack(id)
			var packet: Dictionary = pose.update(id, 1.0/60.0, false, false, 0, not stationary, not stationary, actor.phase, actor.combat_rig_info())
			actor.set_combat_weapon_pose(id, packet)
			actor._apply_combat_weapon_pose()
			mount.visible = id == "grenade" and packet.visible
			if id == "grenade" and tick > 30:
				var points: Array[Vector3] = []
				for part in ["RightArm", "RightForeArm", "RightHand"]:
					points.append(actor.visual.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(part)).origin)))
				var arm_axis := (points[2] - points[0]).normalized()
				var elbow_bend := points[1] - points[0] - arm_axis * (points[1] - points[0]).dot(arm_axis)
				minimum_elbow_back = minf(minimum_elbow_back, elbow_bend.z)
			for side_index in 2:
				var foot: int = actor.skeleton.find_bone(["LeftFoot", "RightFoot"][side_index])
				worst_foot_shift = maxf(worst_foot_shift, feet[side_index].distance_to(actor.skeleton.get_bone_global_pose(foot).origin))
			var now: Array = actor._capture_pose()
			if tick > 30:
				for bone in now.size():
					worst_angle = maxf(worst_angle, rad_to_deg((previous[bone][1] as Quaternion).angle_to(now[bone][1])))
			previous = now
			if label != "" and (tick in [55, 98, 145] or (id == "grenade" and tick >= 60 and tick <= 105 and tick % 3 == 0) or tick == 67):
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("%s-%s-%d.png" % [label, id, tick]))
		check(worst_foot_shift < 0.005, "%s preserves running feet: %.4fm" % [id, worst_foot_shift])
		check(worst_angle < 35.0, "%s continuous joints: %.2f degrees/frame" % [id, worst_angle])
		if id == "grenade":
			check(minimum_elbow_back > 0.0, "grenade elbow bends backward throughout carry/throw/recovery: %.4fm" % minimum_elbow_back)
			var packet: Dictionary = pose.update(id, 1.0/60.0, false, false, 0, false, false, 0, {"loaded": true})
			check(packet.visible and packet.right_grip, "loaded grenade held visibly at rest")
			packet = pose.update(id, 1.0/60.0, false, false, 0, false, false, 0, {"loaded": false})
			check(not packet.visible and not packet.right_grip, "empty hand hides grenade")
	# Real inventory/state and production presentation, without saves or cheats.
	var world := Node3D.new()
	root.add_child(world)
	var state = preload("res://runtime/GameState.gd").new()
	state.grant_weapon("grenade")
	state.equip_weapon("grenade")
	var gameplay = preload("res://gameplay/Gameplay.gd").new()
	gameplay.configure(world, actor, camera, state)
	world.add_child(gameplay)
	gameplay.set_physics_process(false)
	state.consume_ammo("grenade", 1)
	var reserve: int = state.get_ammo("grenade").reserve
	gameplay._update_weapon_pose(1.0/60.0)
	gameplay._update_visual()
	check(gameplay.gun.visible and state.get_ammo("grenade").magazine == 1, "equipping with reserves fills the empty hand")
	check(state.get_ammo("grenade").reserve == reserve - 1, "ready grenade transfers exactly one from reserve")
	gameplay._rig_pose.attack("grenade")
	state.consume_ammo("grenade", 1)
	gameplay._rig_pose.action_age = 0.35
	gameplay._update_weapon_pose(1.0/60.0)
	gameplay._update_visual()
	check(not gameplay.gun.visible and state.get_ammo("grenade").magazine == 0, "no replacement during throwing follow-through")
	gameplay._rig_pose.action_age = 0.70
	gameplay._update_weapon_pose(1.0/60.0)
	gameplay._update_visual()
	check(gameplay.gun.visible and state.get_ammo("grenade").magazine == 1 and gameplay.reload_timer == 0.0, "next grenade returns after recovery without firearm reload")
	check(state.get_ammo("grenade").reserve == reserve - 2, "repeated preparation conserves total ammo")
	state.consume_ammo("grenade", 1)
	gameplay._pending_contact = {"id": "grenade"}
	gameplay._update_weapon_pose(1.0/60.0)
	check(state.get_ammo("grenade").magazine == 0, "pending throw cannot replenish ammo")
	gameplay._pending_contact = {}
	state.set_location("harbor", "maciota")
	gameplay._update_weapon_pose(1.0/60.0)
	gameplay._update_visual()
	check(not gameplay.gun.visible and not gameplay.attack_allowed() and not state.equip_weapon("grenade"), "garage keeps hands unarmed and blocks grenades")
	check(state.get_ammo("grenade").magazine == 0 and state.get_ammo("grenade").reserve == reserve - 2, "garage preserves grenade inventory")
	state.set_location("harbor")
	state.equip_weapon("grenade")
	gameplay._update_weapon_pose(1.0/60.0)
	gameplay._update_visual()
	check(gameplay.gun.visible, "leaving garage restores grenade availability")
	world.queue_free()
	await process_frame
	print("RUNNING_HANDS failures=", failures)
	quit(0 if failures.is_empty() else 1)
