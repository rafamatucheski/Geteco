extends "res://tests/test_harbor_turn_pedestrian_startup.gd"

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var layout = preload("res://world/harbor/HarborRoadLayout.gd").new()
	layout.name = "RoadLayout"
	world.add_child(layout)
	var network = preload("res://world/harbor/HarborRoadNetwork.gd").new()
	network.name = "RoadNetwork"
	network.provider_paths.assign([NodePath("../RoadLayout")])
	world.add_child(network)
	var rail := Node2D.new()
	rail.name = "FreightRail"
	world.add_child(rail)
	var life := TestLife.new()
	world.add_child(life)
	life.setup(network)
	life.set_process(false)
	var ped_case := OS.get_cmdline_user_args().has("--pedestrian")
	var turn: Path2D
	for candidate in get_nodes_in_group("unified_lane_connector"):
		var wanted := "6:RoadLayout/foundry_avenue/forward_01>RoadLayout/warehouse_way/forward_01" if ped_case else "11:RoadLayout/market_street/reverse_01>RoadLayout/union_avenue/reverse_01"
		if String(candidate.get_meta("traffic_connection_id", "")) == wanted: turn = candidate
	if turn == null:
		quit(1)
		return
	var car := preload("res://world/shared/emergency/ModernTrafficFactory.gd").spawn_moving_vehicle(turn, "HarborTraffic_32", "summit_suv", 0.0, 89.6, 32)
	car.set_process(false)
	car.set_physics_process(false)
	var follow: PathFollow2D = car.get_parent()
	follow.progress = 66.226776 if ped_case else 123.33908
	var person: CharacterBody2D
	if ped_case:
		person = preload("res://world/harbor/HarborLife.gd").HarborWalker.new()
		person.configure_authored_route(PackedVector2Array([Vector2(2277,482),Vector2(2277,1168)]), "fixture", 0.0)
		world.add_child(person)
		person.set_physics_process(false)
		person.global_position = Vector2(2255.712,467.434)
	await physics_frame
	await physics_frame
	var target := turn.to_global(turn.curve.sample_baked(follow.progress + 1, true))
	var contact := KinematicCollision2D.new()
	var blocked := car.test_move(car.global_transform, target - car.global_position, contact)
	print("HARBOR_CORNER_CONTACT at=", car.global_position, " rotation=", car.global_rotation, " blocked=", blocked, " collider=", contact.get_collider().get_path() if blocked else "none")
	if person:
		print("GUARD_PED block=",car._lane_pedestrian_blocks(follow,person,false)," car_shape=",car.collision.shape.get_rect())
		for child in person.get_children():
			if child is CollisionShape2D: print("PED_SHAPE ",child.shape.get_rect()," transform=",child.transform)
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = car.collision.shape
		query.transform = Transform2D(PI/2,Vector2(2227.5,467.434)) * car.collision.transform
		query.collision_mask = 4
		print("AT_PEDESTRIAN_PASSAGE physical_hits=",world.get_world_2d().direct_space_state.intersect_shape(query))
		var controller = car._get_junction_traffic_controller()
		var connection: Dictionary = controller._connections_by_id[String(turn.get_meta("traffic_connection_id"))]
		var next_path: Path2D = controller._lane_paths_by_id[String(connection.to_lane_id)]
		var min_distance := INF
		var min_pose := Transform2D.IDENTITY
		var spans: Array = [[turn, follow.progress, turn.curve.get_baked_length()], [next_path, float(connection.exit_curve_offset),float(connection.exit_curve_offset)+180]]
		for span in spans:
			for offset in range(int(span[1]), int(span[2])+1):
				var pose: Transform2D = span[0].global_transform * span[0].curve.sample_baked_with_rotation(offset,true) * car.collision.transform
				var relative := pose.affine_inverse()*person.global_position
				var half: Vector2 = car.collision.shape.size*.5
				var distance := relative.distance_to(relative.clamp(-half,half))
				if distance < min_distance:
					min_distance = distance
					min_pose = pose
		query.transform = min_pose
		print("MIN_GUARD_DISTANCE ",min_distance," pose=",min_pose," actual_hits=",world.get_world_2d().direct_space_state.intersect_shape(query))
		person.route_points = PackedVector2Array([Vector2(2123,482),Vector2(2277,482),Vector2(2277,1168),Vector2(2123,1168),Vector2(2123,482)])
		person.route_loop = true
		person._route_segment = 0
		person._route_direction = 1
		person._route_target_ready = true
		person.walk_target = Vector2(2277,482)
		person.sidewalk_half_width = 14
		person.pause_at_destinations = false
		person._destination_pause = 0
		person._pick_new_sidewalk_target()
		check(person._route_segment == 0,"A delayed pedestrian keeps the current corner instead of skipping across the road")
		person.set_physics_process(true)
		var reached_corner := false
		var previous := person.global_position
		var max_step := 0.0
		for frame in 360:
			await physics_frame
			reached_corner = reached_corner or person.global_position.distance_to(Vector2(2277,482)) <= 3.1
			max_step = maxf(max_step,previous.distance_to(person.global_position))
			previous = person.global_position
		check(reached_corner,"The resident walks to the authored corner before continuing along the sidewalk")
		check(not car._lane_pedestrian_blocks(follow,person,false),"The resident clears the real vehicle turning envelope")
		check(max_step < 2,"Sidewalk correction uses continuous physical movement")
		print("HARBOR_CORNER_RECOVERY failures=",failures," pedestrian=",person.global_position," max_step=",max_step)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
