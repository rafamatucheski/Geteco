extends SceneTree
var failures: Array[String] = []
var reported_blocks := {}
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func run() -> void:
	var production := OS.get_cmdline_user_args().has("--production")
	var world: Node2D
	var operations: Node2D
	if production:
		root.get_node("CampaignState").reset_campaign()
		# Exercise the live city after arrival, independent of the opening film.
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen", true)
		root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_call_complete", true)
		root.get_node("SaveManager").clear_pending_save()
		world = load("res://world/harbor/HarborGame.tscn").instantiate()
		root.add_child(world)
		current_scene = world
		for frame in 12: await process_frame
		world.campaign_controller.skip_cinematic()
		operations = world.get_node("ArrivalStop").terminal_operations
	else:
		world = Node2D.new()
		root.add_child(world)
		current_scene = world
		var view := preload("res://world/harbor/terminal/HarborTerminalView.gd").new()
		world.add_child(view)
		operations = preload("res://world/harbor/terminal/HarborTerminalOperations.gd").new()
		operations.architecture = view
		world.add_child(operations)
	operations.set_physics_process(false)
	for service in operations.fleet:
		service.set_physics_process(false)
	var gate_states: Array = operations.gates.map(func(g): return g.collision.disabled)
	for gate in operations.gates:
		gate.collision.disabled = true
	await physics_frame
	await physics_frame
	check(operations.fleet.size() == 4, "All four platforms have a physical scheduled coach")
	for service in operations.fleet:
		for curve in [service._reverse_route(), service._departure_route(), service._road_route(), service._arrival_route()]:
			for index in ceili(curve.get_baked_length() / 4.0):
				var offset := float(index) * 4.0
				var direction: Vector2 = (curve.sample_baked(minf(offset + 0.2, curve.get_baked_length())) - curve.sample_baked(maxf(0.0, offset - 0.2))).normalized()
				var query := PhysicsShapeQueryParameters2D.new()
				query.shape = service._shape_for_heading(direction)
				query.transform = Transform2D(0.0, operations.to_global(curve.sample_baked(offset)))
				query.collision_mask = 1
				var hits := world.get_world_2d().direct_space_state.intersect_shape(query, 1)
				if not hits.is_empty():
					check(false, "Platform %d swept hull blocked at %s by %s" % [service.platform_index + 1, curve.sample_baked(offset), str(hits[0].collider.get_path()) + str(hits[0].collider.get_child(0).polygon)])
					break
		service.set_physics_process(true)
	for index in operations.gates.size():
		operations.gates[index].collision.disabled = gate_states[index]
	operations.set_physics_process(true)
	if OS.get_cmdline_user_args().has("--geometry-only"):
		print("TERMINAL_GEOMETRY failures=", failures)
		quit(0 if failures.is_empty() else 1)
		return
	Engine.time_scale = 3.0 if production else 6.0
	Engine.physics_ticks_per_second = 120 if production else 180
	# Runtime cadence changes apply at the next engine frame. Start continuity
	# measurements after the old step has drained.
	for frame in 3: await physics_frame
	var started := Time.get_ticks_msec()
	var previous: Dictionary = {}
	var last_print := 0
	var saw_external := false
	while Time.get_ticks_msec() - started < (360000 if production else 100000):
		await physics_frame
		if production and world.campaign_controller.phase == "phone":
			world.campaign_controller.answer_phone()
			for line in 4: world.campaign_controller.advance_dialogue()
		var all_complete := true
		for service in operations.fleet:
			if previous.has(service):
				check(service.coach.position.distance_to(previous[service]) < 3.0, "Coach travels continuously through every route and renderer handoff: state=%s before=%s after=%s step=%f delta=%f" % [service.state,previous[service],service.coach.position,previous[service].distance_to(service.coach.position),service.get_physics_process_delta_time()])
			previous[service] = service.coach.position
			all_complete = all_complete and service.completed_laps >= 1 and service.passenger_service.history.size() >= 2
			saw_external = saw_external or service.coach.position.distance_to(Vector2.ZERO) > 650
		if all_complete: break
		var seconds := int((Time.get_ticks_msec() - started) / 1000)
		if seconds > last_print + 10:
			last_print = seconds
			print("TERMINAL_PROGRESS ", operations.get_operation_status())
			for service in operations.fleet:
				if service.blocked and not reported_blocks.has(service.blocked_by):
					reported_blocks[service.blocked_by] = true
					trace_blockage(service.coach)
			if production:
				var station = world.get_node("ArrivalStop")
				var urban = station.bus
				print("TERMINAL_LOCAL_SERVICE ", station.get_service_status(), " people=", station.passengers.map(func(p): return [p.transit_state, p.position, p.destination]))
				var rays := {}
				for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
					var ray = urban.get_node_or_null(ray_name)
					if ray and ray.is_colliding(): rays[ray_name] = str(ray.get_collider().get_path())
				print("TERMINAL_LOCAL_DIAG position=", urban.global_position, " lane=", urban.get_parent().get_parent().name, " progress=", urban.get_parent().progress, " dwelling=", urban.dwelling, " speed=", urban._lane_motion_speed, " rays=", rays, " obstacle=", urban._get_lane_obstruction(urban.get_parent()), " contract=", urban._last_lane_motion_contract, " spacing=", urban._lane_spacing_motion(urban.get_parent()))
				var controller = urban._get_junction_traffic_controller()
				for junction_index in [6, 11]:
					var junction: Dictionary = controller._states.get(junction_index, {})
					print("TERMINAL_JUNCTION ", junction_index, " ", junction)
					var owner = instance_from_id(int(junction.get("reservation_owner", 0)))
					if owner is Node2D: print_actor(owner)
				for car in get_nodes_in_group("modern_traffic"):
					if car.name in ["HarborTraffic_20", "HarborTraffic_51"]: print_actor(car)
	check(saw_external, "Coaches travel beyond the terminal to another neighborhood")
	for service in operations.fleet:
		check(service.exits >= 1 and service.entries >= 1, "Every coach departs and returns: platform %d" % (service.platform_index + 1))
		check(service.passenger_service.history.size() >= 2, "Every platform completes passenger exchanges on arrival and return")
		var passengers = service.passenger_service
		check(passengers.onboard_count() == passengers.INITIAL_ONBOARD + passengers.boarded - passengers.alighted, "Passenger occupancy is conserved across full trips")
		check(service.distance_travelled > 3000, "Each coach travels an actual district journey")
	print("HARBOR_TERMINAL_OPERATIONS production=", production, " status=", operations.get_operation_status(), " failures=", failures)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func print_actor(actor: Node2D) -> void:
	if actor is CharacterBody2D and actor.get_parent() is PathFollow2D and actor.get_parent().get_parent() is Path2D:
		var follow := actor.get_parent() as PathFollow2D
		var path := follow.get_parent() as Path2D
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(minf(path.curve.get_baked_length(), follow.progress + 1.0), follow.cubic_interp)
		var motion := pose.origin + pose.y * actor.position.y - actor.global_position
		var contact := KinematicCollision2D.new()
		var hit: bool = actor.test_move(actor.global_transform, motion, contact)
		var contact_path := str(contact.get_collider().get_path()) if hit and contact.get_collider() is Node else ""
		print("TERMINAL_CONTACT actor=", actor.name, " motion=", motion, " hit=", hit, " contact=", contact_path)
	var rays := {}
	for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
		var ray = actor.get_node_or_null(ray_name)
		if ray and ray.is_colliding(): rays[ray_name] = str(ray.get_collider().get_path())
	print("TERMINAL_ACTOR path=", actor.get_path(), " position=", actor.global_position, " rotation=", actor.global_rotation, " processing=", actor.is_physics_processing(), " can_process=", actor.can_process(), " progress=", actor.get_parent().progress if actor.get_parent() is PathFollow2D else -1, " contract=", actor.get("_last_lane_motion_contract"), " speed=", actor.get("_lane_motion_speed"), " safety=", actor._traffic_control_zone_motion(actor.get_parent().get_parent(), actor.get_parent()) if actor.has_method("_traffic_control_zone_motion") and actor.get_parent() is PathFollow2D else {}, " spacing=", actor._lane_spacing_motion(actor.get_parent()) if actor.has_method("_lane_spacing_motion") and actor.get_parent() is PathFollow2D else {}, " rays=", rays, " obstruction=", actor._get_lane_obstruction(actor.get_parent()) if actor.has_method("_get_lane_obstruction") and actor.get_parent() is PathFollow2D else {})

