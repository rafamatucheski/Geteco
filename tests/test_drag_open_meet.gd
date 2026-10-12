extends SceneTree
## Real Main/.NET, real NPC and player motion. Only travel/checkpoint and input
## are fixtures. Save path is isolated; no scripted crossing or fake result.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/desert/DesertLayout.gd")
var world
var failures: Array[String] = []
var checks := 0
var output := ""
var samples: Array[float] = []
var stamp := 0
var recording := false
var metrics := {}
var temporal: Node

class InputShield extends Node:
	# A rendered automated run must not consume desktop typing/controller input.
	# Test actions below call the actual public activity/boarding methods.
	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()
	func _physics_process(_delta: float) -> void:
		for action in InputMap.get_actions(): Input.action_release(action)

func _initialize() -> void:
	create_timer(360).timeout.connect(func(): push_error("OPEN_DRAG timeout"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp>0: samples.append(float(now-stamp)/1000.0)
	stamp = now
	return false

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("OPEN_DRAG ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func frames(count: int) -> void:
	for i in count: await physics_frame

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func capture_rear_number(car: Node3D, number: Node3D) -> void:
	if DisplayServer.get_name()=="headless": return
	var previous := root.get_camera_3d()
	var close := Camera3D.new()
	world.add_child(close)
	close.global_position = car.to_global(Vector3(0,2.2,4.8))
	close.look_at(number.global_position,Vector3.UP)
	close.fov = 42.0
	close.make_current()
	await capture("rear-window-number")
	previous.make_current()
	close.queue_free()

func measure(label: String) -> void:
	samples.clear(); stamp = Time.get_ticks_usec(); recording = true
	await create_timer(30.0).timeout
	recording = false
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		total += value
		if value>33.3: over33 += 1
		if value>66.7: over66 += 1
	metrics[label] = {"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50":sorted[int(sorted.size()*.50)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples.duplicate()}
	print("OPEN_DRAG_METRICS ",label," fps=",metrics[label].fps," p95=",metrics[label].p95," p99=",metrics[label].p99)
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"\t"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output = FIXTURE.output_dir("open-drag")
	print("OPEN_DRAG_OUTPUT ",output)
	var at := LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary = FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path: String = FIXTURE.write_fixture(output,"checkpoint.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	var shield := InputShield.new()
	shield.process_physics_priority = -100
	root.add_child(shield)
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if not check(world.session!=null and world.session.ready_for_play,"Main session ready"): finish(); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"native .NET routes active")
	var session = world.session
	var race = session.desert.drag
	var meet = race.open_meet
	if "--benchmark" in OS.get_cmdline_user_args() or "--night" in OS.get_cmdline_user_args():
		session.weather.set_process(false)
		session.weather.time_of_day = .9 if "--night" in OS.get_cmdline_user_args() else .45
		session.weather._update()
	world.gameplay.god_mode = true
	var car = world.production.spawn_vehicle("desert_mirage",at+Vector3(0,0,-6),-PI*.5)
	if not check(is_instance_valid(car),"player car admitted outside strip"): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	await frames(4)
	check(world.driving.interact(),"ordinary car boarding")
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not check(world.driving.occupied and not car.input_locked,"boarding returns control"): finish(); return
	if "--number-only" in OS.get_cmdline_user_args():
		race.OPEN_ROSTER.attach_number(car,27)
		check(car.has_node("DragEntryNumber/RearWindowNumber"),"rear number fits boarded car")
		await capture_rear_number(car,car.get_node("DragEntryNumber/RearWindowNumber"))
		finish(); return
	if "--benchmark" in OS.get_cmdline_user_args():
		if DisplayServer.get_name()=="headless": quit(2); return
		meet.enabled = false
		await frames(2)
		await create_timer(8.0).timeout
		metrics.environment = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"size":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"limit":Engine.max_fps}
		await measure("before_open_meet")
		meet.enabled = true
		# Let the whole finite fleet arrive and complete its first heat before
		# measuring the circulating steady state (initial admission is separate).
		await create_timer(60.0).timeout
		await measure("with_open_meet")
		if "--benchmark-only" in OS.get_cmdline_user_args():
			race.OPEN_ROSTER.attach_number(car,27)
			await capture_rear_number(car,car.get_node("DragEntryNumber/RearWindowNumber"))
			await capture("ambient-final")
			finish(); return
	if "--temporal" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		temporal = preload("res://tests/capture/DesertDragTemporalCapture.gd").new()
		root.add_child(temporal)
		check(temporal.begin(world,race,output.path_join("temporal")),"continuous rendered visitor evidence starts")
		temporal.segment = "open_meet_night" if "--night" in OS.get_cmdline_user_args() else "open_meet_day"
		await create_timer(31.0).timeout
		var report: Dictionary = temporal.stop()
		check(str(report.failure).is_empty() and float(report.duration_seconds)>=30.0,"visitor evidence records at least 30 seconds")
	for i in 3600:
		await physics_frame
		if meet.phase=="racing" and meet.clock>.75 and meet.waiting.size()==2: break
	check(meet.phase=="racing" and meet.heat.size()==2 and meet.waiting.size()==2,"two autonomous racers and a physical waiting pair")
	for entry in meet.heat+meet.waiting+meet.transit: print("OPEN_DRAG_CAR ",entry.identity," ",entry.get("routing","")," ",entry.car.global_position," speed=",entry.car.speed," waypoint=",entry.get("waypoint",-1))
	if not failures.is_empty(): finish(); return
	check(meet.heat.all(func(e): return e.drive.speed_mps>0.0 and race._offset(e.car.global_position)>0.0),"NPCs move using collision bodies and actual drivetrain")
	check(meet.waiting.all(func(e): return race._offset(e.car.global_position)<-8.0 and e.car.has_node("DragEntryNumber")),"numbered queue stays behind the grid")
	var original_racers: Array = meet.heat.map(func(e): return e.car.get_instance_id())
	var maximum_serial: int = meet.visitor_serial+meet.MAX_CARS-meet.heat.size()-meet.waiting.size()-meet.transit.size()
	await capture("ambient")
	if not check(race.perform("board"),"board opens during autonomous heat"):
		print("OPEN_DRAG_BOARD_BLOCK reason=",race.start_block_reason()," at=",car.global_position," modal=",session.modal," nearest=",race.nearest_action())
		finish(); return
	race.board_controller.board.open_meet_button.pressed.emit()
	check(race.board_controller.open_board_panel.is_visible_in_tree(),"board opens free heats")
	await capture("free-board")
	race.board_controller.open_board_panel.queue_button.pressed.emit()
	check(not session.modal and meet.ticket().position==2,"queue action registers exactly second position")
	check(car.has_node("DragEntryNumber") and car.get_meta("drag_entry_number",0)==27,"player receives physical entry number 27")
	var number: Node3D = car.get_node("DragEntryNumber/RearWindowNumber")
	check(number.position.z>0.0 and number.basis.z.z>0.0,"number is attached to rear-facing glass, not the doors")
	await capture("registered")
	await capture_rear_number(car,number)
	check(not meet.request("open_ivo",true),"duplicate registration cannot extend the queue")
	check(not race.save_block_reason().is_empty(),"temporary queue cannot leak into a save")
	var before: Dictionary = race.snapshot().duplicate(true)
	var balance: int = session.state.economy.balance
	var queued_at := Time.get_ticks_msec()
	var count_before: int = meet.heats_completed
	var max_cars := 0
	while not race.active and Time.get_ticks_msec()-queued_at<90000:
		max_cars = maxi(max_cars,meet.heat.size()+meet.waiting.size()+meet.transit.size())
		if meet.pending.is_empty(): break
		await physics_frame
	check(race.active and race.OPEN_ROSTER.CARS.has(race.rival_id),"queue admits player against non-ranked visitor")
	check(meet.heats_completed-count_before==2,"current heat and just one waiting heat precede second position")
	check(max_cars<=meet.MAX_CARS and meet.heat.is_empty(),"bounded population and exclusive track ownership")
	print("OPEN_DRAG_ADMISSION pending=",meet.pending," reason=",meet.last_admission_reason," phase=",meet.phase," car_locked=",car.input_locked," car_speed=",car.speed," car_position=",car.global_position)
	print("OPEN_DRAG_WAIT seconds=",float(Time.get_ticks_msec()-queued_at)/1000.0)
	if not race.active: finish(); return
	await capture("player-staging")
	var deadline := Time.get_ticks_msec()+60000
	var braking_without_skid := false
	var bad_skid_samples := 0
	var good_brake_samples := 0
	var recording_brakes := false
	var audio_capture: AudioEffectRecord
	if "--audio" in OS.get_cmdline_user_args():
		audio_capture = AudioEffectRecord.new()
		audio_capture.format = AudioStreamWAV.FORMAT_16_BITS
		AudioServer.add_bus_effect(0,audio_capture,0)
	while race.active and Time.get_ticks_msec()<deadline:
		race._throttle_override = .54 if race.phase=="staging" else 1.0
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		if race.phase=="braking" and car.speed>10.0 and car.speed<30.0:
			braking_without_skid = braking_without_skid or float(car.get_meta("drag_service_brake_slip",1.0))<.15
			if float(car.get_meta("drag_service_brake_slip",1.0))<.15:
				good_brake_samples += 1
				var skid = car.effects.tire_effects.skid_audio
				if is_instance_valid(skid) and skid.playing:
					if bad_skid_samples < 3: print("OPEN_DRAG_SKID slip=",car.get_meta("drag_service_brake_slip")," probe=",car.effects.tire_effects._probe_clock," lateral=",absf(car.horizontal_velocity.dot(car.global_basis.x))," burnout=",car.burnout_strength()," speed=",car.speed)
					bad_skid_samples += 1
		if audio_capture!=null and not recording_brakes and is_finite(float(race.racers[0].finish)):
			audio_capture.set_recording_active(true)
			recording_brakes = true
		await physics_frame
	if audio_capture!=null:
		audio_capture.set_recording_active(false)
		var clip := audio_capture.get_recording()
		if clip!=null: clip.save_to_wav(ProjectSettings.globalize_path(output.path_join("braking.wav")))
		AudioServer.remove_bus_effect(0,0)
	check(not race.active and race.last_result.get("finished",false) and race.last_result.get("casual",false),"real 800m crossing and braking produce a free heat result")
	check(race.snapshot()==before and session.state.economy.balance==balance,"free result changes neither ranking nor reward balance")
	check(braking_without_skid,"progressive stop does not request a continuous locked-tire loop")
	check(good_brake_samples>10 and bad_skid_samples==0,"actual tire audio remains stopped during rolling service braking")
	await frames(3)
	await capture("free-result")
	check(session.modal and race.board_controller.results_layer.visible,"free result offers normal recovery actions")
	check(await race.return_to_entry(),"safe physical entry destination after free heat")
	session.close_menu()
	var returned_to_queue := false
	for i in 2400:
		for entry in meet.heat+meet.waiting+meet.transit:
			if entry.car.get_instance_id() in original_racers and str(entry.get("routing",""))=="queue": returned_to_queue = true
		if returned_to_queue: break
		await physics_frame
	check(returned_to_queue and meet.visitor_serial<=maximum_serial,"same car physically returns to the queue without respawning")
	for entry in meet.heat+meet.waiting+meet.transit: print("OPEN_DRAG_RETURN ",entry.identity," ",entry.get("routing","")," ",entry.car.global_position," speed=",entry.car.speed," waypoint=",entry.get("waypoint",-1))
	check(meet.request("open_bruno",false),"next-opening registration works after a finish")
	check(meet.ticket().position==1,"immediate option has no extra waiting heat")
	meet.cancel_ticket(false)
	check(meet.pending.is_empty() and not car.input_locked,"cancelling restores unrestricted driving")
	meet.enabled = false
	await frames(3)
	check(meet.heat.is_empty() and meet.waiting.is_empty() and meet.transit.is_empty() and not car.has_node("DragEntryNumber"),"leaving visit releases NPCs and temporary player number")
	finish()

func finish() -> void:
	print("OPEN_DRAG_DONE checks=",checks," failures=",failures)
	if is_instance_valid(world): world.free()
	quit(0 if failures.is_empty() else 1)
