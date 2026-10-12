extends "res://tests/test_biarticulated_theft_session.gd"
func button(action: String) -> void:
	var press := InputEventAction.new(); press.action=action; press.pressed=true
	Input.parse_input_event(press); await process_frame
	var release := InputEventAction.new(); release.action=action; release.pressed=false
	Input.parse_input_event(release); await process_frame
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(300).timeout.connect(func(): push_error("BUS_DRIVER_SESSION timeout"); quit(2))
	for action in InputMap.get_actions():
		if action not in ["bus_driver_shift","bus_doors","exit_vehicle"]: InputMap.action_erase_events(action)
	folder="res://evidence/biarticulated/driver-20261010"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)); root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene=world
	while world.session==null or not world.session.ready_for_play: await process_frame
	var ops=world.production.urban_transit.urban_service
	while not ops.prepared: await physics_frame
	var job=ops.driver_work
	var bus=ops.fleet[0]
	ops.set_physics_process(false)
	for other in ops.fleet: other.set_active(false)
	bus.service_stop=1; bus.route_distance=ops.stops[1].offset
	bus._apply_poses(ops.path_poses.at(bus.route_distance),false)
	bus.service_state="exchange"; bus.dwell=1000; bus.speed=0; bus.set_doors(1)
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	world.player.teleport(bus.driver_door_anchor(1)+Vector3.UP*.45)
	world.production._update_physical_residency(world.player.position)
	world.camera.target=bus; world.camera.target_size=30; world.camera.initialized=false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day=.35; world.session.weather.weather_state=0
	world.session.weather._update(); world.session.weather.set_process(false)
	ops.refresh_presence(); bus.set_active(true); ops.gate(1,true)
	for frame in 120: await physics_frame
	ops.set_physics_process(true)
	check(job.nearby_bus()==bus,"Driver role is offered at the real front door")
	var crime: int=world.gameplay.crime_points
	await button("bus_driver_shift")
	check(world.driving.occupied and world.driving.car==bus,"B enters the scheduled bus as its operator")
	if not world.driving.occupied: quit(1); return
	check(world.driving.transition.carjacking==null,"Driver role does not forcibly extract an NPC")
	await wait_body()
	check(bus.controlled and bus.driver_shift and not bus.stolen,"Peaceful ownership admits manual driving")
	check(world.gameplay.crime_points==crime,"Assuming the line does not report theft")
	check(bus.door_amount==0,"Boarding leaves the bus ready for manual door control")
	await photo("driver")
	var cash: int=world.session.state.economy.balance
	var initial_count: int=bus.passengers.size()
	await button("bus_doors")
	check(bus.door_amount==1,"O opens the doors at the indicated station")
	var parked: Vector3=bus.global_position
	Input.action_press("accelerate")
	for frame in 30: await physics_frame
	Input.action_release("accelerate")
	check(bus.global_position.distance_to(parked)<.01,"Open doors prevent the real accelerator from moving the bus")
	var deadline := Time.get_ticks_msec()+24000
	while not job._exchange_done and Time.get_ticks_msec()<deadline: await process_frame
	if not job._exchange_done:
		for person in ops.people:
			if person.stop==bus.service_stop: print("DRIVER_QUEUE ",person.id," ",person.phase," ",person.actor.global_position if is_instance_valid(person.actor) else Vector3.INF)
	check(job._exchange_done,"Real passenger exchange finishes through the open gate")
	check(bus.passengers.size()>initial_count,"NPC passengers actually board the player-operated vehicle")
	if "--measure-driver" in OS.get_cmdline_user_args():
		var samples: Array[float]=[]
		var began := Time.get_ticks_usec()
		var last := began
		while Time.get_ticks_usec()-began<38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-began>=8000000: samples.append((now-last)/1000.0)
			last=now
		var report := {"summary":stats(samples),"frames_ms":samples,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"scenario":"player bus driver, passenger exchange, doors open, normal Main traffic"}
		FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report))
		print("PLAYER_BUS_DRIVER_PERF ",report.summary)
	await photo("boarding")
	var served: int=bus.service_stop
	await button("bus_doors")
	check(bus.door_amount==0 and bus.work_state.stops==1,"Closing completed boarding records one served stop")
	check(world.session.state.economy.balance>cash,"Serving the stop pays the real wallet")
	check(bus.work_state.next_stop!=(served),"The minimap/HUD objective advances to a different stop")
	var paid: int=world.session.state.economy.balance
	await button("bus_doors")
	check(bus.door_amount==0 and world.session.state.economy.balance==paid,"Button spam at the previous stop cannot duplicate payment")
	var before: Vector3=bus.global_position
	Input.action_press("accelerate")
	for frame in 180: await physics_frame
	Input.action_release("accelerate"); Input.action_press("handbrake")
	for frame in 120: await physics_frame
	Input.action_release("handbrake")
	check(bus.global_position.distance_to(before)>2,"Player input drives away after closing the doors")
	if "--next-stop" in OS.get_cmdline_user_args():
		var until := Time.get_ticks_msec()+30000
		while Time.get_ticks_msec()<until and not job.docked(bus):
			var gap: Vector3=job.target_position()-bus.global_position
			var remaining: float=gap.dot(-bus.global_basis.z)
			if remaining>maxf(1.0,bus.speed*bus.speed/11.0+.45):
				Input.action_release("handbrake"); Input.action_press("accelerate")
			else:
				Input.action_release("accelerate"); Input.action_press("handbrake")
			await physics_frame
		Input.action_release("accelerate"); Input.action_release("handbrake")
		check(job.docked(bus),"Driving reaches and aligns the next authored station without teleporting")
		await button("bus_doors")
		var exchange_limit := Time.get_ticks_msec()+24000
		while not job._exchange_done and Time.get_ticks_msec()<exchange_limit: await process_frame
		await button("bus_doors")
		check(bus.work_state.stops==2,"A second real station boards/alights and pays independently")
	await photo("route")
	check(world.driving.leave(),"F allows the driver to leave the borrowed bus")
	await wait_body(); await process_frame
	check(not world.driving.occupied and not is_instance_valid(job.active_bus),"Leaving ends the active shift and restores walking")
	check(bus.driver_shift and not bus.stolen,"Borrowed bus remains parked without becoming a theft")
	check(world.gameplay.crime_points==crime,"The peaceful shift remains free of a theft report")
	var record: Dictionary=preload("res://runtime/FleetState.gd").capture(bus,"harbor")
	check(preload("res://runtime/FleetState.gd").validate(record) and record.bus_work.stops>=1,"Served-stop progress is captured for restoration")
	print("BUS_DRIVER_SESSION ",checks," checks ",failures," failures")
	world.queue_free(); await process_frame
	quit(1 if failures else 0)
