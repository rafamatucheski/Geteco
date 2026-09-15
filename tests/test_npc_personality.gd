extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok and not message in failures:
		failures.append(message)
		push_error(message)
func run() -> void:
	var stage=Node2D.new()
	root.add_child(stage)
	current_scene=stage
	var signatures: Array[Vector3]=[]
	for variant in 4:
		var actor=AnimatedPedestrian3D.new()
		actor.appearance_seed=variant
		actor.archetype_override=1
		actor.body_type_override=variant
		stage.add_child(actor)
		actor.ensure_presentation()
		actor.set_physics_process(false)
		var speed=actor.base_walk_speed
		var collision=actor.get_node("CollisionShape2D").shape
		var gait=load("res://characters/pedestrians/CitizenGait.gd").new()
		gait.configure(actor,variant)
		actor.gait=gait
		check(actor.head_node.has_node("CitizenFace"),"City faces are installed")
		for run_mode in [false,true]:
			for frame in 240:
				gait.advance(1.0/60.0,2.4 if run_mode else 1.0,run_mode)
				gait.apply_pose()
				for side in 2:
					var lower=actor.left_lower_leg if side==0 else actor.right_lower_leg
					check(lower.rotation.x<=0,"Knees bend backward")
					var foot=gait.feet[side]
					var sole=foot.to_global(Vector3(0,-.0325,0)).y
					check(sole>=-.002,"Feet do not penetrate floor")
					# Running has toe-off and flight; only its stance interval is planted.
					var cycle=fposmod(gait.phase+side*PI,TAU)/TAU
					if cycle<=lerpf(.5,.35,gait.run_weight): check(absf(sole)<.003,"Support foot stays planted")
					check(absf(foot.global_basis.z.normalized().y)<.001,"Soles remain level")
				check(actor.head_node.position.distance_to(actor.torso_node.transform*Vector3(0,.4,0))<.001,"Head follows neck")
			gait.phase=.7
			gait.apply_pose()
			signatures.append(Vector3(actor.left_upper_arm.rotation.x,actor.left_lower_leg.rotation.x,actor.torso_node.rotation.z))
		for frame in 120:
			gait.advance(1.0/60.0,0,false)
			gait.apply_pose()
		check(gait.move_weight==0 and gait.run_weight==0,"Stopping blends to rest")
		check(actor.base_walk_speed==speed and actor.get_node("CollisionShape2D").shape==collision,"Gaits do not alter speed or collision")
		actor._advance_gait(1.0/60.0)
		for frame in 30:
			actor.position.x+=1
			actor._advance_gait(1.0/60.0)
		check(gait.move_weight>0,"Real displacement advances locomotion")
		actor.velocity=Vector2(100,0)
		for frame in 120: actor._advance_gait(1.0/60.0)
		check(gait.move_weight==0,"Blocked or stopped actors settle despite desired velocity")
		actor.is_gangster=true
		actor.combat_target=Node2D.new()
		stage.add_child(actor.combat_target)
		actor.right_upper_arm.rotation=Vector3(1.4,-.05,0)
		var armed_pose=actor.right_upper_arm.rotation
		gait.apply_pose()
		check(actor.right_upper_arm.rotation.is_equal_approx(armed_pose),"Locomotion preserves armed arm pose")
		actor.combat_target.free()
		actor.free()
	for i in 4:
		for j in range(i+1,4): check(signatures[i*2].distance_to(signatures[j*2])>.01,"Walking profiles have distinct poses")
	var nurse=load("res://world/harbor/interiors/HarborConversationalNPC.gd").new()
	stage.add_child(nurse)
	check(nurse.head_node.has_node("CitizenFace"),"Staff have the same facial system")
	print("NPC_PERSONALITY_RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
