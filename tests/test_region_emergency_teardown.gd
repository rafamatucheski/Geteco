extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	# Initial menu focus invokes MenuAudio while the root is busy adding children.
	change_scene_to_file("res://ui/MainMenu.tscn")
	for i in 5: await process_frame
	check(root.get_node_or_null("__MenuHoverPlayer") != null, "initial menu focus creates its audio player safely")
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 15: await physics_frame
	var director = get_first_node_in_group("emergency_depot_director")
	var player = get_first_node_in_group("player")
	var unit = director.request_dispatch("police", player)
	check(is_instance_valid(unit), "dispatch a real pooled Harbor police unit")
	if not is_instance_valid(unit):
		quit(1)
		return
	# Reproduce both expired target and child depot references from the crash log.
	var expired_target = Node2D.new()
	current_scene.add_child(expired_target)
	unit.target = expired_target
	expired_target.free()
	check(not director._owns_unit(unit), "freed target is safely rejected")
	unit.target = player
	var assignment: Dictionary = director._vehicle_assignments[unit.get_instance_id()]
	assignment.depot.free()
	check(not director._owns_unit(unit), "freed depot is safely rejected")
	check(root.get_node("RegionTravel").request("mountain", player), "travel with an assigned emergency unit")
	for i in 30: await physics_frame
	check(current_scene.scene_file_path.ends_with("MountainPass.tscn"), "arrived in Mountain Pass after Harbor teardown")
	check(is_instance_valid(unit) and not unit.visible and unit.target == null, "departing scene returns its unit and clears the stale target")
	change_scene_to_file("res://ui/MainMenu.tscn")
	for i in 10: await process_frame
	check(root.get_node_or_null("__MenuHoverPlayer") != null, "menu reopens with reusable audio")
	print("EMERGENCY TEARDOWN FAILURES: ", failures)
	quit(0 if failures.is_empty() else 1)
