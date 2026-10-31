extends "res://tests/measure/measure.gd"
## Jogo no Main, entrada real do jogador e população normal; 8 s de aquecimento + 30 s.
## Rode a mesma carga antes/depois, com --no-save --skip-arrival.
var scenario := "street"
var variant := "before"
var output_dir := "res://evidence/motorcycle-wheelie-20261004"
var bike: CharacterBody3D
var workload_started := 0
var lifted_frames := 0

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	seed(4102026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save: quit(3); return
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.state.intro.stage = "complete"
	if scenario == "motocross":
		world.player.teleport(Vector3(-224,.15,-37))
		world.production.region.set_focus(world.player.position)
		world.session.state.economy.grant_reward("wheelie_measure", 1000)
		if not world.session.motocross.rent_bike(): quit(4); return
		bike = world.session.motocross.player_bike
	else:
		bike = preload("res://scripts/Vehicle.gd").new()
		bike.archetype = "bike_urban"
		world.add_child(bike)
		driving_route = world.production.traffic_routes.route_near(Vector3(66,.1,129))
		if driving_route == null: quit(5); return
		var distance := driving_route.get_closest_offset(Vector3(66,.1,129))
		var placed := false
		for attempt in 20:
			var offset := fposmod(distance + attempt*6, driving_route.get_baked_length())
			var point := driving_route.sample_baked(offset, true)
			var direction := driving_route.sample_baked(minf(offset+1,driving_route.get_baked_length()),true)-point
			var yaw := atan2(-direction.x,-direction.z)
			if not world.production.vehicle_position_clear(bike, point+Vector3.UP*.12, yaw): continue
			bike.place(point+Vector3.UP*.12, yaw)
			world.player.teleport(bike.driver_door_anchor(-1))
			world.production.region.set_focus(point)
			await physics_frame
			if world.driving.interact(): placed = true; break
		if not placed: quit(6); return
		for i in 300:
			await physics_frame
			if bike.controlled and not world.driving.is_body_transition_active(): break
		if not bike.controlled: quit(7); return
	world.camera.target_size = 22
	workload_started = Time.get_ticks_usec()
	previous = workload_started
	started = workload_started

func _process(_delta: float) -> bool:
	if started == 0 or not is_instance_valid(bike): return false
	var now := Time.get_ticks_usec()
	var elapsed := float(now-workload_started)/1000000.0
	var frame_ms := float(now-previous)/1000.0
	previous = now
	var target: Vector3
	if scenario == "motocross":
		var course = world.session.motocross.track
		var nearest: Dictionary = course.nearest(bike.global_position)
		target = course.sample(float(nearest.distance)+5.0)
	else:
		var offset := driving_route.get_closest_offset(bike.global_position)
		target = driving_route.sample_baked(fposmod(offset+5,driving_route.get_baked_length()),true)
	var toward := target-bike.global_position
	var error := angle_difference(bike.rotation.y,atan2(-toward.x,-toward.z))
	var turn := clampf(error*1.8,-1,1)
	var desired_speed := lerpf(11.0,4.0,clampf(absf(error)/.8,0,1))
	var lift_requested := fposmod(elapsed,8.0) > 1 and fposmod(elapsed,8.0) < 5 and absf(error) < .4
	# Mantém o torque de tração durante a manobra. Um acelerador de cruzeiro quase zero abaixa
	# a frente por design e não exercita empinadas manuais sustentadas.
	Input.action_press("move_up", 1.0 if bike.speed < desired_speed else (.65 if lift_requested else .12))
	Input.action_press("move_left", maxf(0,turn))
	Input.action_press("move_right", maxf(0,-turn))
	if InputMap.has_action("motorcycle_wheelie"):
		if lift_requested: Input.action_press("motorcycle_wheelie")
		else: Input.action_release("motorcycle_wheelie")
	if elapsed < 8: cold.append(frame_ms)
	else:
		samples.append(frame_ms)
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		var lift_state = bike.get("manual_wheelie")
		if lift_state != null and lift_state.pitch > .25: lifted_frames += 1
	if elapsed >= 38:
		started = 0
		finish.call_deferred()
	return false

func finish() -> void:
	var folder := output_dir.path_join(variant)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"scenario":scenario,"variant":variant,"scene":"Main.tscn","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size(),"vehicles":world.production.vehicles.size(),"summary":stats(samples),"warmup":stats(cold),"cpu":stats(cpu),"physics":stats(physics),"intervals_ms":samples,"warmup_ms":cold,"lifted_frames":lifted_frames,"position":str(bike.global_position)}
	report["source_sha256"] = {}
	for path in ["scripts/Vehicle.gd","scripts/Driving.gd","runtime/GameInput.gd","runtime/FullSession.gd","activities/motocross/MotocrossBike.gd","activities/motocross/Motocross.gd","gameplay/MotorcycleWheelie.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256("res://"+path)
	FileAccess.open(folder+"/"+scenario+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WHEELIE_MEASURE ",scenario," ",JSON.stringify(report.summary)," lifted_frames=",lifted_frames)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+scenario+".png")
	for action in ["move_up","move_left","move_right","motorcycle_wheelie"]:
		if InputMap.has_action(action): Input.action_release(action)
	world.free()
	await process_frame
	quit()
