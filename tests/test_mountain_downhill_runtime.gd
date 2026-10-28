extends SceneTree
## Real Main/Vehicle/.NET integration. --no-save is mandatory. --drive adds
## a complete physical race, with test input supplied through the new pilot;
## it never places vehicles or changes checkpoint progress after the start.
const DRIVER := preload("res://activities/mountain_downhill/MountainDownhillDriver.gd")
var world
var checks := 0
var failures: Array[String] = []
var frame_samples: Array[float] = []
var sample_frames := false
var previous_frame_usec := 0
var driving_script: GDScript = DRIVER
var observation_seconds := 0.0

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if sample_frames and previous_frame_usec > 0:
		frame_samples.append(float(now-previous_frame_usec)/1000.0)
	previous_frame_usec = now
	return false

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
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--driver-reference="):
			driving_script = GDScript.new()
			driving_script.source_code = FileAccess.get_file_as_string(argument.trim_prefix("--driver-reference="))
			if driving_script.reload() != OK:
				push_error("Cannot load explicitly requested reference driver")
				quit(2)
				return
		if argument.begins_with("--observe-seconds="):
			observation_seconds = clampf(argument.trim_prefix("--observe-seconds=").to_float(),35.0,240.0)
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
	if driving_script != DRIVER:
		for entry in race.racers:
			if entry.player: continue
			entry.pilot = driving_script.new()
			entry.pilot.setup(entry.car,race.course,int(entry.index))
		if "peers" in race.racers[0].pilot: race._link_pilots()
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
	sample_frames = true
	var driver = driving_script.new()
	driver.setup(car,race.course,0)
	driver.lane = -1.8
	driver.desired_lane = -1.8
	var rivals: Array = race.racers.duplicate()
	var deadline := Time.get_ticks_msec()+int((observation_seconds if observation_seconds>0.0 else 245.0)*1000.0)
	var next_report := Time.get_ticks_msec()
	var next_contact_report := Time.get_ticks_msec()
	while race.active and Time.get_ticks_msec()<deadline:
		driver.tick(1.0/float(Engine.physics_ticks_per_second),false,int(race.racers[6].run.checkpoint))
		await physics_frame
		if "--diagnose-contacts" in OS.get_cmdline_user_args() and Time.get_ticks_msec()>=next_contact_report:
			next_contact_report = Time.get_ticks_msec()+250
			for entry in rivals:
				if entry.player or not is_instance_valid(entry.car) or int(entry.run.checkpoint) > 13: continue
				var body = entry.car
				var offset: float = race.course.nearest_offset(body.global_position)
				var contacts: Array = []
				var merge_blocker: Dictionary = {}
				if entry.pilot.desired_lane<0.0 and absf(float(body.speed))<3.0:
					if not entry.pilot._lane_clear(offset,clampf(4.0+absf(float(body.speed))*.27,4.0,12.0),1.8):
						var blocked: Array = body.get_world_3d().direct_space_state.intersect_shape(entry.pilot.lane_query,1)
						if not blocked.is_empty():
							merge_blocker = {"body":str(blocked[0].collider.get_path()),"query_point":str(entry.pilot.lane_query.transform.origin)}
				# Ultrapassagem recusada atrás de carro lento: o que fecha o corredor da esquerda (28/10).
				var pass_blocker: Dictionary = {}
				if entry.pilot.desired_lane>0.0 and absf(float(body.speed))<6.0 and is_finite(float(entry.pilot.gap)):
					var straight: bool = entry.pilot._passing_straight(offset)
					var clear: bool = entry.pilot._lane_clear(offset,clampf(4.0+absf(float(body.speed))*.27,4.0,12.0),-1.8)
					pass_blocker = {"straight":straight,"clear":clear,"cooldown":entry.pilot.pass_cooldown}
					if not clear:
						var blocked: Array = body.get_world_3d().direct_space_state.intersect_shape(entry.pilot.lane_query,1)
						if not blocked.is_empty(): pass_blocker["body"] = str(blocked[0].collider.get_path())
				var sensor: Dictionary = {}
				var nearest := INF
				var reach := minf(55.0,5.0+float(body.speed)*float(body.speed)/10.0)
				var origin: Vector3 = body.global_position+Vector3.UP*.65-body.global_basis.z*(body.half_length+.2)
				for side in [-.8,0.0,.8]:
					var from: Vector3 = origin+body.global_basis.x*float(body.half_width)*side
					var query := PhysicsRayQueryParameters3D.create(from,from-body.global_basis.z*reach,7,[body.get_rid()])
					var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(query)
					if not hit.is_empty() and from.distance_to(hit.position)<nearest:
						nearest = from.distance_to(hit.position)
						sensor = {"body":str(hit.collider.get_path()),"point":str(hit.position),"distance":nearest,"normal":str(hit.normal)}
						if hit.collider.is_in_group("drivable"):
							sensor.merge({"vehicle_id":hit.collider.vehicle_id,"archetype":hit.collider.archetype,"traffic":hit.collider.traffic,"ambient":hit.collider.get_meta("ambient_traffic",false),"rival":hit.collider.get_meta("mountain_downhill_rival",false),"speed":hit.collider.speed,"heading_dot":(-body.global_basis.z).dot(-hit.collider.global_basis.z)})
				for j in body.get_slide_collision_count():
					var contact = body.get_slide_collision(j)
					contacts.append({"body":str(contact.get_collider().get_path()),"normal":str(contact.get_normal())})
				# Só o que explica perda de tempo: lento ou encostado em outro carro.
				var touching := contacts.any(func(c): return "CharacterBody3D" in str(c.body))
				if absf(float(body.speed)) >= 6.0 and not touching: continue
				print("DOWNHILL_CONTACT ",{"name":entry.name,"time":entry.run.elapsed,"gate":entry.run.checkpoint,"offset":offset,"point":str(body.global_position),"yaw":body.rotation.y,"lane":entry.pilot.lane,"actual_lane":(body.global_position-race.course.point(offset)).dot(race.course.direction(offset).cross(Vector3.UP).normalized()),"speed":body.speed,"steer":body.steer_input,"gap":entry.pilot.gap,"reverse":entry.pilot.reverse_left,"contacts":contacts,"sensor":sensor,"merge_blocker":merge_blocker,"pass_blocker":pass_blocker})
		if Time.get_ticks_msec()>=next_report:
			next_report = Time.get_ticks_msec()+10000
			print("DOWNHILL_RACERS ",rivals.map(func(e): return {"name":e.name,"gate":e.run.checkpoint,"finish":e.run.finish,"failure":e.run.failure,"point":str(e.car.global_position) if is_instance_valid(e.car) else "freed","speed":e.car.speed if is_instance_valid(e.car) else 0,"recoveries":e.pilot.recoveries if e.pilot != null else driver.recoveries,"gap":e.pilot.gap if e.pilot != null else driver.gap}))
	var dante: Dictionary = {}
	for e in rivals: if e.player: dante = {"gate":e.run.checkpoint,"finish":e.run.finish,"failure":e.run.failure,"elapsed":e.run.elapsed,"speed":e.car.speed if is_instance_valid(e.car) else -1,"health":e.car.health if is_instance_valid(e.car) else -1}
	print("DOWNHILL_DANTE_END ",dante," last=",race.last_result," active=",race.active)
	print("DOWNHILL_RESULTS ",rivals.map(func(e): return {"name":e.name,"gate":e.run.checkpoint,"progress":e.run.progress,"finish":e.run.finish,"failure":e.run.failure}))
	sample_frames = false
	if not frame_samples.is_empty():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--frame-samples="):
				var output := FileAccess.open(argument.trim_prefix("--frame-samples="),FileAccess.WRITE)
				if output != null:
					output.store_string(JSON.stringify({"frame_ms_in_order":frame_samples,"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"viewport":str(root.size)}))
		frame_samples.sort()
		var total := 0.0
		for sample in frame_samples: total += sample
		print("DOWNHILL_FRAME_TIME ",{"frames":frame_samples.size(),"seconds":total/1000.0,"fps":float(frame_samples.size())*1000.0/total,"p50":frame_samples[int(frame_samples.size()*.5)],"p95":frame_samples[int(frame_samples.size()*.95)],"p99":frame_samples[int(frame_samples.size()*.99)],"max":frame_samples.back(),"over33":frame_samples.filter(func(v): return v>33.3).size(),"over66":frame_samples.filter(func(v): return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"viewport":root.size})
	car.set_external_driver(false)
	car.controlled = world.driving.occupied and world.driving.car==car
	if observation_seconds>0.0:
		print("DOWNHILL_BOUNDED_OBSERVATION seconds=",observation_seconds," reference_driver=",driving_script != DRIVER)
		race.cancel_attempt()
		check(not race.active and race.snapshot().finishes==0,"bounded measurement cancels without granting a finish or prize")
		return
	check(not race.active and race.last_result.get("finished",false),"player completes full route using physics and ordered checkpoints")
	var final_gate: int = race.course.gate_offsets.size()
	check(rivals.filter(func(e): return not e.player and int(e.run.checkpoint)>=final_gate-3).size()==6,"all six rivals stay competitive through most of the course")
	check(rivals.filter(func(e): return not e.player and not str(e.run.failure).is_empty()).is_empty(),"six rival drivers finish observation without disqualification")
	check(race.snapshot().finishes==1,"real finish persisted once")
	check(preload("res://systems/campaign/MountainDownhillProgress.gd").validate_wallet(race.snapshot(),world.session.state.economy.snapshot()),"runtime result agrees with actual reward ledger")

func finish() -> void:
	print("MOUNTAIN_DOWNHILL_RUNTIME checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
