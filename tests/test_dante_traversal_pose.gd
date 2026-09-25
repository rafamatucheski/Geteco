extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var actor = load("res://scripts/Actor.gd").new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	var failures: Array[String] = []
	var length: float = actor.animation.get_animation("Fast_Ladder_Climb").length
	var min_y := INF
	var max_y := -INF
	for frame in 121:
		actor._pose_clip("Fast_Ladder_Climb", length * frame / 120.0)
		var hip: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
		min_y = minf(min_y, hip.y)
		max_y = maxf(max_y, hip.y)
		if Vector2(hip.x, hip.z).distance_to(Vector2(actor.hip_rest.x, actor.hip_rest.z)) > 0.001: failures.append("ladder horizontal root")
	if max_y - min_y > 0.25: failures.append("ladder duplicates vertical travel")
	actor._apply_pose(actor._idle_pose)
	var knee: int = actor.skeleton.find_bone("RightLeg")
	var standing: Quaternion = actor.skeleton.get_bone_pose_rotation(knee)
	actor.pose_vehicle(1.0)
	var knee_bend := standing.angle_to(actor.skeleton.get_bone_pose_rotation(knee))
	if knee_bend < 0.55: failures.append("seat does not bend knees")
	actor.pose_vehicle(0.0, 1.0, -1)
	var left: Vector3 = actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("LeftFoot")).origin
	var right: Vector3 = actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("RightFoot")).origin
	if absf(left.y - right.y) < 0.25: failures.append("open boarding does not lift one leg")
	for bone in actor.skeleton.get_bone_count():
		if not actor.skeleton.get_bone_global_pose(bone).is_finite(): failures.append("nonfinite bone")
	print("DANTE_TRAVERSAL root_y_range=",max_y-min_y," knee_bend=",knee_bend," failures=",failures)
	quit(0 if failures.is_empty() else 1)
