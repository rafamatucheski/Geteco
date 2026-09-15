extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)
		push_error(label)
func run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene=stage
	for body in 5:
		for profile in 4:
			var actor := AnimatedPedestrian3D.new()
			actor.defer_presentation=true
			actor.body_type_override=body
			actor.appearance_seed=profile
			actor.archetype_override=1
			stage.add_child(actor)
			actor.has_coffee_cup=false
			actor.has_briefcase=false
			actor.has_walking_stick=false
			actor.has_surfboard=false
			actor.ensure_presentation()
			actor.set_physics_process(false)
			actor.gait.move_weight=1
			actor.gait.run_weight=1
			for sample in 48:
				actor.model_root.rotation.y=(sample%4)*PI*.5
				actor.gait.phase=sample*TAU/48
				actor.gait.apply_pose()
				for forearm in [actor.left_lower_arm,actor.right_lower_arm]:
					var elbow: Vector3=actor.model_root.to_local(forearm.global_position)
					var wrist: Vector3=actor.model_root.to_local(forearm.to_global(Vector3(0,-.215,0)))
					# Character forward is -Z. The elbow must bend the hand forward,
					# regardless of facing, body width or the upper arm's swing.
					check(wrist.z<elbow.z-.01,"Running wrist bends forward from the elbow")
			actor.gait.run_weight=0
			for phase in [0.0,PI]:
				actor.gait.phase=phase
				actor.gait.apply_pose()
				var shoulder: Vector3=actor.model_root.to_local(actor.left_upper_arm.global_position)
				var elbow: Vector3=actor.model_root.to_local(actor.left_lower_arm.global_position)
				var foot: Vector3=actor.model_root.to_local(actor.gait.feet[0].global_position)
				check((elbow.z-shoulder.z)*foot.z<0,"Arm and same-side leg swing in opposition")
			actor.free()
	stage.queue_free()
	await process_frame
	print("CITIZEN_RUN_ARMS: ",failures)
	quit(0 if failures.is_empty() else 1)
