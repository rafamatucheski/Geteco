extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var actor = load("res://scripts/Actor.gd").new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	for spec in [["Walking",1.8,Vector3.FORWARD],["Running",3.4,Vector3.FORWARD],["Walk_Backward_with_Gun",.91,Vector3.BACK],["Walk_Left_with_Gun",.89,Vector3.RIGHT]]:
		var positions := {"Left":[],"Right":[]}
		for tick in 121:
			actor._pose_cycle(spec[0],float(tick)/120.0,actor.WALK_START if spec[0] == "Walking" else 0.0)
			var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
			hip.x = actor.hip_rest.x; hip.z = actor.hip_rest.z
			actor.skeleton.set_bone_pose_position(actor.hips,hip)
			for side in positions:
				var bone: int = actor.skeleton.find_bone(side+"ToeBase")
				positions[side].append(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone).origin) + spec[2] * spec[1] * float(tick)/120.0)
		var distance := 0.0
		var steps := 0
		for side in positions:
			var low := INF
			for point in positions[side]: low = minf(low,point.y)
			for i in range(1,positions[side].size()):
				var a: Vector3 = positions[side][i-1]
				var b: Vector3 = positions[side][i]
				if a.y < low+.02 and b.y < low+.02:
					distance += Vector2(b.x-a.x,b.z-a.z).length(); steps += 1
		print("STRIDE ",spec[0]," planted drift / root displacement=",distance/maxf(.0001,float(steps)/120.0*spec[1])," contacts=",steps)
	quit()
