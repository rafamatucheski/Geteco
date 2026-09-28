extends SceneTree
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	if not ok: failures.append(label); push_error(label)
func run():
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	check(session != null and session.ready_for_play,"Production session ready")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save,"User save isolated")
	check(await session.enter_place("port_boss_garage",false),"Enter port garage")
	if not failures.is_empty(): world.free(); quit(1); return
	for i in 15: await physics_frame
	var car = session.garage_rewards.cars.get("port_garage_stock_2")
	check(is_instance_valid(car),"Port stock vehicle materializes")
	if not is_instance_valid(car): world.free(); quit(1); return
	# Start seated; boarding has its own integration test. Keep actual vehicle
	# physics, garage processing, streaming and transfer admission enabled.
	world.driving.car = car
	world.driving.occupied = true
	car.controlled = true
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.player.hide()
	world.player.set_physics_process(false)
	car.place(session.room.to_global(Vector3(0,.08,6.5)),PI)
	car.speed = 4.0
	car.horizontal_velocity = Vector3(0,0,4)
	for i in 180: await physics_frame
	check(session.state.place_id.is_empty(),"Driving out transfers to surface without interaction")
	check(car.global_position.y > -.3,"Car remains supported after exit")
	var destination: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition("port_boss_garage").vehicle_return
	check(car.global_position.distance_to(destination)<6,"Exit returns beside exterior gate")
	check(world.driving.occupied and not world.camera.locked,"Driver and exterior camera retained")
	check(not session.is_transition_blocked() and not car.input_locked,"Controls released")
	world.free()
	await process_frame
	print("PORT_GARAGE_DRIVE_EXIT failures=",failures)
	quit(0 if failures.is_empty() else 1)
