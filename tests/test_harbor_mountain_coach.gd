extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	root.get_node("CampaignState").reset_campaign()
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_phone_answered", true)
	root.get_node("SaveManager").clear_pending_save()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 12:
		await process_frame
	var services := get_nodes_in_group("regional_coach_service")
	var service: Node2D
	if services.is_empty():
		service = preload("res://geodata/transit/HarborMountainCoachService.gd").new()
		world.add_child(service)
		service.configure(world, world.get_node("ContinuousWorld"))
	else:
		service = services[0]
	var started := Time.get_ticks_msec()
	while service.access_lane == null and Time.get_ticks_msec() - started < 180000:
		await process_frame
	check(service.access_lane != null, "Coach requests the mountain destination without player travel")
	if service.access_lane == null:
		quit(1)
		return
	service.set_process(false)
	service.coach.set_process(false)
	for frame in 20:
		await process_frame
	await physics_frame
	await physics_frame
	check(service.coach.is_3d_vehicle, "Regional coach uses the native vehicle renderer")
	check(service.coach.is_in_group("regional_coach"), "Regional coach is exempt from distant ambient traffic suspension")
	check(service.coach.process_mode == Node.PROCESS_MODE_PAUSABLE, "Regional coach survives sleeping region but obeys game pause")
	var life: Node = world.get_node_or_null("Life")
	check(life != null, "Production Harbor ambient population is available for spawn safety audit")
	if life != null:
		for lane in life._traffic_lanes:
			check(not String(lane.get_meta("traffic_lane_id", "")).contains("map2_temporary_return"), "Ambient traffic never seeds beyond the short return link's last usable turn entry")
	check(service._plan_city(service.outbound_lane, service.outbound_lane.curve.get_baked_length()), "Directed Harbor to mountain bridge route exists")
	var outbound_legs: Array = service.city_legs.duplicate()
	print("REGIONAL_OUTBOUND_LEGS=", outbound_legs.size())
	for leg in outbound_legs:
		check_sweep(service, leg.path, float(leg.start), float(leg.end))
	var return_probe := CharacterBody2D.new()
	return_probe.position = service.inbound_lane.to_global(service.inbound_lane.curve.sample_baked(0.0, true))
	world.add_child(return_probe)
	var return_planner := preload("res://geodata/transit/RegionalCoachLanePlanner.gd").new()
	return_planner.start_lane = service.inbound_lane
	return_planner.goal_lane = service.harbor_lane
	var return_legs: Array = return_planner.plan(return_probe, service.harbor_lane.to_global(service.harbor_lane.curve.sample_baked(service.harbor_offset, true)))
	check(not return_legs.is_empty(), "Directed return route reaches Harbor's actual platform lane")
	print("REGIONAL_RETURN_LEGS=", return_legs.size())
	for leg in return_legs:
		check_sweep(service, leg.path, float(leg.start), float(leg.end))
	return_probe.queue_free()
	check_sweep(service, service.mountain_lane, 0, service.mountain_entry_offset)
	check_sweep(service, service.access_lane, 0, service.access_lane.curve.get_baked_length())
	check_sweep(service, service.mountain_lane, service.mountain_exit_offset, service.mountain_lane.curve.get_baked_length())
	for pair in [[service.outbound_lane, service.outbound_lane.curve.get_baked_length(), service.mountain_lane, 0.0], [service.mountain_lane, service.mountain_entry_offset, service.access_lane, 0.0], [service.access_lane, service.access_lane.curve.get_baked_length(), service.mountain_lane, service.mountain_exit_offset], [service.mountain_lane, service.mountain_lane.curve.get_baked_length(), service.inbound_lane, 0.0]]:
		var from: Vector2 = pair[0].to_global(pair[0].curve.sample_baked(pair[1], true))
		var to: Vector2 = pair[2].to_global(pair[2].curve.sample_baked(pair[3], true))
		check(from.distance_to(to) < 0.1, "Regional route lane handoff endpoints meet without teleporting")
	# A separately occupied bay denies the reservation; clearing it admits one coach.
	var occupied := StaticBody2D.new()
	occupied.collision_layer = 2
	occupied.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = Vector2(120, 34)
	occupied.add_child(shape)
	occupied.position = service.access_lane.to_global(service.MOUNTAIN_BERTH)
	world.add_child(occupied)
	await physics_frame
	await physics_frame
	service.berth_owner = null
	if OS.get_cmdline_user_args().has("--gateway-only"):
		for lane in get_nodes_in_group("unified_traffic_lane"):
			if String(lane.get_meta("traffic_lane_id", "")).ends_with("map2_highway_outbound/forward_01"):
				var follow: PathFollow2D = service.coach.get_parent()
				follow.reparent(lane, false)
				follow.progress = lane.curve.get_closest_offset(lane.to_local(Vector2(6098, -3600)))
				service.coach.position = Vector2.ZERO
				service.coach.rotation = 0.0
				service.coach.dwelling = false
				service.coach.doors = 0.0
				service.coach.stop_lane = service.access_lane
				service.coach.stop_offset = service.mountain_berth_offset
				service.coach.stop_armed = true
				service.state = "outbound"
				service._plan_city(service.outbound_lane, service.outbound_lane.curve.get_baked_length())
				break
	check(not service.request_berth(service.coach), "An occupied mountain berth rejects another coach")
	occupied.queue_free()
	await physics_frame
	await physics_frame
	check(service.request_berth(service.coach), "Free mountain berth admits the regional coach")
	var other := Node2D.new()
	world.add_child(other)
	check(not service.request_berth(other), "Exactly one coach owns the mountain platform")
	other.queue_free()
	service.berth_owner = null
	# A main-road car retains priority while the returning bus waits on its spur.
	var prior_state: String = service.state
	service.state = "returning"
	var blocker := PathFollow2D.new()
	blocker.loop = false
	service.mountain_lane.add_child(blocker)
	blocker.progress = service.mountain_exit_offset - 500.0
	blocker.add_child(Node2D.new())
	var hold: float = service.access_lane.curve.get_baked_length() - 250.0
	check(is_equal_approx(service.lane_stop_limit(service.access_lane, hold), hold), "Returning coach waits before the merge when a car approaches on the curved main lane")
	check(not service._return_merge_committed, "Occupied road cannot grant a merge commitment")
	blocker.queue_free()
	await process_frame
	service.state = prior_state
	if OS.get_cmdline_user_args().has("--geometry-only"):
		print("REGIONAL_COACH_GEOMETRY failures=", failures.size())
		world.queue_free()
		for frame in 4:
			await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	service.set_process(true)
	service.coach.set_process(true)
	var same_coach_id:int=service.coach.get_instance_id()
	var original_physics_ticks:=Engine.physics_ticks_per_second
	var original_max_steps:=Engine.max_physics_steps_per_frame
	# Accelerate wall time while retaining the normal 1/60-second physical step.
	Engine.physics_ticks_per_second=480
	Engine.max_physics_steps_per_frame=16
	Engine.time_scale = 8.0
	for frame in 8:await physics_frame
	check(world.get_physics_process_delta_time()<=1.0/60.0+0.00001,"Accelerated full journey retains normal physics substeps")
	print("REGIONAL_SIMULATION physics_delta=",world.get_physics_process_delta_time()," time_scale=",Engine.time_scale)
	var prior: Vector2 = service.coach.global_position
	var jumps := false
	started = Time.get_ticks_msec()
	var last_state := ""
	var last_trace := started
	var last_actual_motion := started
	var motion_anchor := prior
	# The full city/serra route includes normal red lights and ambient queues;
	# allow slow headless hosts enough wall time to simulate the entire journey.
	while service.completed_round_trips < 1 and Time.get_ticks_msec() - started < 1800000:
		await process_frame
		var position: Vector2 = service.coach.global_position
		if position.distance_to(motion_anchor) > 1.0:
			motion_anchor = position
			last_actual_motion = Time.get_ticks_msec()
		jumps = jumps or prior.distance_to(position) > 16.1
		prior = position
		if service.state != last_state:
			last_state = service.state
			print("REGIONAL_COACH_STATE=",last_state," position=",position," status=",service.get_service_status())
		if Time.get_ticks_msec() - last_trace > 12000:
			last_trace = Time.get_ticks_msec()
			var follow: PathFollow2D = service.coach.get_parent()
			print("REGIONAL_PROGRESS position=",position," lane=",follow.get_parent().name," progress=",follow.progress," speed=",service.coach._lane_motion_speed," blocked=",service.coach.block_wait_timer," planned=",follow.get_meta("traffic_planned_connection_id", ""))
			# A positive float remainder at a stop line can leave the runtime
			# wait timer at zero. Diagnose lack of displacement independently.
			if service.coach.block_wait_timer > 10.0 or Time.get_ticks_msec()-last_actual_motion > 12000:
				print("REGIONAL_BLOCK_CONTRACT=", service.coach._last_lane_motion_contract)
				print("REGIONAL_BLOCK_ZONE=",service.coach._traffic_control_zone_motion(follow.get_parent(),follow)," stagnant_ms=",Time.get_ticks_msec()-last_actual_motion)
				var authority = service.coach._get_junction_traffic_controller()
				if authority != null:
					for junction_index in authority._states.keys():
						var state: Dictionary = authority._states[junction_index]
						var owner_id := int(state.reservation_owner)
						if owner_id == 0: continue
						print("REGIONAL_RESERVED_STATE index=",junction_index," state=",state)
						if is_instance_id_valid(owner_id):
							var owner: Node2D = instance_from_id(owner_id)
							print("REGIONAL_RESERVED_OWNER actor=",owner.get_path()," position=",owner.global_position," can=",owner.can_process()," contract=",owner.get("_last_lane_motion_contract"))
							if owner.get_parent() is PathFollow2D and owner.has_method("_traffic_control_zone_motion"):
								print("REGIONAL_RESERVED_ZONE=",owner._traffic_control_zone_motion(owner.get_parent().get_parent(),owner.get_parent()))
				for car in get_nodes_in_group("vehicle"):
					if car is Node2D and car != service.coach and car.global_position.distance_to(position) < 1200:
						print("REGIONAL_NEIGHBOR name=",car.name," position=",car.global_position," parent=",car.get_parent().name," speed=",car.get("_lane_motion_speed")," process=",car.is_processing()," can=",car.can_process())
						if car.get_parent() is PathFollow2D:
							print("NEIGHBOR_CONTRACT name=",car.name," contract=",car.get("_last_lane_motion_contract")," planned=",car.get_parent().get_meta("traffic_planned_connection_id", "")," progress=",car.get_parent().progress)
						for sensor_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
							var sensor := car.get_node_or_null(sensor_name) as RayCast2D
							if sensor != null and sensor.is_colliding():
								var obstruction_actor: Node = sensor.get_collider()
								print("NEIGHBOR_BLOCKER car=",car.name," sensor=",sensor_name," blocker=",obstruction_actor.get_path()," process=",obstruction_actor.is_processing()," can=",obstruction_actor.can_process()," groups=",obstruction_actor.get_groups())
				for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
					var ray: RayCast2D = service.coach.get_node(ray_name)
					if ray.is_colliding(): print("REGIONAL_RAY ",ray_name," collider=",ray.get_collider().get_path())
	check(service.mountain_arrivals >= 1, "Same coach physically reaches the mountain terminal")
	check(service.completed_round_trips >= 1, "Same coach returns to Harbor on the actual roads")
	check(not jumps and service.max_handoff_displacement < 1.0, "Regional journey has no teleporting lane handoffs")
	check(service.coach.get_instance_id()==same_coach_id,"One persistent coach completes departure, arrival and return")
	var passengers:Node=service._passenger_exchange()
	check(passengers!=null and not passengers.history.is_empty(),"Mountain arrival records a real passenger manifest")
	if passengers!=null and not passengers.history.is_empty():
		var manifest:Dictionary=passengers.history[0]
		check(int(manifest.alighted)==int(manifest.expected) and int(manifest.expected)>0,"Every manifested traveler physically disembarks")
		check(passengers.purchases>=int(manifest.shopping) and passengers.purchases>0,"Arriving shoppers purchase winter clothing during the live round trip")
		check(passengers.completed_rests>0,"Travelers complete a real bench rest while the regional service continues")
		print("REGIONAL_PASSENGERS manifests=",passengers.history," purchases=",passengers.purchases," bench_rests=",passengers.completed_rests)
	if service.completed_round_trips>=1:
		var departure_wait:=Time.get_ticks_msec()
		while service.departures<3 and Time.get_ticks_msec()-departure_wait<120000:
			await process_frame
		check(service.departures>=3 and service.state=="outbound","After normal Harbor dwell, the same coach begins the next trip autonomously")
		check(service.coach.get_instance_id()==same_coach_id,"Repeated service reuses the returning coach")
		print("REGIONAL_NEXT_DEPARTURE ",service.get_service_status())
	print("REGIONAL_COACH_RESULT status=", service.get_service_status(), " failures=", failures.size())
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second=original_physics_ticks
	Engine.max_physics_steps_per_frame=original_max_steps
	world.queue_free()
	for frame in 4:
		await process_frame
	quit(0 if failures.is_empty() else 1)

