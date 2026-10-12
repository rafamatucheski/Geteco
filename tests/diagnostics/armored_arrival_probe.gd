extends SceneTree
## Production admission and loading: real bank geometry, crew and physical cars.
## Completed campaign/calendar are isolated fixture setup, not campaign coverage.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var world
var checks := 0
var failures: Array[String] = []
var folder := ""
var origin := "harbor_bank"
var security_level := 0
var prepared := false
func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("ARMORED_SESSION timeout"); finish(3))
	run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	print("ARMORED_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--desert" in OS.get_cmdline_user_args(): origin = "desert_bank"
	if "--maximum-security" in OS.get_cmdline_user_args(): security_level = SCHEDULE.MAX_SECURITY
	folder = FIXTURE.output_dir("armored-arrival-probe")
	var bank: Vector3 = PLACES.get_definition(origin).entry_position
	var point: Vector3 = bank+Vector3(4,.08,1)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var region := "desert" if origin == "desert_bank" else "harbor"
	snapshot.region_id = region
	snapshot.world.pedestrian = {"region":region,"position":[point.x,point.y,point.z]}
	snapshot.world.moon_day = 3 if region == "desert" else 1
	snapshot.world.time = (14.0 if region == "desert" else 9.0)/24.0
	if security_level > 0:
		# Persisted preparation seeds the real scheduler; it must create the event.
		snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":"","security_level":security_level,"event":{}}
	var event := SCHEDULE.initial(SCHEDULE.departure(1,9.0/24.0),security_level)
	event.phase = "finished"
	event.cargo_cycles = [2,2]
	snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":event.id,"security_level":security_level,"event":event}
	var path := FIXTURE.write_fixture(folder,"checkpoint.json",snapshot)
	if not check(not path.is_empty(),"isolated scheduled checkpoint accepted"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for frame in 6000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if not check(world.session != null and world.session.ready_for_play and not world.production.save_invalid,"real Main ready"): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled C# router active")
	var convoy = session.armored_transport
	world.production.region.set_focus(point)
	for frame in 3: await physics_frame
	if not check(session.position_clear(point),"observer begins on supported clear bank sidewalk"): finish(1); return
	world.player.teleport(point)
	print("ARMORED_SETUP ",JSON.stringify({"bank":str(PLACES.get_definition(origin).entry_position),"fixture":str(point),"cache":world.production._route_cache.keys()}))
	convoy.data = SCHEDULE.initial(SCHEDULE.departure(3,14.0/24.0))
	convoy.profile = SCHEDULE.security(0)
	convoy.last_event = convoy.data.id
	convoy.road = null
	if not convoy._prepare_route(): finish(1); return
	convoy.data.phase = "driving"
	convoy.data.cargo_cycles = [2,2]
	convoy.data.route_offset = convoy.road.get_baked_length()-120.0
	convoy._persist()
	print("ARRIVAL_ROAD ",convoy.road.sample_baked(convoy.road.get_baked_length(),true))
	var started := Time.get_ticks_msec()
	var last := 0
	var held_near_bank := false
	while Time.get_ticks_msec()-started < 180000:
		await physics_frame
		if convoy.data.phase == "driving":
			for driver in convoy.drivers:
				if driver.remaining < 100 and driver.vehicle.get_meta("armored_formation_wait",false): held_near_bank = true
		if convoy.data.phase == "unloading" and convoy.data.delivered == [true,true]: break
		if Time.get_ticks_msec()-last < 10000: continue
		last = Time.get_ticks_msec()
		var cars := []
		for driver in convoy.drivers:
			var car = driver.vehicle
			cars.append({"point":str(car.global_position),"speed":car.speed,"holding":driver.holding,"remaining":driver.remaining,"blocked":car.blocked,"junction":car.junction_wait,"formation":car.get_meta("armored_formation_wait",false)})
		print("ARRIVAL_TRACE ",JSON.stringify({"phase":convoy.data.phase,"cycles":convoy.data.cargo_cycles,"admission":convoy.admission_status,"cars":cars}))
	check(convoy.fleet.size()==4 and convoy.fleet.all(func(car): return car.global_position.z+car.half_length < 17),"arriving service parks every hull off the avenue")
	check(convoy.data.phase=="unloading" and convoy.data.delivered==[true,true],"both trucks physically unload at North Pier")
	check(not held_near_bank,"arriving cars clear the avenue without waiting there for the rear escort")
	check(convoy.fleet.all(func(car): return car.health == car.max_health),"arrival and unloading preserve undamaged vehicles")
	await photo("arrival")
	finish(0 if failures.is_empty() else 1)
func finish(code: int):
	print("ARRIVAL_RESULT ",JSON.stringify({"failures":failures,"folder":folder}))
	quit(code)
