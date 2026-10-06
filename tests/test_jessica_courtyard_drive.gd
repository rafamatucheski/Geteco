extends "res://tests/test_jessica_foundry_route.gd"
const COURT_PATH := preload("res://tests/fixtures/JessicaCourtyardFootpath.gd")
const CABIN := preload("res://gameplay/VehicleInterior.gd")
## The real Main courtyard and M8, driven by the production Jetta controller.
## One pre-test placement initializes Quay before both access arcs. There are
## no position/velocity writes during driving, no bank/receipt/wanted fixtures.

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): push_error("Courtyard drive requires --no-save"); quit(2); return
	var folder: String = "res://evidence/jessica-courtyard-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("jessica_diagnostics",true)
	var save_path: String = folder.path_join("fixture-save.json")
	check(fixture(save_path),"isolated consistent checkpoint")
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and is_instance_valid(world.session.jessica.car): break
	check(world.session != null and world.session.ready_for_play and is_instance_valid(world.session.jessica.car),"Main/.NET and the real personal Jetta are ready")
	if not failures.is_empty(): await finish(); return
	var runtime = world.session.jessica
	var plan: Dictionary = runtime._plan_getaway()
	check(plan.get("ok",false) and plan.get("native",false),"production Foundry plan uses compiled native search")
	if not plan.get("ok",false): await finish(); return
	var car: CharacterBody3D = runtime.car
	var road: Curve3D = plan.curve
	var region = world.session.controller.regions.harbor
	var access: float = road.get_meta("getaway_access_offset")
	var start: Vector3 = road.sample_baked(maxf(0,access-8),true)
	var ahead: Vector3 = road.sample_baked(maxf(0,access-7),true)
	var start_yaw: float = atan2(-(ahead-start).x,-(ahead-start).z)
	for offset: float in [access-8,access,access+10,road.get_baked_length()]:
		var point: Vector3 = road.sample_baked(clampf(offset,0,road.get_baked_length()),true)
		region._ensure_chunk(Vector2i(floori(point.x/64),floori(point.z/64)))
	for i in 3: await physics_frame
	var m8 = preload("res://runtime/ArrivalCar.gd").new()
	m8.position = world.maciota_place.tour_parking+Vector3.UP*.02
	world.add_child(m8)
	m8.set_physics_process(false)
	check(not region.buildings.any(func(building): return building.id == "FreightDepot"),"removed pharmacy building does not reserve the garage frontage")
	var depot_present := false
	for building in region.find_children("*","Node3D",true,false):
		if building is UrbanBuildingBase and building.building_id == "FreightDepot": depot_present = true
	check(not depot_present,"removed pharmacy model and attached collision stay absent from the real courtyard")
	check(world.session.controller.vehicle_position_clear(car,start+Vector3.UP*.12,start_yaw),"Quay start is physically admitted")
	if not failures.is_empty(): await finish(); return
	# This is the explicit initialization before the measured physical drive.
	car.call("place",start+Vector3.UP*.12,start_yaw)
	car.set("route",road)
	runtime.route = road
	runtime.driver.setup(car,road)
	runtime.driver.placement_validator = func(point: Vector3,yaw: float) -> bool: return world.session.controller.vehicle_position_clear(car,point,yaw)
	runtime.set_physics_process(false)
	var player = world.player
	runtime._saved_player = {"layer":player.collision_layer,"mask":player.collision_mask,"physics":player.is_physics_processing(),"visible":player.visible,"locked":player.input_locked,
		"visual_transform":player.visual.transform,"body_basis":player.global_basis,"pose":player._capture_pose() if is_instance_valid(player.skeleton) else []}
	world.player.input_locked = true
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	if is_instance_valid(runtime.actor):
		runtime.actor.hide()
		runtime.actor.collision_layer = 0
		runtime.actor.collision_mask = 0
	runtime._create_driver_model()
	runtime.riding = true
	world.camera.target = car
	for i in 12: await physics_frame
	check(car.is_on_floor(),"initialized Quay car settles on the real floor before driving")
	var health: float = car.get("health")
	var samples: Array[Dictionary] = []
	var grounded := true
	var contacts_free := true
	var travelled := 0.0
	var before: Vector3 = car.global_position
	for i in 2100:
		runtime.driver.tick(1.0/60.0,false)
		await physics_frame
		CABIN.follow(world.player,car,1.0/60.0)
		grounded = grounded and car.is_on_floor()
		travelled += Vector2(car.global_position.x-before.x,car.global_position.z-before.z).length()
		before = car.global_position
		for index in car.get_slide_collision_count():
			var collision: KinematicCollision3D = car.get_slide_collision(index)
			if absf(collision.get_normal().y) < .7: contacts_free = false
		if i % 15 == 0: samples.append({"frame":i,"position":str(car.global_position),"yaw":car.rotation.y,"speed":car.get("speed"),"inside":runtime._inside_courtyard(),"driver":runtime.driver.debug_snapshot()})
		if runtime._route_finished(): break
	check(runtime._route_finished() and runtime._inside_courtyard(),"stopped whole hull is inside the actual courtyard")
	check(absf(angle_difference(car.rotation.y,0)) <= .2,"physical final parking faces north within the bay")
	check(grounded and contacts_free and float(car.get("health")) >= health,"real access remains supported and touches no depot/fence/M8")
	check(travelled > 25 and car.collision_mask == 7,"both arcs are completed by ordinary physical steering with collisions active")
	var before_exit: Vector3 = car.global_position
	check(is_instance_valid(runtime.actor) and runtime._leave(false),"ordinary passenger/driver dismount uses validated production exits")
	var stability: Array[Dictionary] = []
	for i in 60:
		await physics_frame
		stability.append({"frame":i,"position":str(car.global_position),"player":str(world.player.global_position),"inside":runtime._inside_courtyard()})
	check(car.global_position.distance_to(before_exit) < .05 and runtime._inside_courtyard(),"collidable parked car remains inside courtyard for60physicsframes after dismount")
	check(world.player.is_physics_processing() and world.player.collision_layer == 2 and not world.player.seated,"Dante restores normal standing collision and physics at the exterior point")
	var walkway: PackedVector3Array = COURT_PATH.path(world,car,runtime.actor) if is_instance_valid(runtime.actor) else PackedVector3Array()
	check(not walkway.is_empty(),"south passage is independently admitted with both parked cars")
	world.player.controlled_automatically = true
	world.player.speed = 3.0
	var reachable := not walkway.is_empty()
	for point: Vector3 in walkway:
		var reached := false
		for i in 600:
			var toward: Vector3 = point-world.player.global_position
			toward.y = 0
			if toward.length() < .16: reached = true; break
			world.player.automatic_direction = toward.normalized()
			await physics_frame
		reachable = reachable and reached
	world.player.automatic_direction = Vector3.ZERO
	check(reachable and runtime._contact_valid(),"ordinary physical walking through the south corridor reaches Jessica")
	check(reachable and runtime.perform("talk") and world.session.dialogue_open,"post-exit contact opens actual conversation")
	FileAccess.open(folder.path_join("drive.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples,"stability":stability,
		"exit":runtime.last_exit_diagnostic,"travelled":travelled,"final":runtime.driver.debug_snapshot()},"\t"))
	print("JESSICA_COURTYARD_STATE ",JSON.stringify({"position":str(car.global_position),"yaw":car.rotation.y,"inside":runtime._inside_courtyard(),"travelled":travelled,"driver":runtime.driver.debug_snapshot()}))
	car.call("_release_junction")
	await finish()
