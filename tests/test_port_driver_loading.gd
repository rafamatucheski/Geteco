extends "res://tests/test_video_phase4_port_freight.gd"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	check(session != null and session.ready_for_play and world.production.no_save,"isolated .NET Main ready")
	if not failures.is_empty(): await finish(); return
	world.gameplay.dispatch_owned = true
	world.gameplay.emergency.dispatch_owned = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.weather.time_of_day = .4
	session.weather.set_process(false)
	var ops = session.urban_operations
	var cargo = ops.cargo_handling
	var freight = ops.freight
	ops.security.authorized_visit = true
	await place_actor(Vector3(298,.1,219))
	var bay := 1
	for _i in 600:
		await physics_frame
		if is_instance_valid(cargo.work_trucks[bay].truck): break
	var entry: Dictionary = cargo.work_trucks[bay]
	var truck = entry.truck
	check(is_instance_valid(truck),"existing port truck spawned")
	if not failures.is_empty(): await finish(); return
	cargo._reset_truck_load(bay)
	entry.phase = "interrupted"
	truck.traffic = false
	truck.speed = 0
	truck.velocity = Vector3.ZERO
	truck.brake_input = true
	truck.global_position = entry.stop + Vector3.UP*.08
	await place_actor(truck.driver_door_anchor(-1) - truck.global_basis.x*.3)
	check(world.driving.interact(true),"borrow or steal truck through real driver door")
	check(await wait_transition(),"driver boarding completed")
	await frames(20)
	check(entry.phase == "interrupted" and not entry.loaded,"boarding reproduces original interrupted empty truck")
	session.state.intro.set_location("harbor_garage")
	for target in ["maciota","mechanic","workbench","maciota"]: session.state.intro.interact(target)
	session.state.intro.set_location("harbor_street")
	check(session.state.intro.stage == "complete","complete real intro before optional freight")
	var crimes: float = world.gameplay.crime_points
	world.gameplay.crime_points = 0
	world.gameplay.stars = 0
	print("DRIVER_OFFER available=",freight._available()," parked=",freight.parked_for_loading(truck,bay)," visit=",ops.security.authorized_visit," intro=",session.state.intro.stage," campaign=",session.state.campaign.active_id," position=",truck.global_position," stop=",entry.stop," floor=",truck.is_on_floor()," speed=",truck.speed," transition=",world.driving.is_body_transition_active()," nearest=",session.nearest())
	check(session.nearest().get("target") == "south_port_freight_load_1","E prompt offered inside parked empty truck")
	if not failures.is_empty(): await finish(); return
	truck.speed = 1
	check(freight.nearest_action().is_empty(),"moving truck cannot request loading")
	truck.speed = 0
	check(session.interact() and freight.active_bay == bay,"normal E interaction begins crane loading")
	check(not session.save_game(),"incomplete loading cannot publish unsafe save")
	var loading: Dictionary = JSON.parse_string(JSON.stringify(freight.snapshot()))
	check(FREIGHT.validate_snapshot(loading) and not loading.cargo_loaded,"loading snapshot preserves absence of cargo")
	check(freight.restore_snapshot(loading),"loading snapshot accepted")
	await frames(30)
	check(not entry.loaded and entry.phase == "loading","reload never conjures a loaded container")
	var initial: Vector3 = truck.global_position
	truck.global_position += Vector3(4,0,0)
	await frames(15)
	check(not entry.loaded and is_zero_approx(float(cargo.cranes[bay].clock)),"leaving bay restarts loading without remote attachment")
	truck.global_position = initial
	truck.speed = 0
	truck.velocity = Vector3.ZERO
	for _i in 1800:
		await physics_frame
		if entry.loaded: break
	check(entry.loaded and entry.phase == "freight" and cargo.cranes[bay].visual.get_parent() == truck,"real crane cycle attaches cargo to occupied truck")
	check(world.gameplay.crime_points == 0,"loading does not add or erase crimes")
	print("DRIVER_THEFT initial_crime_points=",crimes)
	if not failures.is_empty(): await finish(); return
	var depot: Vector3 = freight.depot_position(bay)
	await lifecycle_fixture(truck,depot)
	check(not freight.perform("south_port_freight_deliver"),"delivery requires disembarking")
	check(world.driving.leave(),"leave truck at destination")
	check(await wait_transition(),"physical destination exit completes")
	await frames(20)
	check(session.nearest().get("target") == "south_port_freight_deliver","normal handback prompt appears at company")
	var balance: int = session.state.economy.balance
	check(session.interact() and session.state.economy.balance == balance+300,"driver-loaded shipment pays R$300")
	check(not freight.perform("south_port_freight_deliver") and session.state.economy.balance == balance+300,"shipment cannot pay twice")
	await finish()
