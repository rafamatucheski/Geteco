extends "res://tests/measure/measure.gd"
var combat_mode := false
var fire_clock := 0.0
var combat_alive_seconds := 0.0
var combat_shots := 0
var evidence_dir := ""
var ablate_traffic := false
var ablate_population := false
var sample_population := -1
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
		if arg.begins_with("--evidence-dir="): evidence_dir = arg.split("=")[1]
		if arg == "--ablate-traffic": ablate_traffic = true
		if arg == "--ablate-population": ablate_population = true
		if arg.begins_with("--sample-population="): sample_population = arg.split("=")[1].to_int()
		if arg == "--drive": driving_mode = true
		if arg == "--combat": combat_mode = true
	world = load("res://Main.tscn").instantiate()
	world.set_meta("benchmark_trace","--trace-runtime" in OS.get_cmdline_user_args())
	root.add_child(world)
	var startup_frames := 4800 # 100 streamed residents may need 25+ seconds plus collision retries.
	for i in startup_frames:
		await physics_frame
		var startup_population: int = world.production.requested_population if sample_population < 0 else sample_population
		if world.session != null and world.session.ready_for_play and world.people.size() >= startup_population: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Native world failed to start"); quit(1); return
	var required_population: int = world.production.requested_population if sample_population < 0 else sample_population
	if world.people.size() < required_population:
		push_error("Requested benchmark population was not reached before sampling"); quit(1); return
	if ablate_population: world.set_population(24)
	if ablate_traffic:
		for index in range(world.production.vehicles.size()-1,-1,-1):
			var vehicle: CharacterBody3D = world.production.vehicles[index]
			if vehicle.traffic:
				world.production.vehicles.remove_at(index)
				vehicle.queue_free()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	for child in world.hud.get_children():
		if child.get_script() == preload("res://scripts/PauseInput.gd"): child.set_process_unhandled_input(false)
	world.player.controlled_automatically = true
	world.player.speed = 1.5
	if "--interior" in OS.get_cmdline_user_args():
		if not await world.session.enter_place("maciota",false):
			push_error("Interior transition failed"); quit(1); return
		var origin: Vector3 = world.maciota_place.interior_origin
		route = PackedVector3Array([origin+Vector3(0,0,3.2),origin+Vector3(1,0,1.5),origin+Vector3(3.4,0,1.5),origin+Vector3(3.4,0,-.55),origin+Vector3(3.4,0,1.5),origin+Vector3(1,0,1.5)])
	else:
		var origin: Vector3 = world.player.position
		route = PackedVector3Array([origin+Vector3(-3,0,0),origin+Vector3(3,0,0)])
	if driving_mode:
		var car: CharacterBody3D = world.driving.car
		driving_route = world.production.traffic_routes.route_near(car.position)
		if driving_route == null: push_error("No native driving route"); quit(1); return
		var distance := driving_route.get_closest_offset(car.position)
		var point := driving_route.sample_baked(distance,true)
		var direction := driving_route.sample_baked(distance+1,true)-point
		var free_pose := false
		for attempt in 16:
			var probe := fposmod(distance+attempt*6,driving_route.get_baked_length())
			point = driving_route.sample_baked(probe,true)
			direction = driving_route.sample_baked(minf(probe+1,driving_route.get_baked_length()),true)-point
			if world.production.vehicle_position_clear(car,point+Vector3.UP*.12,atan2(-direction.x,-direction.z)):
				free_pose = true
				break
		if not free_pose: push_error("Native driving route has no clear vehicle start"); quit(1); return
		car.traffic = false
		car.place(point+Vector3.UP*.12,atan2(-direction.x,-direction.z))
		var entered := false
		for side in [-1,1]:
			var approach := car.to_global(Vector3(side*(car.half_width+.65),.04,.15))
			if not world.session.position_clear(approach): continue
			world.player.teleport(approach)
			await physics_frame
			if world.driving.interact(): entered=true; break
		if not entered:
			push_error("Native car entry failed: health=%s locked=%s car=%s speed=%s position=%s"%[world.gameplay.health,world.player.input_locked,car.vehicle_id,car.speed,car.position]); quit(1); return
		# O embarque usa Tween em segundos; frames renderizados variam com FPS.
		# Mantem o prazo funcional de 4 s, respeitando caminhos de porta mais longos.
		var presentation = world.driving.transition
		var planned_duration := float(presentation.duration) if is_instance_valid(presentation) else 0.0
		var boarding_budget_usec := int(maxf(4.0,planned_duration+.5)*1000000.0)
		var boarding_started := Time.get_ticks_usec()
		var boarding_frames := 0
		while Time.get_ticks_usec()-boarding_started < boarding_budget_usec:
			if car.controlled and not world.driving.is_body_transition_active(): break
			await physics_frame
			boarding_frames += 1
		var boarding_elapsed_ms := float(Time.get_ticks_usec()-boarding_started)/1000.0
		if not car.controlled or world.driving.is_body_transition_active() or not world.player.seated:
			var transition = world.driving.transition
			var phase := str(transition.phase) if is_instance_valid(transition) else "none"
			var progress := float(transition.progress) if is_instance_valid(transition) else -1.0
			push_error("Embarque incompleto antes da medicao: elapsed_ms=%s budget_usec=%s planned_s=%s physics_frames=%s controlled=%s active=%s seated=%s phase=%s progress=%s max_fps=%s"%[boarding_elapsed_ms,boarding_budget_usec,planned_duration,boarding_frames,car.controlled,world.driving.is_body_transition_active(),world.player.seated,phase,progress,Engine.max_fps])
			quit(1)
			return
		print("MEASUREMENT_BOARDING elapsed_ms=%s planned_s=%s budget_usec=%s physics_frames=%s controlled=%s seated=%s"%[boarding_elapsed_ms,planned_duration,boarding_budget_usec,boarding_frames,car.controlled,world.player.seated])
		car.external_input = true
	if combat_mode:
		world.session.state.grant_weapon("ak47")
		world.session.state.add_ammo("ak47",600)
		world.session.state.equip_weapon("ak47")
		world.gameplay.register_crime(150,world.player.position)
	started = Time.get_ticks_usec()
	previous = started

