extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var model = load("res://world/mountain_pass/transit/MountainArrivalTravelerModel.gd").new()
	model.winter_outfit = false
	root.add_child(model)
	model.set_process(false)
	var old_elbows: Array = model.elbows.duplicate()
	model.put_on_winter_clothes()
	await process_frame
	await process_frame
	check(model.elbows.size() == 2, "Clothing change must retain exactly two current elbows")
	for elbow in old_elbows:
		check(not is_instance_valid(elbow), "Previous rig must be released")
	var joints_valid := true
	for elbow in model.elbows:
		if not is_instance_valid(elbow):
			joints_valid = false
		else:
			check(model.is_ancestor_of(elbow), "Elbow must belong to the current rig")
	check(joints_valid, "Animation must not retain freed elbows")
	if joints_valid:
		for walking in [false, true]:
			model.walking = walking
			for activity in ["idle", "drink", "talk", "warm", "attack"]:
				model.activity = activity
				model.set_seat_pose(0.0 if walking else 1.0, 0.45, 0)
				model._process(0.1)
				for elbow in model.elbows:
					check(is_equal_approx(elbow.rotation.x, -0.18 if walking else -0.12), "Current elbows must animate after clothing change")
	var current_pose: Node3D = model.pose_root
	model.put_on_winter_clothes()
	check(model.pose_root == current_pose, "Putting on winter clothes twice must preserve the rig")
	model.free()
	print("WINTER_TRAVELER_RIG_LIFECYCLE: %d failures" % failures)
	quit(0 if failures == 0 else 1)
