extends SceneTree
## Rendered functional evidence, separate from the frame-time benchmark.
## Run with Godot .NET -- --no-save --skip-arrival --population=24 --label=after.
## Saves per-frame metadata and either JPEG frames or an external native video.
## Continuous capture spans >=30 s including entry, driving, steering, braking,
## night headlights and exit. Image readback overhead is NOT a performance result.
var world
var car: CharacterBody3D
var route: Curve3D
var folder := "res://evidence/sport-coupe-redesign/after/flow"
var phase := "setup"
var night := false
var recording := false
var recording_finished := false
var capture_start := 0
var rows: Array[Dictionary] = []
var events: Array[Dictionary] = []
var failures: Array[String] = []
var expected_night_lamps := false
var night_lamp_frames := 0
var night_lamp_failures := 0
var max_steering := 0.0
var travelled := 0.0
var last_car_position := Vector3.ZERO
var normal_max_fps := 60
var external_capture := false
var skip_normal := false
var admitted_route := {}

func _initialize() -> void: run.call_deferred()

func record_check(ok: bool, description: String) -> bool:
	events.append({"phase":phase,"seconds":float(Time.get_ticks_usec()-capture_start)/1000000.0 if capture_start > 0 else 0.0,"ok":ok,"description":description})
	if not ok:
		failures.append(description)
		push_error(description)
	return ok

func run() -> void:
	var args := OS.get_cmdline_user_args()
	external_capture = "--external-capture" in args
	skip_normal = "--skip-normal" in args
	if DisplayServer.get_name() == "headless" or "--no-save" not in args:
		push_error("Rendered Godot .NET and --no-save required"); quit(2); return
	for arg in args:
		if arg.begins_with("--label="):
			folder = "res://evidence/sport-coupe-redesign/" + arg.trim_prefix("--label=").validate_filename() + "/flow"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder + "/frames"))
	seed(11102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	normal_max_fps = Engine.max_fps
	Engine.max_fps = 30 # Loading/capture budget, restored before the normal-settings sample.
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if not record_check(world.session != null and world.session.ready_for_play and world.production.no_save, "isolated Main ready"):
		await finish(); return
	world.production.set_population(24)
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	car = world.driving.car
	if not record_check(car.archetype == "sport_coupe", "real starter sport coupe selected"):
		await finish(); return
	car.paint_color = Color("ba3f35")
	car.ensure_equipment(world)
	# Move only during setup, to a physically admitted road pose. Capture contains
	# normal movement thereafter, without position/rotation injection.
	if not record_check(await prepare_road_pose(), "50 metres of authored road pass physical and camera admission"):
		await finish(); return
	car.external_input = false
	car.controlled = false
	car.brake_input = true
	for frame in 20: await physics_frame
	var approached := false
	for side in [-1, 1]:
		var approach: Vector3 = car.to_global(Vector3(float(side)*(car.half_width+.7), .04, .10))
		var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(approach+Vector3.UP*.3,approach-Vector3.UP*.5,1))
		if ground.is_empty(): continue
		approach.y = ground.position.y+.04
		if not world.session.position_clear(approach): continue
		world.player.teleport(approach)
		approached = true
		break
	if not record_check(approached, "player approach has solid ground and clear standing capsule beside car"):
		await finish(); return
	world.production.region.set_focus(car.global_position)
	world.camera.target = world.player
	world.camera.target_size = 15.0
	world.camera.set_preview_view(false)
	world.camera.heading = float(admitted_route.get("camera_heading",0.0))
	world.camera.offset = Vector3(0,25.3,25.3)
	world.camera.initialized = false
	set_time(false)
	await hold(1.0)
	# Independent normal-settings check, before any readbacks or capture coroutine.
	if not skip_normal:
		Engine.max_fps = normal_max_fps
		await measure_normal_settings()
	Engine.max_fps = 60 if external_capture else 30
	if external_capture:
		DisplayServer.window_move_to_foreground()
		FileAccess.open(folder+"/capture-ready.json",FileAccess.WRITE).store_string(JSON.stringify({"pid":OS.get_process_id(),"folder":ProjectSettings.globalize_path(folder)}))
		deadline = Time.get_ticks_msec()+30000
		while not FileAccess.file_exists(folder+"/capture-started.json") and Time.get_ticks_msec()<deadline:
			await process_frame
		if not record_check(FileAccess.file_exists(folder+"/capture-started.json"), "external recorder starts within thirty seconds"):
			await finish(); return
	last_car_position = car.global_position
	capture_start = Time.get_ticks_usec()
	recording = true
	_capture_loop()
	phase = "day-parked"
	await hold(1.0)
	await shot("01-day-parked")
	phase = "entry"
	if not record_check(world.driving.interact(), "Driving.interact accepts entry"):
		await finish(); return
	if not await transition_done(true): await finish(); return
	if not record_check(world.driving.car == car and car.controlled and world.player.seated and world.player.visible, "entry ends with visible seated driver in target coupe"):
		await finish(); return
	world.camera.target_size = 15.0
	await shot("02-day-inside")
	phase = "day-driving"
	await drive_for(7.0)
	if not failures.is_empty(): await finish(); return
	await shot("03-day-moving")
	phase = "night-transition"
	set_time(true)
	await hold(.3)
	expected_night_lamps = true
	phase = "night-driving"
	await drive_for(8.0)
	if not failures.is_empty(): await finish(); return
	await shot("04-night-moving")
	phase = "braking"
	release_inputs()
	Input.action_press("brake")
	deadline = Time.get_ticks_msec() + 8000
	while absf(car.speed) > .2 and Time.get_ticks_msec() < deadline and failures.is_empty(): await physics_frame
	release_inputs()
	Input.action_press("handbrake")
	if not record_check(absf(car.speed) <= .2, "service brake stops the car"):
		await finish(); return
	await hold(1.0)
	await shot("05-night-braking")
	expected_night_lamps = false # Engine/headlight shutdown on leaving is intentional.
	phase = "exit"
	release_inputs()
	if not record_check(world.driving.leave(), "Driving.leave accepts safe stopped exit"):
		await finish(); return
	if not await transition_done(false): await finish(); return
	record_check(not world.driving.occupied and not world.player.seated and world.player.visible, "exit restores visible on-foot player")
	phase = "night-exited"
	await shot("06-night-exited")
	while Time.get_ticks_usec()-capture_start < 30500000 and failures.is_empty(): await process_frame
	record_check(travelled > 16.0, "physical driving distance exceeds sixteen metres across day and night")
	record_check(max_steering > .025, "front wheels steer during the recorded road drive")
	record_check(absf(car.wheel_spin) > .1 and car.wheels.size() == 4, "all four wheels keep their physical spin pivots")
	record_check(night_lamp_frames > 30 and night_lamp_failures == 0, "both player projectors and lens materials remain lit throughout measured night driving/braking")
	await finish()

