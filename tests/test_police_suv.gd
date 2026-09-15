extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func _run() -> void:
	create_timer(60).timeout.connect(func(): printerr("POLICE_SUV_TIMEOUT"); quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var wanted := root.get_node("WantedManager")
	wanted.set_process(false)
	wanted.reset_crime()
	await physics_frame
	await physics_frame
	var pool := root.get_node("EmergencyPool")
	var cars: Array = pool._pool.police.filter(func(unit): return unit.police_variant != "motorcycle")
	check(cars.size() == 5 and pool._pool.police.size() == 7, "Fleet size and two motorcycle slots are preserved")
	check(cars.filter(func(unit): return unit.police_archetype == "police_suv").size() == 2, "Two SUVs alongside three more frequent sedans")
	var sedan = cars.filter(func(unit): return unit.police_archetype == "police_cruiser")[0]
	var suv = cars.filter(func(unit): return unit.police_archetype == "police_suv")[0]
	for unit in [sedan,suv]:
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		unit.activate()
		unit.set_physics_process(false)
		unit.position = Vector2.ZERO
	check(suv.body_model.vehicle_id == "police_suv", "Response builds the SUV body")
	check(suv.get_node("CollisionShape2D").shape.size.x > sedan.get_node("CollisionShape2D").shape.size.x, "SUV collision follows its larger body")
	check(suv.visual_3d.wheel_rig.pivots.size() == 4, "Four authored wheels use the steering rig")
	check(suv.visual_3d.doors.size() == 2, "Driver and passenger doors exist")
	for door in suv.visual_3d.doors.values():
		check(door.extracted_triangles > 0, "Door is extracted from the SUV body and glazing")
	suv.visual_3d.lightbar.update(true,0)
	check(suv.visual_3d.lightbar.lamps.size() == 2 and suv.visual_3d.lightbar.lamps[0].emission_enabled, "Red-blue lightbar keeps first phase")
	suv.visual_3d.lightbar.update(true,160)
	check(suv.visual_3d.lightbar.lamps[1].emission_enabled and not suv.visual_3d.lightbar.lamps[0].emission_enabled, "Lightbar alternates its second phase")
	var model_id: int = suv.body_model.get_instance_id()
	suv.configure_police_response(5,4,true)
	check(suv.police_variant == "tactical" and suv.body_model.vehicle_id == "police_suv", "Response tier changes crew without replacing SUV body")
	pool.return_vehicle(suv)
	suv.process_mode = Node.PROCESS_MODE_INHERIT
	suv.activate()
	suv.set_physics_process(false)
	suv.position = Vector2(200,100)
	check(suv.body_model.get_instance_id() == model_id, "Pooling reuses the prepared SUV geometry")
	var parking = load("res://world/harbor/HarborPatrolParking.gd").new()
	world.add_child(parking)
	check(parking.get_node("PatrolParked1").active_archetype_id == "police_cruiser" and parking.get_node("PatrolParked2").active_archetype_id == "police_suv", "Precinct has one sedan and one SUV in its two existing bays")
	var standby = load("res://world/shared/emergency/EmergencyStandbyPoint.gd").new()
	for i in 20:
		standby.standby_id = "suv_test_%d" % i
		if posmod(standby.standby_id.hash(),3) == 0: break
	world.add_child(standby)
	await process_frame
	var director = load("res://world/shared/emergency/EmergencyDepotDirector.gd").new()
	world.add_child(director)
	check(director._claim_standby("police","police_cruiser") == null and standby.available, "Sedan cannot consume a parked SUV")
	check(director._claim_standby("police","police_suv") == standby, "SUV dispatch claims a matching standby body")
	director.remove_from_group("emergency_depot_director")
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player.position = suv.position + Vector2(0,40)
	var collision_size: Vector2 = suv.get_node("CollisionShape2D").shape.size
	suv.enter_vehicle(player)
	var stolen: Node = null
	for vehicle in get_nodes_in_group("vehicle"):
		if vehicle.get("is_driven_by_player") == true: stolen = vehicle
	check(stolen != null and stolen.active_archetype_id == "police_suv", "Taking the response SUV creates a drivable SUV, not a sedan")
	if stolen:
		stolen.set_physics_process(false)
		check(stolen.is_police_vehicle and stolen.body_model.vehicle_id == "police_suv", "Stolen SUV retains police identity and geometry")
		check(stolen.collision.shape.size.is_equal_approx(collision_size), "Theft preserves the response collision footprint")
		check(stolen.lightbar_3d.lamps.size() == 2, "Stolen SUV retains its working lightbar")
		while stolen.has_meta("vehicle_boarding"): await process_frame
	await process_frame
	wanted.current_stars = 5
	# Reserve the other cars, forcing the pool to replace the stolen SUV slot.
	for unit in pool._pool.police:
		if is_instance_valid(unit): unit.show()
	pool.get_vehicle("police")
	await process_frame
	var replacement = pool.get_vehicle("police")
	check(replacement != null and replacement.police_archetype == "police_suv" and replacement.body_model.vehicle_id == "police_suv", "Replacing a stolen response unit preserves its SUV slot")
	for unit in pool._pool.police:
		if is_instance_valid(unit): pool.return_vehicle(unit)
	world.queue_free()
	await process_frame
	await process_frame
	print("POLICE_SUV_RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
