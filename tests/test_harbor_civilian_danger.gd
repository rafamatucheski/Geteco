extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	var campaign := root.get_node("CampaignState")
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_arrival_delivery_complete"]:
		campaign.set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 35: await physics_frame
	var controller = current_scene.get("campaign_controller")
	if controller and controller.has_method("skip_cinematic"): controller.skip_cinematic()
	root.get_node("WantedManager").set_process(false)
	var people := get_nodes_in_group("authored_sidewalk_pedestrian")
	assert(not people.is_empty(), "Real Harbor population exists")
	var focus: Node2D = people[0]
	for person in people:
		if person.global_position.distance_to(Vector2(1750, 1950)) < focus.global_position.distance_to(Vector2(1750, 1950)):
			focus = person
	var officer = load("res://police/PoliceOfficer.tscn").instantiate()
	current_scene.add_child(officer)
	officer.set_physics_process(false)
	officer.global_position = focus.global_position - Vector2(110, 110)
	var tracked: Dictionary = {}
	for person in people:
		if person.global_position.distance_to(officer.global_position) < 550:
			tracked[person] = person.global_position
	var camera := root.get_camera_2d()
	camera.global_position = focus.global_position
	camera.zoom = Vector2.ONE * 1.6
	camera.reset_smoothing()
	for burst in 6:
		officer._shoot_at_target(officer.global_position - Vector2(500, 0))
		await create_timer(0.5).timeout
	var scared := 0
	var moved := 0
	for person in tracked:
		if person.is_scared:
			scared += 1
			if person.global_position.distance_to(tracked[person]) > 45: moved += 1
	print("HARBOR CIVILIAN DANGER nearby=", tracked.size(), " scared=", scared, " physically_escaped=", moved)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/harbor-civilian-danger.png")
	quit(0 if scared > 0 and moved > 0 else 1)