func route_sample(curve: Curve3D, distance: float) -> Vector3:
	var length := curve.get_baked_length()
	return curve.sample_baked(clampf(distance,0,length) if curve.get_meta("traffic_open",false) else fposmod(distance,length),true)

func prepare_road_pose() -> bool:
	var origin := car.global_position
	var deadline := Time.get_ticks_msec()+45000
	var graph = world.production.ambient_traffic_routes
	var candidates: Array[Dictionary] = []
	var rejected := {"physical":0,"camera":0}
	# Sample real authored straight road segments. The bounded slow review needs
	# 50 m, including stopping distance; do not require a complete traffic cycle.
	for segment in graph.segments:
		var a: Vector3 = segment.a
		var b: Vector3 = segment.b
		if a.distance_to(b)<65.0 or absf(a.y-b.y)>.3: continue
		var direction := a.direction_to(b)
		var offset: Vector3 = graph._lane_offset(direction,segment)
		var length := a.distance_to(b)
		for distance in [7.0,maxf(7.0,length*.5-25.0),length-57.0]:
			var point: Vector3 = a+direction*distance+offset
			if point.distance_to(origin)>400.0: continue
			candidates.append({"point":point,"direction":direction,"source":segment.id,"distance":point.distance_to(origin)})
	candidates.sort_custom(func(a,b): return a.distance<b.distance)
	for candidate in candidates:
		if Time.get_ticks_msec()>deadline: break
		var point: Vector3 = candidate.point+Vector3.UP*.12
		var direction: Vector3 = candidate.direction
		var yaw := atan2(-direction.x,-direction.z)
		var headings: Array[float] = [0.0,PI*.5,PI,-PI*.5]
		var clear := true
		for index in range(14):
			var probe := point+direction*minf(index*4.0,50.0)
			world.production.region.prepare_collision_at(probe)
			await physics_frame
			if not world.production.vehicle_position_clear(car,probe,yaw):
				rejected.physical+=1; clear=false; break
			var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
			for heading in headings.duplicate():
				for x in [-.75,0.0,.75]:
					var eye := probe+Vector3(0,25.3,25.3).rotated(Vector3.UP,heading)
					var sight := PhysicsRayQueryParameters3D.create(eye,probe+Vector3(x,.8,0),1)
					if not space.intersect_ray(sight).is_empty():
						headings.erase(heading); break
			if headings.is_empty(): rejected.camera+=1; clear=false; break
		if not clear: continue
		route=Curve3D.new()
		route.add_point(candidate.point)
		route.add_point(candidate.point+direction*60.0)
		route.set_meta("traffic_open",true)
		car.place(point,yaw)
		admitted_route={"start":str(point),"yaw":yaw,"checked_metres":50.0,"camera_heading":headings[0],"sources":[candidate.source],"rejected":rejected}
		print("SPORT_COUPE_FLOW_ROUTE ",JSON.stringify(admitted_route))
		return true
	print("SPORT_COUPE_FLOW_ROUTE_REJECTED ",JSON.stringify({"candidates":candidates.size(),"rejected":rejected}))
	return false

