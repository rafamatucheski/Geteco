extends "res://tests/measure/measure.gd"

var arrival
var scenario := "motorcycle"
var baseline := false
var evidence_dir := "res://evidence/arrival-chaos-20261010"
var spawned: Array[Node] = []
var frames: Array[Dictionary] = []
var recording := false
var last_capture := 0
var capture_index := 0
var tour_start := 0
var invalid_overlap := false
var frame_query := PhysicsShapeQueryParameters3D.new()
var capture_motion := false
var dynamic_added := false
var night := false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.get_slice("=",1)
		if arg.begins_with("--label="): label = arg.get_slice("=",1)
		if arg == "--baseline": baseline = true
		if arg == "--capture-motion": capture_motion = true
		if arg == "--night": night = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))
	root.get_node("V2Launch").selected_path = "user://arrival-chaos-unused.json"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: push_error("Chaos startup unavailable"); quit(1); return
	arrival = world.session.arrival
	if night:
		world.session.weather.time_of_day = .94
		world.session.weather.weather_state = 1
		world.session.weather.rain_intensity = .25
		world.session.weather.weather_timer = 180
		world.session.weather._update()
	arrival.active = false
	arrival.cancel_dialogue()
	world.player.teleport(arrival.PARK+Vector3(4,.08,0))
	world.production.region.set_focus(arrival.PARK)
	deadline = Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.production.region.is_streaming_idle(): break
	arrival._spawn_encounter()
	if baseline:
		var legacy: CharacterBody3D = load("res://evidence/arrival-chaos-20261010/ArrivalLegacyDriver.gd").new()
		legacy.position = arrival.car.position
		legacy.rotation = arrival.car.rotation
		arrival.car.queue_free()
		world.add_child(legacy)
		legacy.set_physics_process(false)
		arrival.car = legacy
	arrival.active = true
	arrival.opening_completed = true
	arrival.flags = {"harbor_arrival_seen":true,"harbor_arrival_contact_met":true}
	arrival._caption = -1
	arrival._caption_wait = 4
	world.player.teleport(arrival.car.door_point(1)+Vector3.UP*.08)
	for frame in 8: await physics_frame
	arrival._set_phase("tour_board","",arrival.car.door_point(1))
	if not arrival.perform("arrival_board"): push_error("Passenger action unavailable"); quit(1); return
	deadline = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if arrival.riding or arrival.phase == "tour_board": break
	if not arrival.riding: push_error("Actual passenger boarding failed"); quit(1); return
	print("CHAOS_BOARD route=",arrival.route.get_baked_length()," control_points=",arrival.route.point_count," intro=",world.session.state.intro.stage)
	# Add ordinary production vehicles on the route, rather than removing
	# traffic/collisions or placing the mission car past the blockage.
	if scenario != "normal":
		for index in (1 if scenario == "motorcycle" else 6):
			var offset := 22.0+float(index/2)*6.0
			var p: Vector3 = arrival.route.sample_baked(offset,true)
			var tangent: Vector3 = arrival.route.sample_baked(offset+.5,true)-arrival.route.sample_baked(offset-.5,true)
			var right := tangent.normalized().cross(Vector3.UP)
			var vehicle := preload("res://scripts/Vehicle.gd").new()
			vehicle.vehicle_id = "chaos_parked_%d" % index
			vehicle.archetype = "bike_sport" if index == 0 else "sedan_classic"
			world.add_child(vehicle)
			var shift := 0.0 if index == 0 else (-3.2 if index%2 else 0.0)
			vehicle.place(p+right*shift+Vector3.UP*.08,atan2(-tangent.x,-tangent.z)+(PI*.5 if index==0 else 0.0))
			vehicle.set_physics_process(false)
			spawned.append(vehicle)
			print("CHAOS_OBSTACLE ",vehicle.vehicle_id," ",vehicle.archetype," ",vehicle.global_position)
	frame_query.shape = arrival.car.rotation_shape
	frame_query.collision_mask = 4
	frame_query.exclude = [arrival.car.get_rid()]
	tour_start = Time.get_ticks_usec()
	started = tour_start
	previous = started
	recording = true
	deadline = Time.get_ticks_msec()+(45000 if baseline else 360000)
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if not arrival.riding or arrival.flags.get("harbor_city_tour_complete",false): break
		if scenario == "dynamic" and not dynamic_added and arrival.car.recovery_count>0 and arrival.car.recovery_path.size()>arrival.car.recovery_index+3:
			var pose: Dictionary = arrival.car.recovery_path[arrival.car.recovery_index+3]
			var bike := preload("res://scripts/Vehicle.gd").new()
			bike.vehicle_id = "chaos_dynamic_motorcycle"
			bike.archetype = "bike_sport"
			world.add_child(bike)
			bike.place(pose.p+Vector3.UP*.08,float(pose.yaw)+PI*.5)
			bike.set_physics_process(false)
			spawned.append(bike)
			dynamic_added = true
			print("CHAOS_DYNAMIC_BLOCKER position=",bike.global_position)
		frame_query.transform = Transform3D(arrival.car.global_basis,arrival.car.to_global(arrival.car.shape.position))
		for hit in world.get_world_3d().direct_space_state.intersect_shape(frame_query,16):
			if hit.collider in spawned: invalid_overlap = true
	recording = false
	var tour_ok: bool = arrival.flags.get("harbor_city_tour_complete",false)
	var mission_ok := false
	if tour_ok and not baseline:
		var entrance: Vector3 = world.maciota_place.entry_position+Vector3(0,0,1.0)
		# Player controls remain normal. Walk around the facade through its open
		# court rather than asking the foot grid for a diagonal through the shop.
		var court_z: float = world.maciota_place.exterior_origin.z+9.3
		var walked: bool = await arrival._walk(world.player,Vector3(world.player.global_position.x,0,court_z),true)
		if walked: walked = await arrival._walk(world.player,entrance,true)
		print("CHAOS_GARAGE_APPROACH walked=",walked," player=",world.player.global_position," entrance=",entrance)
		if walked and await world.session.enter_place("maciota",false):
			var admission_deadline := Time.get_ticks_msec()+15000
			while Time.get_ticks_msec()<admission_deadline:
				await physics_frame
				if world.session.state.place_id=="maciota" and not world.session.is_transition_blocked(): break
			print("CHAOS_ADMISSION place=",world.session.state.place_id," blocked=",world.session.is_transition_blocked()," player=",world.player.global_position)
			var meeting: Vector3 = world.maciota_place.interaction_points.maciota+Vector3(0,0,.8)
			var interior_origin: Vector3 = world.maciota_place.interior_origin
			# The partition has its authored doorway at (2.4, 1.5). Stay
			# inside and use that opening; walking toward the front triggers exit.
			var to_contact := true
			for local in [Vector3(1.5,0,3.2),Vector3(1.5,0,1.5),Vector3(3.4,0,1.5)]:
				if not await arrival._walk(world.player,interior_origin+local,true): to_contact = false; break
			if to_contact: to_contact = await arrival._walk(world.player,meeting,true)
			print("CHAOS_INTERIOR_APPROACH walked=",to_contact," player=",world.player.global_position," meeting=",meeting)
			if not to_contact:
				for index in world.player.get_slide_collision_count(): print("CHAOS_WALK_BLOCKER ",world.player.get_slide_collision(index).get_collider().get_path())
			if to_contact:
				print("CHAOS_MEETING action=",world.session.nearest())
				await world.session.interact()
				mission_ok = arrival.flags.get("harbor_maciota_met",false)
	await capture()
	var report := {"scenario":scenario,"label":label,"baseline":baseline,"night":night,"capture_motion":capture_motion,"tour_complete":tour_ok,"mission_complete":mission_ok,"phase":arrival.phase,"riding":arrival.riding,"overlap":invalid_overlap,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size(),"traffic":world.production.vehicles.size(),"seconds":float(Time.get_ticks_usec()-tour_start)/1000000,"summary":stats(samples),"warmup":stats(cold),"frame_intervals_ms":samples,"trace":frames,"position":arrival.car.global_position,"route_distance":arrival.car.route_distance,"route_length":arrival.car.route.get_baked_length(),"recoveries":arrival.car.get("recovery_count")}
	var file := FileAccess.open(evidence_dir+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	var brief := report.duplicate()
	brief.frame_intervals_ms = []
	brief.trace = []
	print("CHAOS_RESULT ",JSON.stringify(brief))
	world.free()
	await process_frame
	quit(0 if (baseline or (tour_ok and mission_ok)) and not invalid_overlap else 1)

func _process(_delta: float) -> bool:
	if not recording: return false
	var now := Time.get_ticks_usec()
	var ms := float(now-previous)/1000
	previous = now
	if now-started<5000000: cold.append(ms)
	elif now-started<35000000: samples.append(ms)
	if now-last_capture>500000:
		last_capture = now
		frames.append({"seconds":float(now-started)/1000000,"position":arrival.car.global_position,"yaw":arrival.car.rotation.y,"speed":arrival.car.speed,"route":arrival.car.route_distance,"recovery":arrival.car.get("recovery_count")})
	# Render readback/encoding is evidence overhead, not the game's frame time.
	# Keep it out of the fixed 5s warmup + 30s measurement window.
	if (capture_motion or now-started>35000000) and now-last_capture_image>2000000:
		last_capture_image = now
		capture.call_deferred()
	return false

var last_capture_image := 0
func capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(evidence_dir+"/"+label+"-%04d.jpg" % capture_index,.8)
	capture_index += 1
