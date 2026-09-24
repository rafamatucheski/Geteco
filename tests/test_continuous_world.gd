extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	create_timer(90).timeout.connect(func(): printerr("CONTINUOUS WORLD TIMEOUT"); quit(2))
	var saves := root.get_node("SaveManager")
	var output := ProjectSettings.globalize_path("user://tests/continuous-world")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	if DirAccess.make_dir_recursive_absolute(output.path_join("saves")) != OK:
		push_error("Cannot create continuous-world test output: " + output)
		quit(1)
		return
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_maciota_met", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 25: await process_frame
	var world := current_scene
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	var stream := world.get_node("ContinuousWorld")
	check(stream.mountain == null, "mountain is not instantiated at city startup")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var mountain: Node2D = stream.mountain
	var harbor_life = world.get_node_or_null("Life")
	var harbor_controller = harbor_life.get("traffic_controller") if harbor_life != null else null
	check(harbor_controller != null and harbor_controller.has_method("is_simulation_suspended"), "Harbor traffic controller exposes suspension state")
	if harbor_controller == null or not harbor_controller.has_method("is_simulation_suspended"):
		quit(1)
		return
	check(not harbor_controller.is_simulation_suspended(), "Harbor traffic controller starts active")
	var player: Node2D = world.get_node("Player")
	var player_id := player.get_instance_id()
	var world_id := world.get_instance_id()
	check(get_nodes_in_group("player").size()==1, "one player across both regions")
	check(get_nodes_in_group("weapon_effects").size()==1, "one combat effects system")
	check(not mountain.has_node("HarborReturnCrossing"), "no teleport border in production")
	check(mountain.to_global(mountain.road.control_points[0])==Vector2(7300,-4560), "mountain physically adjoins Harbor road")
	var car = ModernTrafficFactory.spawn_parked_vehicle(world,"ContinuousReviewCar",Vector2(7050,-4529),0,"summit_suv",0,Color("2b6995"))
	var car_id := car.get_instance_id()
	player.global_position = car.global_position+Vector2(0,-50)
	car.enter_vehicle(player)
	print("BOARDING ",car.is_driven_by_player," processing=",car.is_physics_processing()," treepaused=",paused," pos=",car.global_position)
	var boarding_deadline := Time.get_ticks_msec() + 6000
	while is_instance_valid(car._boarding) and car._boarding.active and Time.get_ticks_msec() < boarding_deadline:
		await process_frame
	check(not is_instance_valid(car._boarding) or not car._boarding.active, "boarding completes before driving")
	for i in 3: await physics_frame
	var health: int = car.health
	var previous: Vector2 = car.global_position
	var largest_step := 0.0
	Input.action_press("move_up")
	for i in 200:
		await physics_frame
		largest_step = maxf(largest_step,car.global_position.distance_to(previous))
		previous = car.global_position
	Input.action_release("move_up")
	stream._update_region()
	print("CROSSING RESULT ",car.global_position," velocity=",car.velocity," health=",car.health," driven=",car.is_driven_by_player," process=",car.can_process()," armed=",car._drive_input_armed)
	check(current_scene.get_instance_id()==world_id and player.get_instance_id()==player_id and car.get_instance_id()==car_id,"world/player/car instances survive physical crossing")
	check(car.global_position.x>7500 and largest_step<20 and car.health==health,"drive over seam without jump or invisible barrier")
	check(stream.current_region=="mountain", "region weather changes geographically")
	check(not harbor_controller.is_simulation_suspended(), "Harbor traffic controller stays active in the seam handoff neighborhood")
	stream._update_harbor_suspension(false)
	check(harbor_controller.is_simulation_suspended(), "Harbor traffic controller suspends outside the Harbor neighborhood")
	stream.population_activity.stats = {}
	stream._budget_traffic(mountain.global_position)
	check(not stream.population_activity.stats.is_empty(), "Population budget remains active while Harbor is suspended")
	stream._update_harbor_suspension(true)
	check(not harbor_controller.is_simulation_suspended(), "Harbor traffic controller resumes after the handoff neighborhood")
	check(not world.weather.is_inside_interior, "mountain exterior retains the world day/night lighting")
	world.weather.atmosphere.refresh_immediately()
	check(world.weather.atmosphere.mountain_weight > 0.2, "driving onto the bridge blends toward mountain atmosphere")
	check(get_nodes_in_group("regional_atmosphere").size() == 1, "streaming adds no duplicate atmosphere compositor")
	var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(snapshot.region=="mountain" and snapshot.coordinates_version==2,"save uses continuous world coordinates")
	check(load("res://world/harbor/HarborSceneRoute.gd").for_save({"world":snapshot}).ends_with("HarborGame.tscn"),"mountain save opens unified world")
	car.velocity = Vector2.ZERO
	car.global_position = Vector2(7540,-4591)
	car.rotation = PI
	previous = car.global_position
	Input.action_press("move_up")
	# Same acceleration window as outbound: both legs start from rest.
	for i in 200:
		await physics_frame
		largest_step = maxf(largest_step,car.global_position.distance_to(previous))
		previous = car.global_position
	Input.action_release("move_up")
	stream._update_region()
	print("RETURN RESULT ", car.global_position, " velocity=", car.velocity)
	check(car.global_position.x<7300 and largest_step<20 and stream.current_region=="harbor","return over seam without scene change")
	check(not harbor_controller.is_simulation_suspended(), "Harbor traffic controller resumes on return")
	world.weather.atmosphere.refresh_immediately()
	check(world.weather.atmosphere.mountain_weight < 0.3, "returning west recovers harbor atmosphere geographically")
	print("STREAM STATS ",stream.get_streaming_stats()," largest_frame_displacement=",largest_step)
	if DisplayServer.get_name()!="headless":
		car.velocity = Vector2.ZERO
		car.set_physics_process(false)
		var camera := Camera2D.new()
		camera.position = Vector2(7300,-4560)
		camera.zoom = Vector2.ONE*0.75
		world.add_child(camera)
		camera.reset_physics_interpolation()
		camera.make_current()
		for i in 3: await physics_frame
		camera.force_update_scroll()
		check(camera.get_screen_center_position().distance_to(Vector2(7300,-4560)) < 1.0, "capture camera is centered on the physical seam")
		await process_frame
		await RenderingServer.frame_post_draw
		var image_error := root.get_texture().get_image().save_png(output.path_join("bridge.png"))
		check(image_error == OK, "rendered crossing evidence is saved")
	print("CONTINUOUS WORLD FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