func measure_normal_settings() -> void:
	phase = "normal-settings"
	var warm: Array[float] = []
	var frames: Array[float] = []
	var focused := 0
	var minimized := 0
	var population_start: int = world.people.size()
	var began := Time.get_ticks_usec()
	var previous := began
	var measured_ms := 0.0
	while measured_ms < 30000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now-previous)/1000.0
		previous = now
		if now-began < 10000000:
			warm.append(elapsed)
			continue
		frames.append(elapsed)
		measured_ms += elapsed
		if DisplayServer.window_is_focused(): focused += 1
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED: minimized += 1
	var report := {"scenario":"daytime road pose before boarding, normal user settings",
		"summary":frame_stats(frames),"warmup":frame_stats(warm),"frames_ms":frames,"warmup_ms":warm,
		"max_fps":Engine.max_fps,"original_max_fps":normal_max_fps,
		"vsync":DisplayServer.window_get_vsync_mode(),"resolution":str(root.size),"msaa":root.msaa_3d,
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),
		"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"population_start":population_start,"population_end":world.people.size(),
		"focused_frames":focused,"minimized_frames":minimized,"car_position":str(car.global_position),
		"camera_position":str(world.camera.global_position),"camera_size":world.camera.size,
		"notes":"10 seconds warmup then >=30 seconds real frame intervals before recording starts. Original FPS cap restored; VSync and quality untouched. No screenshots or frame readbacks in this interval. This confirms only this stationary daytime scenario, not all driving/night settings."}
	FileAccess.open(folder+"/normal-settings.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPORT_COUPE_NORMAL_SETTINGS ",JSON.stringify(report.summary)," cap=",Engine.max_fps," vsync=",report.vsync)

func frame_stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in values:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/total,
		"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],
		"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":slow,"over_66_7_ms":very_slow}

func set_time(value: bool) -> void:
	night = value
	world.session.weather.time_of_day = .93 if night else .4
	world.session.weather.weather_state = 0
	world.production.state.world_state.time = .93 if night else .4
	world.production.state.world_state.weather = 0
	world.session.weather._update()
	car.equipment.headlights_on = night

