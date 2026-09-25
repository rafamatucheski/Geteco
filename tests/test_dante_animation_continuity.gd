extends SceneTree
const ACTOR = preload("res://scripts/Actor.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")
var failures: Array[String] = []
var actor
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("CONTINUITY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(n: int) -> void:
	for tick in n: await physics_frame
func run() -> void:
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	root.add_child(actor)
	actor.set_physics_process(false)
	for id in DATA.PROFILES:
		var pose = POSE.new()
		var previous: Array = []
		var max_angle := 0.0
		var worst := ""
		for tick in 240:
			if tick == 45: pose.attack(id)
			actor._pose_locomotion(Vector3.ZERO,3.5,Vector3.ZERO,0.0)
			var reload_action: bool = tick >= 120 and tick < 210 and id in POSE.FIREARMS
			var packet: Dictionary = pose.update(id,1.0/60.0,tick < 220,reload_action,float(tick-120)/90.0,false,false,actor.phase)
			actor.set_combat_weapon_pose(id,packet)
			actor._apply_combat_weapon_pose()
			var now: Array = actor._capture_pose()
			if tick > 30:
				for bone in now.size():
					var angle := rad_to_deg((previous[bone][1] as Quaternion).angle_to(now[bone][1]))
					if angle > max_angle:
						max_angle = angle
						worst = "%s tick=%d" % [actor.skeleton.get_bone_name(bone),tick]
			previous = now
		check(max_angle < 35.0,"%s max_rotation=%.3f %s" % [id,max_angle,worst])
	actor.clear_combat_weapon_pose()
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40,0.2,40)
	collision.shape = shape
	collision.position.y = -0.1
	floor.add_child(collision)
	root.add_child(floor)
	actor.set_physics_process(true)
	actor.speed = 6.5
	actor.combat_facing = 0.0
	actor.combat_stance = "gun"
	actor.automatic_direction = Vector3.BACK
	await frames(45)
	check(actor.animation.current_animation == "Walk_Backward_with_Gun" and actor._run_weight == 0.0,"reversing while aiming never uses forward running")
	check(actor.velocity.length() < 1.9 and actor.velocity.z > 1.3,"backpedal displacement matches its stride")
	for direction in [Vector3.LEFT,Vector3.RIGHT]:
		actor.automatic_direction = direction
		await frames(45)
		check(actor.animation.current_animation == "Walk_Left_with_Gun" and actor._run_weight == 0.0,"directional lateral step " + str(direction))
	actor.combat_facing = NAN
	actor.automatic_direction = Vector3.FORWARD * 0.15
	await frames(45)
	check(actor._run_weight == 0.0,"partial stick sprint does not run in slow motion")
	actor.automatic_direction = Vector3.ZERO
	await frames(20)
	var origin: Vector3 = actor.global_position
	actor.combat_facing = actor.visual.rotation.y + PI / 2
	await frames(8)
	check(actor._turn_time > 0 and actor._turn_time < 1,"stationary quarter turn has a stepping phase")
	await frames(45)
	check(actor.global_position.distance_to(origin) < 0.01,"turning does not translate the collision body")
	check(absf(wrapf(actor._feet_yaw-actor.visual.rotation.y,-PI,PI)) < 0.21,"feet finish facing the new direction")
	var alive: Array = actor._capture_pose()
	actor.on_player_death()
	await create_timer(1.4).timeout
	var dead_pose: Array = actor._capture_pose()
	var changed := 0
	for bone in alive.size():
		if (alive[bone][1] as Quaternion).angle_to(dead_pose[bone][1]) > 0.2: changed += 1
	check(changed >= 5,"death articulates the skeleton")
	actor.respawn_player()
	check(not actor.dead and actor.visual.rotation.x == 0.0,"respawn cancels the death presentation")
	print("DANTE_ANIMATION_CONTINUITY failures=",failures)
	quit(0 if failures.is_empty() else 1)