func trace_blockage(start: Node2D) -> void:
	var pending: Array[Node2D] = [start]
	var visited := {}
	while not pending.is_empty() and visited.size() < 10:
		var actor: Node2D = pending.pop_front()
		if not is_instance_valid(actor) or visited.has(actor.get_instance_id()): continue
		visited[actor.get_instance_id()] = true
		print_actor(actor)
		if actor.is_in_group("harbor_terminal_coach"):
			var service = actor.get_parent()
			var blocker = root.get_node_or_null(service.blocked_by) if service.blocked else null
			if blocker is Node2D: pending.append(blocker)
			continue
		var contract = actor.get("_last_lane_motion_contract")
		if contract is Dictionary and contract.get("must_stop", false) and actor.has_method("_get_junction_traffic_controller"):
			var controller = actor._get_junction_traffic_controller()
			var junction = controller._states.get(int(contract.get("junction_index", -1)), {})
			print("TERMINAL_BLOCK_JUNCTION ", junction)
			for crossing in controller._crossings_by_junction.get(int(contract.get("junction_index", -1)), []):
				if not crossing.has_pedestrian_on_roadway(): continue
				for reference in crossing._pedestrians_inside.values():
					var person = reference.get_ref()
					if not is_instance_valid(person): continue
					var hull := person.get_node_or_null("CollisionShape2D") as CollisionShape2D
					if hull == null or not hull.shape.collide(hull.global_transform, crossing._roadway_occupancy_shape, crossing.global_transform): continue
					var contact := KinematicCollision2D.new()
					var blocked: bool = person.test_move(person.global_transform, person.global_position.direction_to(person.walk_target) * 4.0, contact)
					var neighbors := []
					for other in preload("res://characters/pedestrians/PedestrianNeighborhood.gd").neighbors(person, 60.0):
						if other != person and other.global_position.distance_to(person.global_position) < 60.0: neighbors.append([str(other.get_path()), other.global_position, other.collision_layer])
					print("TERMINAL_CROSSING_OCCUPANT crossing=", crossing.get_path(), " person=", person.get_path(), " position=", person.global_position, " layer=", person.collision_layer, " visible=", person.is_visible_in_tree(), " processing=", person.can_process(), " dead=", person.get("is_dead"), " transit=", person.get("transit_state"), " target=", person.get("walk_target"), " velocity=", person.get("velocity"), " blocker=", contact.get_collider().get_path() if blocked else "", " neighbors=", neighbors, " navigation=", person.validation_state() if person.has_method("validation_state") else {})
			var owner = instance_from_id(int(junction.get("reservation_owner", 0)))
			if owner is Node2D and owner != actor: pending.append(owner)
		for ray_name in ["FrontRay", "FrontRayL", "FrontRayR"]:
			var ray = actor.get_node_or_null(ray_name)
			if ray and ray.is_colliding():
				var blocker = ray.get_collider()
				if blocker is Node2D and (blocker.is_in_group("vehicle") or blocker.is_in_group("authored_sidewalk_pedestrian")): pending.append(blocker)


