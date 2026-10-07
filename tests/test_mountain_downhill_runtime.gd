extends SceneTree
## Real Main/Vehicle/.NET integration. --no-save is mandatory. --drive adds
## a complete physical race, with test input supplied through the new pilot;
## it never places vehicles or changes checkpoint progress after the start.
const DRIVER := preload("res://activities/mountain_downhill/MountainDownhillDriver.gd")
var world
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(330).timeout.connect(func(): push_error("MOUNTAIN_DOWNHILL bounded runtime timeout"); quit(3))
	run.call_deferred()

func frames(count: int) -> void:
	for i in count: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	print("MOUNTAIN_DOWNHILL ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-save; player saves must remain untouched.")
		quit(2)
		return
	seed(5102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"real Main .NET session ready")
	if not failures.is_empty(): finish(); return
	var session = world.session
	check(session.controller.no_save,"save protection actually enabled")
	# Fixture only: completed introductory delivery, before any race begins.
	var intro: Dictionary = session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(session.state.intro.restore_snapshot(intro),"completed-intro fixture accepted")
	var coordinator := get_first_node_in_group("mountain_activities")
	check(is_instance_valid(coordinator),"production installs MountainActivities coordinator")
	if not is_instance_valid(coordinator): finish(); return
	var race = coordinator.components.get("mountain_downhill") if coordinator!=null else null
	check(is_instance_valid(race),"production coordinator installs downhill controller")
	if not is_instance_valid(race): finish(); return
	var start: Vector3 = race.course.start_position()
	var right: Vector3 = race.course.direction(10.0).cross(Vector3.UP).normalized()
	check(world.production.travel("mountain",start+right*3.4),"actual region travel to summit admitted")
	for i in 600:
		await physics_frame
		if not world.production.travel_busy and session.ready_for_play: break
	check(session.state.region_id=="mountain","summit destination has supported ground")
	if not failures.is_empty(): finish(); return
	await frames(180)
	var pose: Transform3D = race.course.grid(6)
	var car = world.production.spawn_vehicle("sport_coupe",pose.origin,pose.basis.get_euler().y)
	check(is_instance_valid(car),"sports car spawned over real road support")
	if not is_instance_valid(car): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	await frames(4)
	check(world.driving.interact(),"ordinary door interaction boards race car")
	await frames(200)
	check(world.driving.occupied and world.driving.car==car,"player occupies correct physical car")
	if not failures.is_empty(): finish(); return
	session.weather.time_of_day = .5
	check(not race.perform("start") and not race.active,"daylight start rejected without changing clock")
	check(is_equal_approx(float(session.weather.time_of_day),.5),"start does not silently set night")
	session.weather.time_of_day = .9
	var original: Transform3D = car.global_transform
	var obstruction := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8,2.0,5.6)
	shape.shape = box
	obstruction.add_child(shape)
	obstruction.transform = race.course.grid(1)
	obstruction.position.y += 1.0
	world.add_child(obstruction)
	await frames(3)
	check(not race.perform("start"),"occupied second grid slot rejects transactional start")
	await frames(3)
	check(not race.active and race.racers.is_empty() and not car.input_locked,"partial spawn rolls back rivals and releases controls")
	check(car.global_transform.origin.distance_to(original.origin)<.1,"failed start does not teleport player")
	obstruction.queue_free()
	await frames(3)
	check(race.perform("start") and race.active,"night start builds actual seven-car grid")
	if not race.active: finish(); return
	check(race.racers.size()==7 and race.racers.filter(func(e): return not e.player).size()==6,"exactly six competitive rivals plus Dante")
	check(not race.save_block_reason().is_empty(),"active attempt blocks saving")
	for entry in race.racers:
		check(entry.car.collision_layer!=0 and entry.car.collision_mask!=0,"physical collision retained: "+str(entry.name))
	var before_menu: float = race.countdown
	session._menu("Pausa da prova")
	await frames(30)
	check(race.active and is_equal_approx(float(race.countdown),before_menu),"modal pauses countdown without cancelling race")
	check(car.input_locked and race.racers.all(func(e): return absf(float(e.car.speed))<.01 and is_zero_approx(float(e.car.steer_input))),"modal keeps player locked and all six rivals stopped without residual steering")
	session.close_menu()
	await frames(200)
	check(not car.input_locked and race.countdown==0,"countdown restores player controls")
	if "--drive" in OS.get_cmdline_user_args():
		await drive_race(race,car)
	else:
		var elapsed_before: float = race.racers[6].run.elapsed
		session._menu("Pausa após a largada")
		await frames(30)
		check(race.active and is_equal_approx(float(race.racers[6].run.elapsed),elapsed_before),"modal during live race pauses time without false-start failure")
		session.close_menu()
		var rivals: Array = race.racers.duplicate()
		race.cancel_attempt()
		await frames(3)
		check(not race.active and race.racers.is_empty() and not car.input_locked,"cancel clears activity and input ownership")
		check(rivals.filter(func(e): return not e.player and is_instance_valid(e.car)).is_empty(),"cancel removes every race-owned rival")
		check(race.snapshot().finishes==0 and not race.snapshot().reward_paid,"cancel cannot claim race completion or payment")
	finish()

func drive_race(race,car) -> void:
	var driver := DRIVER.new()
	driver.setup(car,race.course,0)
	driver.lane = -1.8
	driver.desired_lane = -1.8
	var rivals: Array = race.racers.duplicate()
	var deadline := Time.get_ticks_msec()+245000
	var next_report := Time.get_ticks_msec()
	while race.active and Time.get_ticks_msec()<deadline:
		driver.tick(1.0/float(Engine.physics_ticks_per_second),false,int(race.racers[6].run.checkpoint))
		await physics_frame
		if Time.get_ticks_msec()>=next_report:
			next_report = Time.get_ticks_msec()+10000
			print("DOWNHILL_RACERS ",rivals.map(func(e): return {"name":e.name,"gate":e.run.checkpoint,"finish":e.run.finish,"failure":e.run.failure,"point":str(e.car.global_position) if is_instance_valid(e.car) else "freed"}))
	var dante: Dictionary = {}
	for e in rivals: if e.player: dante = {"gate":e.run.checkpoint,"finish":e.run.finish,"failure":e.run.failure,"elapsed":e.run.elapsed,"speed":e.car.speed if is_instance_valid(e.car) else -1,"health":e.car.health if is_instance_valid(e.car) else -1}
	print("DOWNHILL_DANTE_END ",dante," last=",race.last_result," active=",race.active)
	car.set_external_driver(false)
	car.controlled = world.driving.occupied and world.driving.car==car
	check(not race.active and race.last_result.get("finished",false),"player completes full route using physics and ordered checkpoints")
	var final_gate: int = race.course.gate_offsets.size()
	check(rivals.filter(func(e): return not e.player and int(e.run.checkpoint)>=final_gate-3).size()==6,"all six rivals stay competitive through most of the course")
	check(rivals.filter(func(e): return not e.player and not str(e.run.failure).is_empty()).is_empty(),"six rival drivers finish observation without disqualification")
	check(race.snapshot().finishes==1,"real finish persisted once")
	check(preload("res://systems/campaign/MountainDownhillProgress.gd").validate_wallet(race.snapshot(),world.session.state.economy.snapshot()),"runtime result agrees with actual reward ledger")

func finish() -> void:
	print("MOUNTAIN_DOWNHILL_RUNTIME checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
