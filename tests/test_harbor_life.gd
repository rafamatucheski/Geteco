extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("CHECK ",label,": ",value)
	if not value: failures.append(label)
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.player.teleport(Vector3(223,.3,203))
	world.production.region.set_focus(world.player.position)
	var terminal = world.session.urban_operations.passenger_terminal
	for i in 15: await physics_frame
	terminal.refresh_context()
	check(terminal.active,"terminal active near public access")
	for point in [terminal.ARRIVAL,Vector3(233,.44,191),Vector3(233,.2,194),Vector3(223,.2,193.5)]:
		var clear: bool = world.session.position_clear(point)
		check(clear,"free supported point "+str(point))
		if not clear:
			var query := PhysicsShapeQueryParameters3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius=.32; capsule.height=1.7
			query.shape=capsule; query.collision_mask=7; query.transform.origin=point+Vector3.UP*.9
			for hit in world.get_world_3d().direct_space_state.intersect_shape(query): print("BLOCKER ",hit.collider.get_path())
	terminal._ensure_angler(0)
	check(is_instance_valid(terminal.anglers[0]),"fisher present")
	if is_instance_valid(terminal.anglers[0]):
		var fisher=terminal.anglers[0]
		var before: float=fisher.fishing_clock
		for i in 20: await physics_frame
		check(fisher.is_on_floor(),"fisher physically supported on jetty")
		check(fisher.fishing_clock!=before,"fisher animates own cycle")
		fisher.receive_damage(1000)
		check(fisher.dead and not is_instance_valid(terminal.anglers[0]),"fisher dies and releases post")
		check(terminal.cooldown[0]>179,"fisher return waits three minutes")
	terminal.set_process(false)
	terminal._spawn_passenger()
	check(not terminal.passengers.is_empty(),"passenger spawns aboard")
	if not terminal.passengers.is_empty():
		var passenger=terminal.passengers[0]
		# 75 m including both 32-degree stair ramps; uphill slide speed is below
		# the 1.55 m/s flat pace. Allow 75 s for the complete physical route.
		for i in 4500:
			await physics_frame
			if passenger.point_index>=passenger.points.size(): break
		print("PASSENGER ",passenger.global_position," waypoint=",passenger.point_index)
		for c in passenger.get_slide_collision_count(): print("ROUTE_CONTACT ",passenger.get_slide_collision(c).get_collider().get_path())
		check(passenger.point_index>=passenger.points.size(),"passenger walks gangway bridge and city connection")
		check(not passenger.dead,"passenger survives full public route")
	world.player.teleport(Vector3(232.7,.2,200))
	await physics_frame
	check(world.player.test_move(world.player.global_transform,Vector3(2,0,0)),"bench footprint physically blocks player")
	check(not world.session.urban_operations.security._inside_security_zone(Vector3(237,.2,202)),"passenger quay stays outside private cargo security")
	world.camera.set_process(false)
	world.camera.position=Vector3(230,25,215)
	world.camera.look_at(Vector3(233,0,191))
	terminal.cooldown[0]=0
	terminal._ensure_angler(0)
	check(not is_instance_valid(terminal.anglers[0]),"fisher does not reappear in front of camera")
	world.camera.position+=Vector3(0,0,200)
	terminal._ensure_angler(0)
	check(is_instance_valid(terminal.anglers[0]) and not terminal.anglers[0].dead,"fisher returns to fishing post offscreen")
	world.player.teleport(terminal.ARRIVAL)
	terminal.clock=terminal.DWELL
	terminal._tick_ferry(.1)
	check(terminal.phase=="docked","ferry waits for player still aboard")
	world.player.teleport(Vector3(254,.1,211))
	terminal._tick_ferry(.1)
	check(terminal.phase=="departing" and terminal.gate_closed,"ferry departs and closes passenger gate")
	terminal._tick_ferry(terminal.TRAVEL*.5)
	check(terminal.ferry.position.distance_to(terminal.BERTH)>30,"boat physically leaves berth before disappearing")
	terminal._tick_ferry(terminal.TRAVEL)
	check(terminal.phase=="away" and not terminal.ferry.visible,"departed ferry is removed offscreen")
	terminal._tick_ferry(terminal.AWAY)
	check(terminal.phase=="approaching","ferry returns after interval")
	terminal._tick_ferry(terminal.TRAVEL)
	check(terminal.phase=="docked" and not terminal.gate_closed and terminal.spawned==0,"next landing opens gate with a fresh group")
	check(terminal.passengers.size()<=12,"passenger population remains bounded")
	var saved: Dictionary=terminal.snapshot()
	check(terminal.validate_snapshot(saved) and terminal.restore_snapshot(saved),"terminal lifecycle roundtrip")
	var bad: Dictionary=saved.duplicate(true)
	bad.cooldown[0]=NAN
	check(not terminal.validate_snapshot(bad),"invalid respawn timer rejected")
	world.free()
	await process_frame
	print("HARBOR_LIFE failures=",failures)
	quit(0 if failures.is_empty() else 1)
