extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func run() -> void:
	create_timer(120).timeout.connect(func(): print("FAIL taxi test timeout"); quit(2))
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	var world := current_scene
	while not world.gameplay_ready: await process_frame
	var player: CharacterBody2D = world.get_node("Player")
	var cab: CharacterBody2D
	for vehicle in get_nodes_in_group("ambient_traffic"):
		if vehicle.active_archetype_id == "taxi_yellow" and vehicle.get_parent() is PathFollow2D:
			var path: Path2D = vehicle.get_parent().get_parent()
			if path.curve.get_baked_length()-vehicle.get_parent().progress > 400:
				cab = vehicle
				break
	check(cab != null,"city spawns moving taxis")
	if cab == null: quit(1); return
	# Keep the selected street free of random traffic during the arrival assertion.
	for vehicle in get_nodes_in_group("ambient_traffic"):
		if vehicle != cab: vehicle.queue_free()
	await physics_frame
	player.global_position = cab.to_global(Vector2(0,45))
	player.is_control_disabled = false
	player.is_in_dialogue = false
	player.set_physics_process(false)
	cab.enter_vehicle(player)
	var service = cab._taxi_service
	check(service != null and service.state == "offer","interact offers passenger or theft")
	check(not cab.is_driven_by_player and player.is_control_disabled,"offer blocks movement without stealing")
	var start: Vector2 = cab.global_position
	await create_timer(0.2).timeout
	check(cab.global_position.distance_to(start)<1,"hailed taxi waits for the conversation")
	service.cancel()
	check(not player.is_control_disabled and not player.is_in_dialogue,"cancel restores actor controls")
	cab.enter_vehicle(player)
	var original_path: Path2D = service.source_lane
	var offset: float = cab.get_parent().progress
	service._board()
	check(cab.taxi_passenger and cab._boarding.side == 1,"passenger boards the passenger side")
	while cab.has_meta("vehicle_boarding"): await process_frame
	await physics_frame
	await physics_frame
	check(service.state == "destinations","driver asks destination after boarding")
	check(service.destinations.size() >= 6,"map exposes real exterior locations")
	check(cab.body_model.paint.albedo_color.is_equal_approx(Color("ffc526")),"cab has New York yellow paint")
	check(cab.body_model.get_node("TaxiDriver").visible,"NPC stays in driver's seat")
	var occupant: Node3D = cab.body_model.get_node("DanteCabinOccupant")
	check(occupant.position.x > 0,"passenger stays in right seat")
	check(not get_nodes_in_group("pedestrian").any(func(node): return node is CarjackedDriver),"passenger boarding does not eject driver")
	var real_routes := 0
	var junction_route: Array[Dictionary] = []
	for i in service.destinations.size():
		service._select(i)
		if not service.route.is_empty():
			real_routes += 1
			if service.route.size() >= 3 and junction_route.is_empty():
				junction_route.assign(service.route.slice(0,3).duplicate(true))
	if OS.get_cmdline_user_args().has("--capture"):
		service._select(0)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/taxi-map.png")
	check(real_routes >= 3,"at least three real POIs have a connected lane route")
	service.destinations.append({"id":"test_far","label":"Unreachable","position":Vector2(999999,999999)})
	service._select(service.destinations.size()-1)
	check(service.route.is_empty() and service.column.get_node("Depart").disabled,"unreachable destination cannot begin a ride")
	# A real lane provides a short deterministic end-to-end trip.
	var target := original_path.to_global(original_path.curve.sample_baked(offset+200,true))
	service.destinations.append({"id":"test_stop","label":"Parada de teste","position":target})
	service._select(service.destinations.size()-1)
	check(not service.route.is_empty(),"same-lane destination is reachable")
	service.start_ride()
	Input.action_press("ui_up")
	Input.action_press("handbrake")
	var began := Time.get_ticks_msec()
	while cab.taxi_passenger and Time.get_ticks_msec()-began<12000:
		await process_frame
	Input.action_release("ui_up")
	Input.action_release("handbrake")
	check(not cab.taxi_passenger and not cab.is_driven_by_player,"ride arrives and disembarks automatically")
	check(cab.global_position.distance_to(target)<10,"ride stops at selected road position")
	check(player.visible and player.is_physics_processing() and not player.is_control_disabled,"arrival returns walking controls")
	if cab.is_driven_by_player: cab.force_exit_vehicle()
	check(not junction_route.is_empty(),"route contains a real street junction")
	if not junction_route.is_empty():
		# Start near the turn to exercise signals and lane handoff without a long drive.
		junction_route[0].start = maxf(float(junction_route[0].start),float(junction_route[0].end)-240)
		junction_route[2].end = minf(float(junction_route[2].end),float(junction_route[2].start)+160)
		var first: Dictionary = junction_route[0]
		cab.global_position = first.path.to_global(first.path.curve.sample_baked(first.start,true))
		cab.global_rotation = first.path.curve.sample_baked_with_rotation(first.start,true).get_rotation()+first.path.global_rotation
		player.global_position = cab.to_global(Vector2(0,45))
		player.is_control_disabled = false
		player.set_physics_process(false)
		cab.enter_vehicle(player)
		service._board()
		while cab.has_meta("vehicle_boarding"): await process_frame
		await physics_frame
		await physics_frame
		service.route = junction_route
		service.destination_name = "Depois do cruzamento"
		service.start_ride()
		began = Time.get_ticks_msec()
		while cab.taxi_passenger and Time.get_ticks_msec()-began<35000:
			await process_frame
		check(not cab.taxi_passenger,"NPC crosses a reserved junction and completes the trip")
		if cab.taxi_passenger:
			print("JUNCTION_STUCK leg=",service.leg_index," position=",cab.global_position," offset=",service.follow.progress," contract=",cab._last_lane_motion_contract)
			cab.force_exit_vehicle()
	player.set_physics_process(false)
	player.is_control_disabled = false
	player.global_position = cab.to_global(Vector2(0,45))
	cab.enter_vehicle(player)
	service._board()
	await create_timer(0.25).timeout
	cab.force_exit_vehicle()
	await process_frame
	check(not cab.taxi_passenger and not player.is_control_disabled and player.visible,"forced exit during boarding cleans up passenger state")
	player.set_physics_process(false)
	player.is_control_disabled = false
	player.global_position = cab.to_global(Vector2(0,45))
	cab.enter_vehicle(player)
	service._steal()
	check(cab.is_driven_by_player and not cab.taxi_passenger and not service.driver_available,"stealing gives driving control and removes taxi service")
	check(not cab.body_model.get_node("TaxiDriver").visible,"stolen taxi no longer renders NPC at wheel")
	check(get_nodes_in_group("pedestrian").any(func(node): return node is CarjackedDriver),"stealing ejects an NPC with existing reactions")
	cab.force_exit_vehicle()
	print("TAXI SERVICE FAILURES: ",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
