extends "res://tests/measure.gd"
var control := false
var stock_count := 0
var guard_count := 0
var loading_previous := 0
var loading_frames: Array[float]=[]
func _process(delta: float) -> bool:
	if loading_previous>0:
		var now := Time.get_ticks_usec()
		loading_frames.append(float(now-loading_previous)/1000.0)
		loading_previous=now
	return super._process(delta)
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Rendered benchmark required"); quit(2); return
	control="--without-guards" in OS.get_cmdline_user_args()
	label="garage-guards-control" if control else "garage-guards-product"
	seed(9212026)
	loading_previous=Time.get_ticks_usec()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.people.size()>=world.production.requested_population: break
	if world.session==null or not world.session.ready_for_play or not world.production.no_save: push_error("Unsafe or incomplete benchmark setup"); quit(1); return
	if world.people.size()<world.production.requested_population: push_error("Population not reached"); quit(1); return
	world.session.weather.time_of_day=.1
	world.session.state.world_state.time=.1
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically=true
	world.player.speed=1.5
	if control:
		var guards=world.session.garage_rewards.guards
		world.session.garage_rewards.guards=null
		guards.queue_free()
	if not await world.session.enter_place("port_boss_garage",false): push_error("Boss garage entry failed"); quit(1); return
	for i in 60: await physics_frame
	for car in world.session.garage_rewards.cars.values():
		if is_instance_valid(car) and car.visible and car.get_meta("garage_place","")=="port_boss_garage": stock_count+=1
	guard_count=0 if control else world.session.garage_rewards.guards.actors.size()
	if stock_count!=5 or guard_count!=(0 if control else 2): push_error("Incomplete room: cars=%d guards=%d"%[stock_count,guard_count]); quit(1); return
	var origin: Vector3=world.session.room.global_position
	world.player.teleport(origin+Vector3(-4,.04,6))
	route=PackedVector3Array([origin+Vector3(4,.04,6),origin+Vector3(-4,.04,6)])
	for point in route:
		if not world.session.position_clear(point): push_error("Benchmark route blocked"); quit(1); return
	world.diagnostic_label.hide()
	loading_previous=0
	started=Time.get_ticks_usec()
	previous=started
func finish() -> void:
	var report := {"label":label,"scene":"res://Main.tscn","place":"port_boss_garage","control_removes_only_guards":control,"stock_vehicles":stock_count,"guards":guard_count,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"population":world.people.size(),"requested_population":world.production.requested_population,"traffic_enabled":world.production.traffic_routes!=null,"time_of_day":world.session.weather.time_of_day,"camera_position":str(world.camera.position),"camera_size":world.camera.size,"camera_locked":world.camera.locked,"summary":stats(samples),"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"warmup_intervals_ms":cold,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"player_distance":world.player.travelled,"guard_positions":[],"guard_source":"world/harbor/PortBossGarage.gd;HarborPortSecurity.gd;police/PoliceOfficer.gd","notes":"Neutral two guards, original room camera, five stock cars; no combat cost claimed. Fixture-only control removes guards, no product settings changed."}
	report.first_visit=stats(loading_frames)
	report.first_visit_intervals_ms=loading_frames
	if not control:
		for actor in world.session.garage_rewards.guards.actors: report.guard_positions.append(str(actor.global_position-world.session.room.global_position))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")
	var file := FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("GARAGE_BENCHMARK ",label," ",JSON.stringify(report.summary))
	world.queue_free()
	await process_frame
	quit()
