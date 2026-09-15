extends SceneTree
const PARKING := preload("res://world/harbor/HarborMedicalParking.gd")
const OUTPUT := "D:/geteco/artifacts/hospital-parking-0911"
var failures: Array[String] = []
var passing_traffic: Array[RID] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func clear_shape(world: Node2D, point: Vector2, angle: float, size: Vector2, exclude: Array[RID] = []) -> bool:
	var shape := RectangleShape2D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(angle, point)
	query.collision_mask = 3
	query.exclude = exclude + passing_traffic
	var hits := world.get_world_2d().direct_space_state.intersect_shape(query)
	if not hits.is_empty():
		print("PARKING_BLOCK point=", point, " hit=", hits[0].collider.get_path())
	return hits.is_empty()

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(label+".png"))

func run() -> void:
	create_timer(180).timeout.connect(func(): print("PARKING TIMEOUT"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1440, 960)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	for flag in [&"harbor_arrival_seen", &"harbor_arrival_call_complete", &"harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(flag, true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	paused = false
	root.get_node("WantedManager").set_process(false)
	world.get_node("Player").global_position = Vector2(1790, 1720)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(1900, 1510)
	camera.zoom = Vector2.ONE * 2.0
	camera.make_current()
	world.weather.time_of_day = .45
	world.weather.weather_state = 0
	world.weather.set_rain_intensity(0)
	world.weather._update_lighting()
	for i in 15: await physics_frame
	# Geometry checks concern the yard; live departures below still yield to traffic.
	for actor in get_nodes_in_group("ambient_traffic"):
		if actor is CollisionObject2D: passing_traffic.append(actor.get_rid())
	var district: Node2D = world.get_node("District")
	var hospital = district.get_node("Clinic")
	check(world.get_node("HospitalSpawn").global_position.is_equal_approx(district.get_node("ClinicAccess").global_position), "Hospital respawn stays at the relocated public reception")
	var director = get_first_node_in_group("emergency_depot_director")
	check(hospital.get_ambulance_stop_position().is_equal_approx(district.get_node("ClinicVehicleAccess").global_position), "Admission and dispatch use the same recessed bay")
	check(district.get_spatial_audit().is_empty(), "Repositioned buildings and pedestrian accesses do not overlap: "+str(district.get_spatial_audit()))
	for point in [PARKING.AMBULANCE_STOP, PARKING.CORONER_STOP, PARKING.RESERVE_STOP]:
		check(point.x+50 < PARKING.ROAD_EDGE-100, "Whole parked vehicle stays more than 100px off the road at "+str(point))
		check(clear_shape(world, point, 0, Vector2(100,46)), "Parking envelope clears physical buildings and islands at "+str(point))
	var targets: Array[Node2D] = []
	var units: Array[Node2D] = []
	for service in ["ambulance", "coroner"]:
		var target := Node2D.new()
		world.add_child(target)
		target.position = Vector2(2220, 2020 if service == "ambulance" else 1850)
		targets.append(target)
		var unit: Node2D = director._dispatch_unbatched(service, target, false)
		check(is_instance_valid(unit), service+" dispatches from the authored off-street bay")
		if unit:
			unit.set_physics_process(false)
			units.append(unit)
	await physics_frame
	var aisle_clear := true
	for y in range(1430, 1671, 4):
		aisle_clear = aisle_clear and clear_shape(world, Vector2(2090,y), PI*.5, Vector2(100,46))
	check(aisle_clear, "Full vehicle traverses aisle with ambulance and coroner both parked")
	for unit in units:
		var clear := true
		var gate: Vector2 = unit.get_meta("depot_road_gate")
		for step in 80:
			clear = clear and clear_shape(world, unit.position.lerp(gate, step/79.0), 0, Vector2(100,46), [unit.get_rid()])
		check(clear, "Entire departure sweep clears other parked unit and hospital for "+str(unit.type))
	for i in 15: await physics_frame
	await shot("patio-com-servicos")
	for unit in units: unit.set_physics_process(true)
	var departed := {}
	for tick in 1200:
		await physics_frame
		for unit in units:
			if unit.visible and unit.global_position.x > 2150 and unit.global_position.x < 2290:
				departed[unit.get_instance_id()] = true
		if tick % 180 == 0:
			for unit in units: print("YARD_MOTION type=",unit.type," position=",unit.position," visible=",unit.visible," speed=",unit.current_speed)
		if departed.size() == units.size(): break
	check(units.size() == 2 and departed.size() == 2, "Ambulance and coroner both leave the lot in live physics")
	for unit in units:
		print("DEPARTURE_UNIT type=",unit.type," position=",unit.position," gate=",unit.get_meta("depot_road_gate",Vector2.ZERO)," visible=",unit.visible," target=",unit.target," pending=",unit.get_meta("depot_departure_pending",false))
	await shot("patio-saida")
	print("HOSPITAL_PARKING failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
