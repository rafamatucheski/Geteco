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
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
	change_scene_to_file("res://district/harbor_preview/HarborGame.tscn")
	for i in 25: await process_frame
	var world := current_scene
	var stream := world.get_node("ContinuousWorld")
	await stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var mountain: Node2D = stream.mountain
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
	for i in 3: await physics_frame
	var health: int = car.health
	var previous: Vector2 = car.global_position
	var largest_step := 0.0
	Input.action_press("ui_up")
	for i in 200:
		await physics_frame
		largest_step = maxf(largest_step,car.global_position.distance_to(previous))
		previous = car.global_position
	Input.action_release("ui_up")
	stream._update_region()
	print("CROSSING RESULT ",car.global_position," velocity=",car.velocity," health=",car.health," driven=",car.is_driven_by_player)
	check(current_scene.get_instance_id()==world_id and player.get_instance_id()==player_id and car.get_instance_id()==car_id,"world/player/car instances survive physical crossing")
	check(car.global_position.x>7500 and largest_step<20 and car.health==health,"drive over seam without jump or invisible barrier")
	check(stream.current_region=="mountain", "region weather changes geographically")
	var snapshot: Dictionary = root.get_node("RegionTravel").snapshot_world()
	check(snapshot.region=="mountain" and snapshot.coordinates_version==2,"save uses continuous world coordinates")
	check(load("res://district/harbor_preview/HarborSceneRoute.gd").for_save({"world":snapshot}).ends_with("HarborGame.tscn"),"mountain save opens unified world")
	car.velocity = Vector2.ZERO
	car.global_position = Vector2(7540,-4591)
	car.rotation = PI
	previous = car.global_position
	Input.action_press("ui_up")
	for i in 100:
		await physics_frame
		largest_step = maxf(largest_step,car.global_position.distance_to(previous))
		previous = car.global_position
	Input.action_release("ui_up")
	stream._update_region()
	check(car.global_position.x<7300 and largest_step<20 and stream.current_region=="harbor","return over seam without scene change")
	print("STREAM STATS ",stream.get_streaming_stats()," largest_frame_displacement=",largest_step)
	if DisplayServer.get_name()!="headless":
		car.velocity = Vector2.ZERO
		car.set_physics_process(false)
		var camera := Camera2D.new()
		world.add_child(camera)
		camera.position = Vector2(7300,-4560)
		camera.zoom = Vector2.ONE*0.75
		camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/continuous-bridge-review.png")
	print("CONTINUOUS WORLD FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
