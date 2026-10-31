extends SceneTree
const F := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ROUTES := preload("res://runtime/regional/RegionalCoachRoute.gd")
var world
var folder := ""
var checks := 0
var failures := 0
var baseline := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("REGIONAL_COACH ","PASS " if ok else "FAIL ",label)
func run() -> void:
	create_timer(1300).timeout.connect(func(): push_error("REGIONAL_COACH timeout"); quit(3))
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(7102026)
	baseline = "--baseline" in OS.get_cmdline_user_args()
	folder = F.output_dir("regional-session-baseline" if baseline else "regional-session")
	var snapshot := F.full_snapshot(ROUTES.station("harbor").arrival + Vector3.UP * .12, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var save_path := F.write_fixture(folder,"save.json",snapshot)
	if save_path.is_empty(): quit(2); return
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	if "--night" in OS.get_cmdline_user_args():
		world.session.weather.set_process(false)
		world.session.weather.time_of_day = .88
		world.session.weather.weather_state = 0
		world.session.weather._update()
	if "--accelerated" in OS.get_cmdline_user_args():
		# Preserva o passo de simulação nativo de 1/60 ao percorrer rotas longas.
		# Esta rodada funcional nunca é usada como benchmark de desempenho.
		Engine.time_scale = 4
		Engine.physics_ticks_per_second = 240
		print("REGIONAL_COACH accelerated functional run: 4x, 240 physics ticks")
	check(world.production.store.path == save_path and not world.production.save_invalid,"isolated valid checkpoint")
	world.production.no_save = false
	await create_timer(1).timeout
	if baseline:
		for id in ["harbor","mountain","desert"]:
			if world.session.state.region_id != id:
				check(world.production.travel(id,ROUTES.station(id).arrival),"baseline transfer admitted "+id)
				while world.production.travel_busy: await process_frame
			await create_timer(.8).timeout
			print("REGIONAL_BASELINE ",id," region=",world.session.state.region_id," point=",world.player.position," action=",world.session.nearest())
			check(world.session.state.region_id == id,"baseline stop has physical support "+id)
			await photo("stop-"+id)
		finish()
		return
	var service = world.session.regional_coach
	check(service != null,"regional service connected to ordinary session")
	if service == null: finish(); return
	check(world.session.nearest().get("id","") == "regional_coach","Harbor stop exposes regional bus action")
	var complete: Dictionary = world.session.state.campaign.snapshot()
	world.session.state.campaign.restore_snapshot(F.prefix(0))
	check(not service.station_available(ROUTES.station("desert")),"desert locked before final campaign")
	check(service.station_available(ROUTES.station("mountain")),"ice station available before desert gate")
	check(not service.travel_to("desert",true),"quick travel cannot bypass campaign")
	world.session.state.campaign.restore_snapshot(complete)
	world.gameplay.stars = 1
	check(service.nearest_action().is_empty(),"wanted player cannot start regional journey")
	world.gameplay.stars = 0
	check(await world.session.interact(),"ordinary interaction opens destination UI")
	check(service.menu_open and world.session.modal,"destination menu owns input")
	check(not world.gameplay.attack_allowed() and not world.gameplay.cycle_weapon(1),"destination menu blocks combat and weapon wheel")
	service.close_station_menu()
	check(not world.session.modal and not world.player.input_locked,"cancel restores controls")
	# A blocked platform cannot commit a region or leave the passenger stranded.
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6,4,10)
	collision.shape = box
	blocker.add_child(collision)
	blocker.position = ROUTES.station("mountain").arrival + Vector3.UP*1.5
	world.add_child(blocker)
	await physics_frame
	check(service.travel_to("mountain",true),"blocked destination still uses checked admission")
	while service._boarding or service.landing: await process_frame
	check(service.riding and world.session.state.region_id == "harbor","blocked arrival preserves origin and passenger ownership")
	check(not world.session.save_block_reason().is_empty(),"failed arrival cannot save hidden passenger")
	blocker.queue_free()
	await physics_frame
	service.skip_trip()
	while service.riding: await process_frame
	await create_timer(.4).timeout
	check(world.session.state.region_id == "mountain" and not world.player.input_locked,"cleared arrival recovers without a second boarding")
	await trip("harbor",true)
	var full := "--full-route" in OS.get_cmdline_user_args()
	await trip("mountain",not full)
	await trip("desert",true)
	await trip("harbor",not full or "--ice-only" in OS.get_cmdline_user_args())
	await trip("desert",true)
	await trip("mountain",true)
	await trip("harbor",true)
	check(world.session.save_game(),"arrival saves successfully to isolated file")
	var saved := preload("res://runtime/SaveStore.gd").read_valid(save_path)
	check(not saved.is_empty() and saved.region_id == "harbor","completed arrival persisted")
	check(world.player.visible and world.player.collision_layer != 0 and world.player.is_physics_processing(),"player visibility collision and physics restored")
	check(not service.busy() and not is_instance_valid(service.train),"coach and passenger ownership released")
	# Cancellation during the boarding fade must invalidate its pending coroutine.
	check(service.travel_to("mountain",false),"recovery boarding admitted")
	service.cancel_for_transition()
	await create_timer(.8).timeout
	check(not service.busy() and not is_instance_valid(service.train) and not world.player.input_locked,"cancelled boarding cannot recreate a coach")
	# Exercita o dono comum de resgate depois de dano num ônibus ocupado.
	check(service.travel_to("mountain",false),"destruction recovery boarding admitted")
	while service._boarding: await process_frame
	if is_instance_valid(service.train):
		service.train.health = 0
		await physics_frame
		await physics_frame
		check(world.session.rescue_pending and not service.riding and not is_instance_valid(service.train),"destroyed coach transfers ownership to rescue")
		var recovery_deadline := Time.get_ticks_msec()+30000
		while (world.session.rescue_pending or world.session.respawn_busy) and Time.get_ticks_msec()<recovery_deadline: await process_frame
		check(not world.session.rescue_pending and world.gameplay.health>0 and not world.player.input_locked,"rescue completes after coach destruction")
		check(world.player.visible and world.player.collision_layer!=0 and world.player.is_physics_processing(),"rescue restores real actor collision and processing")
	else:
		check(false,"destruction fixture requires admitted coach")
	finish()