func drive_for(seconds: float) -> void:
	var began := Time.get_ticks_msec()
	var distance := 0.0
	var previous := car.global_position
	var last_movement := began
	var health_before: float = car.health
	var deadzone := 0.0
	for action in ["move_left","move_right","move_up","move_down"]: deadzone += InputMap.action_get_deadzone(action)*.25
	while Time.get_ticks_msec()-began < seconds*1000.0 and failures.is_empty():
		var progress := route.get_closest_offset(car.global_position)
		var destination := route_sample(route,progress+5.0)
		var direction := destination-car.global_position
		var yaw := atan2(-direction.x,-direction.z)
		var steer := clampf(angle_difference(car.rotation.y,yaw)*1.8,-.65,.65)
		# One gentle half-second correction makes steering visible on a straight,
		# while the road-following controller immediately brings the car back.
		if Time.get_ticks_msec()-began < 450: steer = .28
		Input.action_release("move_left")
		Input.action_release("move_right")
		if absf(steer)>.015:
			# Input.get_vector removes the average action deadzone; compensate it
			# explicitly so a gentle direction input reaches the real player path.
			Input.action_press("move_left" if steer > 0 else "move_right", deadzone+(1.0-deadzone)*absf(steer))
		if car.speed < 2.5: Input.action_press("accelerate", .4)
		else: Input.action_release("accelerate")
		await physics_frame
		distance += car.global_position.distance_to(previous)
		previous=car.global_position
		if absf(car.speed)>.5: last_movement=Time.get_ticks_msec()
		if Time.get_ticks_msec()-last_movement>2500:
			record_check(false,"recorded road drive stalled for more than 2.5 seconds")
		if car.health <= 0 or car.equipment.broken_left or car.equipment.broken_right:
			record_check(false, "driving route collision damaged target headlights")
		elif car.health < health_before-1.0:
			record_check(false,"recorded road drive collided and lost vehicle health")
	release_inputs()
	if failures.is_empty(): record_check(distance>8.0,phase+" physically covers at least eight metres")

func release_inputs() -> void:
	for action in ["accelerate","brake","handbrake","move_left","move_right"]: Input.action_release(action)

func transition_done(inside: bool) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec() < deadline and failures.is_empty(): await process_frame
	return record_check(not world.driving.is_body_transition_active() and world.driving.occupied == inside, "entry completes" if inside else "exit completes")

func hold(seconds: float) -> void:
	var until := Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec() < until and failures.is_empty(): await process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder+"/"+name+".png"))

func _capture_loop() -> void:
	while recording:
		await RenderingServer.frame_post_draw
		if not recording: break
		var now := Time.get_ticks_usec()
		var file := "drive.mp4" if external_capture else "frames/%06d.jpg" % rows.size()
		if not external_capture: root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(folder+"/"+file), .88)
		var lamps := 0
		var lenses := 0
		for item in car.equipment.lamps:
			if item.lamp.visible: lamps += 1
		for item in car.equipment.lens_materials:
			if item.material.emission_enabled and item.material.emission_energy_multiplier > 0: lenses += 1
		if expected_night_lamps:
			night_lamp_frames += 1
			if lamps != 2 or lenses < 2: night_lamp_failures += 1
		travelled += car.global_position.distance_to(last_car_position)
		last_car_position = car.global_position
		max_steering = maxf(max_steering,absf(car.steering))
		rows.append({"file":file,"seconds":float(now-capture_start)/1000000.0,"phase":phase,
			"night":night,"position":str(car.global_position),"yaw":car.rotation.y,"speed":car.speed,
			"steering":car.steering,"wheel_spin":car.wheel_spin,"lamps_visible":lamps,"lenses_lit":lenses,
			"tail_state":car.equipment._tail_state,"health":car.health,"controlled":car.controlled})
		if now-capture_start > 90000000:
			record_check(false,"90-second capture watchdog exceeded")
			recording = false
	recording_finished = true

func finish() -> void:
	release_inputs()
	recording = false
	if capture_start > 0:
		while not recording_finished: await process_frame
	var report := {"ok":failures.is_empty(),"failures":failures,"events":events,"frames":rows,
		"continuous_seconds":rows[-1].seconds if not rows.is_empty() else 0.0,
		"travelled_m":travelled,"maximum_steering_rad":max_steering,
		"night_lamp_frames":night_lamp_frames,"night_lamp_state_failures":night_lamp_failures,
		"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),
		"external_capture":external_capture,"normal_settings_skipped":skip_normal,"admitted_route":admitted_route,
		"notes":"Real Main, normal player input and metadata every rendered frame. External mode records native video without engine readbacks except six PNG snapshots; fallback mode saves JPEG frames. This is functional/temporal evidence, never a frame-time benchmark. Night shutdown after exiting is intentional. Visual flicker inspection still required."}
	FileAccess.open(folder+"/flow.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPORT_COUPE_FLOW ","PASS" if failures.is_empty() else "FAIL"," frames=",rows.size()," distance=",travelled," failures=",failures)
	if is_instance_valid(world): world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
