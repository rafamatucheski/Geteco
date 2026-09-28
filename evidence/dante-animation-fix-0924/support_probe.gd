extends SceneTree
## Multi-frame skeletal invariant: IK may rotate joints, never resize limbs.
const ACTOR = preload("res://scripts/Actor.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
var worst_scale := 0.0
var worst_length := 0.0
var failures: Array[String] = []
const DATA = preload("res://gameplay/WeaponPoseData.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var actor = ACTOR.new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	var pose = POSE.new()
	for frame in 600:
		var direction := Vector3(sin(frame * 0.03), 0, cos(frame * 0.03))
		actor.visual.rotation.y = frame * 0.03
		actor.combat_facing = actor.visual.rotation.y
		actor.combat_stance = "gun"
		actor._pose_locomotion(direction, 3.5, direction * 3.5 / 60.0, 3.5)
		actor.set_combat_weapon_pose("smg", pose.update("smg", 1.0 / 60.0, true, false, 0, true, false, frame / 60.0))
		actor._apply_combat_weapon_pose()
		for side in ["Right", "Left"]:
			for name in ["Arm", "ForeArm", "Hand"]:
				var bone: int = actor.skeleton.find_bone(side + name)
				var scale_error: float = (actor.skeleton.get_bone_pose_scale(bone) - Vector3.ONE).length()
				var length_error: float = absf(actor.skeleton.get_bone_pose_position(bone).length() - actor.skeleton.get_bone_rest(bone).origin.length())
				worst_scale = maxf(worst_scale, scale_error)
				worst_length = maxf(worst_length, length_error)
		if frame % 60 == 0: print("DANTE_FRAME ", frame, " scale_error=", worst_scale, " length_error=", worst_length)
	print("DANTE_DEFORMATION scale_error=", worst_scale, " length_error=", worst_length)
	if worst_scale >= 0.09 or worst_length >= 0.001:
		quit(1)
		return
	var frames_checked := 0
	for id in ["bat"]:
		var max_joint_error := 0.0
		var max_support_error := 0.0
		var max_palm_radius := 0.0
		for direction_index in 8:
			actor.visual.rotation.y = direction_index * TAU / 8.0
			actor.position = Vector3(127, 3, -91)
			for tick in 240:
				var moving := tick >= 40 and tick < 220
				var sprint := tick >= 160
				var aiming := tick >= 20 and tick < 220
				var reloading := tick >= 90 and tick < 160
				var speed := 6.5 if sprint else (1.0 if tick < 80 else 3.5)
				var direction := Vector3.BACK if tick < 80 else Vector3.RIGHT
				direction = actor.visual.basis * direction if moving else Vector3.ZERO
				actor.combat_facing = actor.visual.rotation.y if aiming else NAN
				actor._pose_locomotion(direction, speed, direction * speed / 60.0, speed if moving else 0.0)
				if id in ["fists", "knuckles", "axe", "bat", "knife"] and tick % 60 < 12:
					var locomotion: Array = actor._capture_pose()
					actor._pose_clip("Attack", 0.4 + float(tick % 12) / 30.0)
					actor._apply_blend(locomotion, actor._capture_pose(), sin(float(tick % 12) / 12.0 * PI))
				if tick % 20 == 0: pose.attack(id)
				var packet: Dictionary = pose.update(id, 1.0 / 60.0, aiming, reloading, (tick - 90) / 70.0, moving, sprint, tick / 60.0)
				actor.set_combat_weapon_pose(id, packet)
				actor._apply_combat_weapon_pose()
				var weapon: Transform3D = actor.combat_weapon_transform(DATA.GRIPS[id])
				if packet.support_locked:
					var error: float = actor.combat_palm_position("Left").distance_to(weapon * (packet.get("support_point", DATA.SUPPORT_GRIPS[id]) as Vector3))
					if error > max_support_error and error > 0.06:
						print("WORST dir=",direction_index," tick=",tick," error=",error," left=",actor.visual.to_local(actor.combat_palm_position("Left"))," desired=",actor.visual.to_local(weapon * (packet.support_point as Vector3))," right=",actor.visual.to_local(actor.combat_palm_position("Right")))
					max_support_error = maxf(max_support_error, error)
				for side in ["Right", "Left"]:
					var palm: Vector3 = actor.to_local(actor.combat_palm_position(side))
					max_palm_radius = maxf(max_palm_radius, Vector2(palm.x, palm.z).length())
					for part in ["Arm", "ForeArm", "Hand"]:
						var bone: int = actor.skeleton.find_bone(side + part)
						var expected_scale := Vector3.ONE * (0.95 if part == "Hand" else 1.0)
						var global_pose: Transform3D = actor.skeleton.get_bone_global_pose(bone)
						if not global_pose.is_finite():
							failures.append("nonfinite " + id)
							quit(1)
							return
						max_joint_error = maxf(max_joint_error, actor.skeleton.get_bone_pose_scale(bone).distance_to(expected_scale))
						max_joint_error = maxf(max_joint_error, actor.skeleton.get_bone_pose_position(bone).distance_to(actor.skeleton.get_bone_rest(bone).origin))
				frames_checked += 1
		var ok := max_joint_error < 0.001 and max_support_error < 0.080 and max_palm_radius < 1.0
		print("DANTE_TRANSITIONS ", id, " joint=", max_joint_error, " support=", max_support_error, " radius=", max_palm_radius, " pass=", ok)
		if not ok: failures.append(id)
	# Switch during recoil/reload/sprint, rather than only at settled boundaries.
	var ids: Array = DATA.PROFILES.keys()
	var switch_error := 0.0
	for tick in 960:
		var id: String = ids[(tick / 7) % ids.size()]
		var direction := Vector3.RIGHT.rotated(Vector3.UP, float(tick % 8) * TAU / 8.0)
		actor.visual.rotation.y = float(tick % 8) * TAU / 8.0
		actor._pose_locomotion(direction, 6.5, direction * 6.5 / 60.0, 6.5)
		pose.attack(id)
		var packet: Dictionary = pose.update(id, 1.0 / 60.0, true, tick % 3 == 0, 0.5, true, true, tick / 60.0)
		actor.set_combat_weapon_pose(id, packet)
		actor._apply_combat_weapon_pose()
		for side in ["Right", "Left"]:
			for part in ["Arm", "ForeArm"]:
				var bone: int = actor.skeleton.find_bone(side + part)
				switch_error = maxf(switch_error, actor.skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE))
	if switch_error >= 0.001: failures.append("switch-during-actions")
	print("DANTE_SWITCH frames=960 arm_scale_error=", switch_error)
	print("DANTE_TRANSITIONS frames=", frames_checked, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
