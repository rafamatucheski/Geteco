extends SceneTree
## Behavioural checks on the production population, not a duplicate mock rig.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok and not failures.has(label):
		failures.append(label)
		push_error(label)
func run() -> void:
	seed(914)
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene=stage
	for archetype in 24:
		var actor := AnimatedPedestrian3D.new()
		actor.archetype_override=archetype
		actor.appearance_seed=archetype
		actor.body_type_override=archetype%5
		stage.add_child(actor)
		actor.ensure_presentation()
		actor.set_physics_process(false)
		var gait=actor.gait
		var flight_frames := 0
		for running in [false,true]:
			for frame in 150:
				gait.advance(1.0/60.0,2.0 if running else 1.0,running)
				gait.apply_pose()
				var both_up := true
				for side in 2:
					var foot: Node3D=gait.feet[side]
					var sole:=foot.to_global(Vector3(0,-.0325,0)).y
					both_up=both_up and sole>.008
					check(sole>=-.002,"Floor contact across all archetypes and body types")
					check(foot.global_transform.is_finite(),"Finite articulated pose")
				if both_up and running and frame>60: flight_frames+=1
				if not running: check(not both_up,"Walking always has a support foot")
				if is_instance_valid(gait.coffee):
					check(gait.coffee.global_basis.y.normalized().dot(Vector3.UP)>.999,"Carried coffee stays upright")
				if is_instance_valid(gait.cane):
					var tip: Vector3=gait.cane.to_global(Vector3(0,-.275,0))
					check(absf(tip.y-actor.model_root.global_position.y)<.002,"Cane tip reaches the floor for every body height")
		check(flight_frames>0,"Running has a flight phase")
		# A prop must constrain its own arm, leaving the other arm free.
		actor.has_briefcase=true
		actor.has_walking_stick=false
		actor.has_coffee_cup=false
		actor.has_surfboard=false
		actor.is_gangster=false
		gait.phase=0
		gait.apply_pose()
		check(absf(actor.left_upper_arm.rotation.x)>absf(actor.right_upper_arm.rotation.x)*3,"Free arm swings while the other carries a case")
		# Compare world-projected ground travel with foot displacement during stance.
		gait.run_weight=0
		gait.move_weight=1
		gait.phase=.2
		gait.apply_pose()
		var z_before: float=gait.feet[0].global_position.z
		var camera:=actor.viewport.get_camera_3d()
		var scale_px: float=(camera.unproject_position(Vector3(0,0,.01))-camera.unproject_position(Vector3(0,0,-.01))).length()*actor.sprite_3d_display.scale.x/.02
		gait.advance_distance(1.0/60.0,Vector2(0,.05),false)
		gait.apply_pose()
		var travelled: float=(gait.feet[0].global_position.z-z_before)*scale_px
		check(absf(travelled-.05)<.004,"Support foot matches measured ground displacement")
		actor.free()
	# Explicit prop coverage at every supported height, including short/tall.
	for body in 5:
		var carrier := AnimatedPedestrian3D.new()
		carrier.defer_presentation=true
		carrier.body_type_override=body
		carrier.archetype_override=1
		stage.add_child(carrier)
		carrier.has_coffee_cup=true
		carrier.has_walking_stick=true
		carrier.ensure_presentation()
		carrier.set_physics_process(false)
		for frame in 120:
			carrier.gait.advance(1.0/60.0,2.0,true)
			carrier.gait.apply_pose()
			check(carrier.gait.coffee.global_basis.y.normalized().dot(Vector3.UP)>.999,"Cup stays upright across five body types")
			check(absf(carrier.gait.cane.to_global(Vector3(0,-.275,0)).y)<.002,"Cane reaches floor across five body types")
		carrier.free()
	stage.queue_free()
	await process_frame
	print("CITIZEN_QUALITY_RESULT archetypes=24 failures=",failures)
	quit(0 if failures.is_empty() else 1)
