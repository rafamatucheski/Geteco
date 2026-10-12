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
	folder = FIXTURE.output_dir("armored-session-"+origin)
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
	# Bank staging may shift along the street to leave persistent/player cars intact.
	# Bound service by its actual two round trips at the authored 1.35m/s walk pace.
	var deadline := Time.get_ticks_msec()+(140000 if origin == "desert_bank" else 90000)
	var observed_loading := false
	var observed_boarding := false
	var last_log := 0
	var initial_positions: Array = []
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if not convoy.data.is_empty() and convoy.fleet.size() == 4:
			if initial_positions.is_empty():
				for car in convoy.fleet: initial_positions.append(car.global_position)
				if origin == "harbor_bank":
					check(convoy.fleet.all(func(car): return car.global_position.z+car.half_length < 17.0),"all four service hulls leave the avenue and frontage clear")
				var longest_trip := 0.0
				for index in 2:
					var trip: Vector3 = convoy.fleet[index].door_point()-(bank+Vector3(float(index)-.5,.08,1.0))
					# Carriers use the frontage then a perpendicular road crossing.
					longest_trip = maxf(longest_trip,absf(trip.x)+absf(trip.z))
				deadline = Time.get_ticks_msec()+int((4.0*longest_trip/1.35+35.0)*1000.0)
				await photo("loading")
			observed_loading = observed_loading or convoy.data.phase == "loading"
			observed_boarding = observed_boarding or convoy.data.phase == "boarding"
			if convoy.data.phase == "driving": break
		if Time.get_ticks_msec()-last_log > 10000:
			last_log = Time.get_ticks_msec()
			var crew: Array = []
			for guard in convoy.guards:
				if is_instance_valid(guard): crew.append({"slot":guard.slot,"point":str(guard.global_position),"target":str(guard.patrol_target),"health":guard.health})
			print("ARMORED_TRACE ",JSON.stringify({"phase":convoy.data.get("phase","none"),"fleet":convoy.fleet.size(),"crew":crew,"cycles":convoy.data.get("cargo_cycles",[]),"elapsed":convoy.data.get("elapsed",0),"player":str(world.player.global_position),"blocked":session.is_transition_blocked(),"road":convoy.road != null}))
	await photo("service-end")
	check(observed_loading,"scheduled convoy admits exactly four physical vehicles at "+origin)
	check(observed_boarding,"cargo carriers finish physical bank trips before boarding")
	check(not convoy.data.is_empty() and convoy.data.phase == "driving","crew physically returns and convoy departs")
	check(not convoy.data.is_empty() and convoy.data.origin == origin,"scheduled origin matches existing bank")
	var expected := SCHEDULE.security(security_level)
	check(convoy.data.get("security_level",-1) == security_level and convoy.data.get("guards",[]).size() == int(expected.crew_count),"entire configured crew physically admitted and boarded")
	check(convoy.data.get("guards",[]).all(func(guard): return float(guard.health) == float(expected.guard_health)),"legal loading preserves every guard's health")
	check(not convoy.data.is_empty() and not convoy.data.hostile and world.gameplay.stars == 0,"observing legal service does not trigger police")
	check(SCHEDULE.valid_saved(session.state.world_state.get(SCHEDULE.KEY,{})),"live service snapshot obeys persistent contract")
	check(convoy.fleet.all(func(car): return car.health == car.max_health),"legal parking and loading cause no vehicle damage")
	if not initial_positions.is_empty() and convoy.fleet.size() == 4:
		var moved := 0
		# A legal red signal held the rear pair for >15s in the production trace.
		# Observe two signal cycles instead of demanding all cars move within 8s.
		var movement_deadline := Time.get_ticks_msec()+45000
		while Time.get_ticks_msec() < movement_deadline and moved < 4:
			await physics_frame
			moved = 0
			for index in mini(4,convoy.fleet.size()):
				if is_instance_valid(convoy.fleet[index]) and convoy.fleet[index].global_position.distance_to(initial_positions[index]) > 2: moved += 1
		check(moved == 4,"all four vehicles move under shared physical driver")
		await photo("departure")
	prepared = true
	finish(0 if failures.is_empty() else 1)
func finish(code: int) -> void:
	print("ARMORED_SESSION_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"origin":origin,"security_level":security_level,"evidence":folder}))
	if is_instance_valid(world): world.queue_free()
	quit(code)