func check_sweep(service: Node2D, path: Path2D, start: float, end: float) -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = service.coach.collision.shape
	query.collision_mask = 1
	# The north access passes below the mountain bridge. Ask its actual layer
	# controller which bodies belong to the other deck at each sampled pose.
	# An unfiltered shape query would incorrectly hit the lower access rails.
	var deck_controller := current_scene.get_node_or_null("Gateway/Works")
	var deck_probe := CharacterBody2D.new()
	deck_probe.collision_layer = 0
	deck_probe.collision_mask = 1
	current_scene.add_child(deck_probe)
	var samples := maxi(1, ceili((end - start) / (2.0 if path.is_in_group("unified_lane_connector") else 18.0)))
	for index in range(samples + 1):
		var offset := lerpf(start, end, float(index) / samples)
		query.transform = path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
		deck_probe.global_transform = query.transform
		if deck_controller != null and deck_controller.has_method("update_actor_layer"):
			deck_controller.update_actor_layer(deck_probe)
			var excluded: Array[RID] = []
			for body in deck_probe.get_collision_exceptions():
				excluded.append(body.get_rid())
			query.exclude = excluded
		query.motion = Vector2.ZERO
		var hits := service.get_world_2d().direct_space_state.intersect_shape(query, 4)
		if not hits.is_empty():
			print("REGIONAL_SWEEP_HIT lane=",path.name," offset=",offset," point=",query.transform.origin," collider=",hits[0].collider.get_path())
			check(false, "Coach hull must clear world geometry along " + path.name)
			deck_probe.queue_free()
			return
		if path.is_in_group("unified_lane_connector"):
			query.motion = path.to_global(path.curve.sample_baked(minf(end,offset+14.4), true))-query.transform.origin
			query.margin = 0.1
			var fractions := service.get_world_2d().direct_space_state.cast_motion(query)
			if fractions[0] < 0.999:
				query.transform.origin += query.motion * fractions[1]
				query.motion = Vector2.ZERO
				var contacts := service.get_world_2d().direct_space_state.intersect_shape(query,4)
				print("REGIONAL_TURN_SWEEP_HIT lane=",path.name," offset=",offset," fractions=",fractions," contacts=",contacts)
				check(false, "Full moving coach must clear the complete turn sweep along "+path.name)
				deck_probe.queue_free()
				return
	deck_probe.queue_free()