func _process(delta: float) -> bool:
	if started != 0 and combat_mode:
		# Explicit stress fixture: replenish health to keep the real combat workload active.
		# Death/respawn is validated separately, not hidden behind an FPS result.
		if world.gameplay.health > 0 and not world.session.modal:
			combat_alive_seconds += delta
			world.gameplay.health = 100
		fire_clock += delta
		if fire_clock >= .2:
			fire_clock = 0
			if world.gameplay.fire_at(world.player.position+Vector3(8,0,-2)): combat_shots += 1
			if world.session.state.get_ammo("ak47").magazine == 0: world.gameplay.reload_weapon()
	return super._process(delta)

func finish() -> void:
	var summary := stats(samples)
	var report := {"label":label,"scene":"native_harbor_v2","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"population":world.people.size(),"requested_population":world.production.requested_population,"cars":world.production.vehicles.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"summary":summary,"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"warmup_intervals_ms":cold,"cpu_ms":cpu,"physics_ms":physics,"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"player_distance":world.player.travelled,"notes":"Native Harbor production geometry. Different scene from slice baseline; compare against later native runs at same location and settings."}
	report.driving = driving_mode
	report.combat = combat_mode
	report.ablate_traffic = ablate_traffic
	report.ablate_population = ablate_population
	report.measured_start_usec = measured_started
	report.runtime_costs = world.get_meta("perf_costs",[])
	if combat_mode:
		report.combat_health_replenished = true
		report.combat_alive_seconds = combat_alive_seconds
		report.combat_shots = combat_shots
		report.combat_final_health = world.gameplay.health
		report.combat_workload_valid = combat_alive_seconds>=34.0 and combat_shots>30 and not world.session.modal
	if driving_mode: report.vehicle_distance = world.driving.car.distance_travelled
	await RenderingServer.frame_post_draw
	var output_dir := evidence_dir if not evidence_dir.is_empty() else "res://evidence"
	root.get_texture().get_image().save_png(output_dir.path_join(label+".png"))
	var file := FileAccess.open(output_dir.path_join(label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BENCHMARK ",label," ",JSON.stringify(summary))
	var workload_valid: bool = not combat_mode or report.combat_workload_valid
	world.free()
	await process_frame
	if not workload_valid: push_error("Combat benchmark invalid: sustained live workload was interrupted")
	quit(0 if workload_valid else 1)
