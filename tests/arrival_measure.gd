extends "res://tests/measure.gd"
var cgi := false
var arrival
var capture_busy := false
var finished_measurement := false
var observed_phases: Array[String] = []
var startup_ms := 0.0

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	cgi = "--cgi" in OS.get_cmdline_user_args()
	label = "arrival-cgi" if cgi else "arrival-tour"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
	var loading_started := Time.get_ticks_usec()
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for i in 600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size() >= world.production.requested_population: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	arrival = world.session.arrival
	arrival.phase = "new"
	arrival.flags.clear()
	arrival.active = true
	arrival.opening_completed = not cgi
	if cgi:
		arrival.start_or_resume(false)
		for i in 4: await process_frame
	else:
		arrival.flags = {"harbor_arrival_seen":true,"harbor_police_briefed":true,"harbor_arrival_call_complete":true}
		world.player.teleport(arrival.PARK + Vector3(4,.1,0))
		world.production.region.set_focus(arrival.PARK)
		for i in 15: await physics_frame
		arrival._spawn_encounter()
		world.player.teleport(arrival.car.door_point(1) + Vector3(0,0,1.2))
		for i in 12: await physics_frame
		await capture("meeting")
		arrival._set_phase("tour_board", "[E] Entrar como passageiro", arrival.car.door_point(1))
		arrival.perform("arrival_board")
		for i in 600:
			await physics_frame
			if arrival.riding: break
		if not arrival.riding: push_error("Rendered boarding failed"); quit(1); return
	startup_ms = float(Time.get_ticks_usec() - loading_started) / 1000.0
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0 or finished_measurement: return false
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - previous) / 1000.0
	previous = now
	if not observed_phases.has(arrival.phase): observed_phases.append(arrival.phase)
	if not measuring:
		cold.append(frame_ms)
		if now - started >= 5000000:
			measuring = true
			measured_started = now
		return false
	samples.append(frame_ms)
	cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
	physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000)
	if now - measured_started >= 30000000:
		finished_measurement = true
		finish.call_deferred()
	return false

func capture(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/" + label + "-" + suffix + ".png")

func finish() -> void:
	var report := {"label":label,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"population":world.people.size(),"requested_population":world.production.requested_population,"cars":world.production.vehicles.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":stats(samples),"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"warmup_intervals_ms":cold,"cpu_ms":cpu,"physics_ms":physics,"startup_ms":startup_ms,"phases_measured":observed_phases,"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"notes":"Actual integrated Main. 5s warmup separated from30s real frame intervals. Screenshots outside measurement. Same production settings as native24 baseline; arrival route/film differs from old native driving scenario, so not a controlled regression comparison."}
	await capture("measured")
	if cgi:
		arrival.presentation.film.seek(62.0 + preload("res://cutscenes/opening/v3/opening_timeline.gd").E)
		for i in 3: await process_frame
		await capture("bus-gallery")
		arrival.presentation.film.seek(74.0 + preload("res://cutscenes/opening/v3/opening_timeline.gd").E)
		for i in 3: await process_frame
		await capture("terminal")
		arrival.presentation.film.skip()
		for i in 600:
			await physics_frame
			if arrival.phase == "police_visit": break
		await capture("disembarked")
		report.disembarked = arrival.phase == "police_visit"
	else:
		for i in 2400:
			await physics_frame
			if arrival.flags.get("harbor_city_tour_complete", false): break
		for i in 180: await physics_frame
		await capture("garage")
		report.vehicle_distance = arrival.car.distance_travelled
		report.route_distance = arrival.car.route_distance
		report.route_length = arrival.route.get_baked_length()
		report.tour_complete = arrival.flags.get("harbor_city_tour_complete", false)
		report.maciota_entered = not arrival.maciota.visible
	var file := FileAccess.open("res://evidence/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ARRIVAL_BENCHMARK ", label, " ", JSON.stringify(report.summary), " phase=", arrival.phase)
	world.free()
	await process_frame
	quit(0 if cgi or report.tour_complete else 1)