func trip(id: String, instant: bool) -> void:
	var service = world.session.regional_coach
	var origin: String = world.session.state.region_id
	check(await world.session.interact(),"destination menu "+origin+" -> "+id)
	check(service.travel_to(id,instant),"journey admitted "+origin+" -> "+id)
	var began := Time.get_ticks_msec()
	var photographed := false
	var pause_checked := false
	var stalled_reported := false
	var seen_progress := false
	var start_distance := 0.0
	var frames: Array[float] = []
	var measurement_start := 0
	var previous_frame := 0
	var measure := "--measure-ride" in OS.get_cmdline_user_args()
	var report_at := began
	while service.riding and Time.get_ticks_msec()-began < 580000:
		await process_frame
		var now := Time.get_ticks_usec()
		if measurement_start > 0 and previous_frame > 0 and now-measurement_start >= 8000000 and now-measurement_start < 38000000:
			frames.append(float(now-previous_frame)/1000.0)
		previous_frame = now
		if Time.get_ticks_msec()-report_at > 15000:
			report_at = Time.get_ticks_msec()
			print("REGIONAL_PROGRESS ",origin," -> ",id," distance=",service.distance," length=",service.route_length," position=",world.player.position," speed=",service.speed)
			if is_instance_valid(service.train): print("REGIONAL_BLOCKER ",service.train.blocker," junction=",service.train.junction_wait," stall=",service._stalled_seconds)
		if not instant and not service._boarding and not service.landing and is_instance_valid(service.train):
			if not photographed:
				check(not world.session.save_block_reason().is_empty(),"saving blocked aboard")
				check(not world.gameplay.attack_allowed() and not world.gameplay.cycle_weapon(1),"ride blocks combat and weapon wheel")
				check(not world.gameplay.fire_at(world.player.position+Vector3.FORWARD*10),"direct shot rejected aboard")
				check(service.train.passengers.size() >= 6,"passengers present aboard")
				start_distance = service.train.route_distance
				await photo(origin+"-"+id+"-interior")
				service.set_camera_mode(1)
				await photo(origin+"-"+id+"-exterior")
				photographed = true
			if service.train.route_distance > start_distance+25: seen_progress = true
			if seen_progress and not pause_checked:
				var paused_at: float = service.train.route_distance
				paused = true
				await create_timer(.3,true).timeout
				check(is_equal_approx(service.train.route_distance,paused_at),"pause holds the physical coach")
				paused = false
				pause_checked = true
				# A cronometragem começa depois da pausa intencional e das fotos síncronas;
				# o intervalo da corrotina delas não é amostra de tempo de quadro renderizado.
				measurement_start = Time.get_ticks_usec()
				previous_frame = 0
			if "--short-ride" in OS.get_cmdline_user_args() and seen_progress and (not measure or now-measurement_start >= 38000000):
				service.set_camera_mode(0)
				await photo(origin+"-"+id+"-interior-moving")
				service.skip_trip()
			elif service._stalled_seconds > 90 and not stalled_reported:
				stalled_reported = true
				check(false,"physical trip made no progress for 90 simulation seconds")
				var obstacle: Object = service.train.blocker
				if is_instance_valid(obstacle):
					print("REGIONAL_STALL_DETAIL ",obstacle.get_path()," script=",obstacle.get_script()," position=",obstacle.get("global_position")," traffic=",obstacle.get("traffic")," speed=",obstacle.get("speed")," heading=",obstacle.get("rotation")," metadata=",obstacle.get_meta_list())
				await photo("blocked-"+origin+"-"+id)
				service.skip_trip()
	if service.riding:
		check(false,"journey exceeded finite limit: "+origin+" -> "+id+" distance="+str(service.distance))
		service.skip_trip()
		while service.riding: await process_frame
	await create_timer(.8).timeout
	if measure and not frames.is_empty():
		var sorted := frames.duplicate()
		sorted.sort()
		var total := 0.0
		var over33 := 0
		var over66 := 0
		for frame in frames:
			total += frame
			if frame > 33.3: over33 += 1
			if frame > 66.7: over66 += 1
		var report := {"fps":frames.size()*1000.0/total,"seconds":total/1000.0,"frames_ms":frames,
			"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],
			"max_ms":sorted[-1],"over33":over33,"over66":over66,"gpu":RenderingServer.get_video_adapter_name(),
			"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),
			"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"time_scale":Engine.time_scale,
			"note":"Current rendered journey; no isolated historical baseline, regression remains inconclusive."}
		FileAccess.open(folder.path_join(origin+"-"+id+"-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
		print("REGIONAL_CURRENT_FRAMES ",origin," -> ",id," fps=",report.fps," p95=",report.p95_ms," p99=",report.p99_ms)
	check(world.session.state.region_id == id,"arrival committed "+id)
	check(world.player.position.distance_to(ROUTES.station(id).arrival) < 4,"arrival remains at bus station "+id)
	check(world.session.position_clear(world.player.position),"arrival has clear body and support "+id)
	check(not world.player.input_locked and not paused and not world.session.modal,"controls restored "+id)
	if not instant: check(photographed and seen_progress,"physical road travel with passengers "+origin+" -> "+id)
	await photo("arrival-"+id)
func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func finish() -> void:
	print("REGIONAL_COACH_RESULT checks=",checks," failures=",failures," evidence=",folder)
	if is_instance_valid(world): world.free()
	await process_frame
	quit(0 if failures == 0 else 1)
