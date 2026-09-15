extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ")+description)
	if not ok: failures.append(description)
func run() -> void:
	seed(510)
	create_timer(160,true,false,true).timeout.connect(func(): print("FAIL timeout"); quit(2))
	var script := preload("res://world/harbor/urban_transit/UrbanTransit.gd")
	for item in [[0,true],[1.999,true],[2,false],[3,false],[4.999,false],[5,true],[23.999,true],[24,true]]:
		check(script.is_service_hour(item[0]) == item[1],"operating boundary %s h"%item[0])
	for flag in [&"harbor_arrival_seen",&"harbor_arrival_call_complete",&"harbor_maciota_met",&"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag,true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 30: await process_frame
	while not current_scene.gameplay_ready: await process_frame
	var system: Node2D = current_scene.get_node("UrbanTransit")
	while not system.ready_for_service: await process_frame
	current_scene.get_node("CobraCampaign").set_process(false)
	system.clock.is_dynamic_time = false
	system.clock.time_of_day = 12.0/24
	check(system.stops.size()==6,"six urban stops in production world")
	check(system.buses.size()==2 and system.passengers.size()==24,"bounded fleet and living commuter pool")
	check(current_scene.get_node_or_null("ArrivalStop") != system,"urban service separate from coach terminal")
	for bus in system.buses:
		check(bus.sections.size()==1,"articulated bus has two physical bodies")
		check(bus.sections[0].get_collision_exceptions().has(bus),"coupled sections ignore own collisions")
	await physics_frame
	for bus in system.buses:
		for body in [bus]+bus.sections:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = body.collision.shape
			query.transform = body.global_transform
			query.collision_mask = 2
			query.exclude = [bus.get_rid(),bus.sections[0].get_rid()]
			check(body.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(),"initial convoy is clear of ambient car spawns")
	# Isolate random cars only for the deterministic full-loop test.
	current_scene.get_node("Life")._traffic_target = 0
	for car in get_nodes_in_group("ambient_traffic"):
		if not car.is_in_group("urban_bus") and not car.is_in_group("urban_bus_section") and not car.is_in_group("harbor_transit_bus"):
			car.queue_free()
	await physics_frame
	Engine.time_scale = 3.0
	var began := Time.get_ticks_msec()
	var max_articulation := 0.0
	var visited := {}
	var last_report := began
	while Time.get_ticks_msec()-began<95000:
		await physics_frame
		for bus in system.buses:
			visited[bus.current_stop] = true
			max_articulation = maxf(max_articulation,absf(angle_difference(bus.global_rotation,bus.sections[0].global_rotation)))
		if Time.get_ticks_msec()-last_report>10000:
			last_report = Time.get_ticks_msec()
			for bus in system.buses:
				print("PROGRESS stop=",bus.current_stop," next=",bus.next_stop," at=",bus.global_position," dwell=",bus.dwelling," boarded=",system.boarded," alighted=",system.alighted," sections_clear=",bus._sections_clear()," contract=",bus._last_lane_motion_contract)
				var contact := KinematicCollision2D.new()
				if bus.test_move(bus.global_transform,bus.global_transform.x*4,contact): print("HEAD_BLOCKER ",contact.get_collider().get_path())
		if visited.size()==6 and system.boarded>=6 and system.alighted>=4 and system.buses.any(func(bus): return bus.visits>=6): break
	print("URBAN_STATE boarded=",system.boarded," alighted=",system.alighted," departures=",system.departures," visited=",visited," articulation=",max_articulation)
	for bus in system.buses: print("BUS ",bus.name," stop=",bus.current_stop," next=",bus.next_stop," position=",bus.global_position," distance=",bus.distance_travelled," dwell=",bus.dwelling," obstruction=",bus.block_wait_timer)
	check(system.boarded>=6,"NPCs actually walk into buses")
	check(system.alighted>=4,"NPCs alight at their destinations")
	check(visited.size()==6,"service reaches all six city stops")
	check(system.buses.any(func(bus): return bus.visits>=6),"an articulated bus completes a full circuit")
	check(max_articulation>0.25,"trailers articulate through real street turns")
	check(system.passengers.any(func(person): return person.trips>0 and person.transit_state != "onboard"),"arrivals continue a sidewalk routine")
	system.clock.time_of_day = 2.0/24
	system._update_schedule()
	var before_board: int = system.boarded
	var before_depart: int = system.departures
	await create_timer(12).timeout
	check(not system.operating and system.boarded == before_board,"02:00 stops new boarding")
	check(system.departures == before_depart,"no passenger departures during closure")
	var closure_started := Time.get_ticks_msec()
	while not system.buses.all(func(bus): return bus.suspended) and Time.get_ticks_msec()-closure_started<30000:
		await physics_frame
	check(system.buses.all(func(bus): return bus.suspended and bus.onboard.is_empty()),"overnight fleet stops safely and unloads everyone")
	system.clock.time_of_day = 4.999/24
	system._update_schedule()
	check(not system.operating,"service remains closed immediately before 05:00")
	system.clock.time_of_day = 5.0/24
	system._update_schedule()
	check(system.operating,"05:00 reopens the route")
	await create_timer(25).timeout
	check(system.buses.any(func(bus): return not bus.suspended),"fleet resumes after dawn")
	Engine.time_scale = 1
	print("URBAN TRANSIT FAILURES: ",failures)
	quit(0 if failures.is_empty() else 1)
