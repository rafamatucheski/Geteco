extends SceneTree
## Real .NET Main, rival dialogue, physical finish, deferred reward and cleanup.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const MEET := preload("res://runtime/desert/drag_meet/DragMeetTakeshi.gd")
const HONOR := preload("res://runtime/TakeshiHonor.gd")
var world
var output := ""
var failures: Array[String] = []
var checks := 0
var recording := false
var samples: Array[float] = []
var stamp := 0

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp>0: samples.append(float(now-stamp)/1000.0)
	stamp = now
	return false

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("TAKESHI_SESSION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	print("TAKESHI_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func press(label: String) -> bool:
	for child in world.session.column.get_children():
		if child is Button and child.text==label:
			child.pressed.emit()
			return true
	return false

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated .NET session required"): quit(2); return
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("takeshi-session")
	var at := MEET.POINT+Vector3(0,.1,2)
	var data := FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if not check(not path.is_empty(),"isolated valid desert checkpoint written"): quit(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"Main loads isolated checkpoint"): quit(1); return
	if not check(world.player.global_position.distance_to(at)<3.0,"checkpoint restores at the actual meet, outside existing solid props"): finish(); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"C# route backend active")
	var session = world.session
	var race = session.desert.drag
	world.gameplay.god_mode = true
	for i in 180:
		await physics_frame
		if is_instance_valid(race.takeshi_meet.actor) and is_instance_valid(race.takeshi_meet.parked): break
	check(is_instance_valid(race.takeshi_meet.actor) and is_instance_valid(race.takeshi_meet.parked),"Takeshi and his Supra occupy the meet")
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(MEET.POINT+Vector3(1,.9,0),MEET.POINT+Vector3(-1,.9,0),2))
	check(not hit.is_empty() and hit.collider==race.takeshi_meet.actor,"Takeshi has physical body collision")
	hit = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(MEET.CAR_POINT+Vector3(0,.8,3),MEET.CAR_POINT+Vector3(0,.8,-3),1))
	check(not hit.is_empty() and hit.collider==race.takeshi_meet.parked,"parked Supra has collision matching its bay")
	check(race.nearest_action().get("target","")=="takeshi" and race.perform("takeshi"),"nearby player can talk to optional Takeshi")
	check(session.modal and press("Voltar"),"optional interaction opens and closes normally")
	await capture("takeshi-meet")
	if "--measure" in OS.get_cmdline_user_args():
		if not check(DisplayServer.get_name()!="headless","frame measurement requires rendered Main"): finish(); return
		await create_timer(3).timeout
		stamp = Time.get_ticks_usec()
		recording = true
		await create_timer(30).timeout
		recording = false
		var sorted := samples.duplicate()
		sorted.sort()
		var total := 0.0
		var above33 := 0
		var above66 := 0
		for milliseconds in samples:
			total += milliseconds
			if milliseconds>33.3: above33 += 1
			if milliseconds>66.7: above66 += 1
		var metrics := {"scene":"Main.tscn","scenario":"takeshi_meet_current_no_baseline","engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":above33,"over66":above66,"raw_ms":samples}
		var metrics_file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
		metrics_file.store_string(JSON.stringify(metrics,"\t"))
		metrics_file.close()
		print("TAKESHI_METRICS ",JSON.stringify({"fps":metrics.fps,"p95":metrics.p95,"p99":metrics.p99,"max":metrics.max,"over33":above33,"over66":above66}))
	var player_car_point: Vector3 = race.staging_point+Vector3(0,.1,-6)
	world.production.region.set_focus(player_car_point)
	world.production.region.prepare_collision_at(player_car_point)
	for i in 8: await physics_frame
	var car = world.production.spawn_vehicle("desert_mirage",player_car_point,-PI*.5)
	if not check(is_instance_valid(car),"player sports car spawned"): quit(1); return
	preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car,race.rival_parts("takeshi"))
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	check(world.driving.interact(),"ordinary boarding starts")
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not check(world.driving.occupied and not car.input_locked,"boarding releases controls"): quit(1); return
	check(race.perform("board"),"ordinary drag board opens")
	race.board_controller.board.takeshi_button.pressed.emit()
	check(session.modal and press("Desafiar Takeshi"),"separate board action starts honor challenge")
	check(session.dialogue_open and not race.active,"Takeshi speaks before the timed race")
	await capture("takeshi-intro")
	session.dialogue_card.advance_button.pressed.emit()
	if not check(race.active and race.rival_id=="takeshi","continuing dialogue starts actual honor race"): quit(1); return
	check(race.racers[1].car.archetype=="supra_a80" and race.racers[1].drive.car_id=="supra_a80","opponent drives real Supra powertrain")
	check(race.racers[1].car.get_node("DragRivalDriver").get_meta("character_identity")=="takeshi","Takeshi sits at the wheel")
	await capture("takeshi-grid")
	var deadline := Time.get_ticks_msec()+80000
	while race.active and Time.get_ticks_msec()<deadline:
		race._throttle_override = .54 if race.phase=="staging" else 1.0
		race._nitro_override = race.phase=="racing"
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		await physics_frame
	check(not race.active and race.last_result.get("finished",false),"two physical cars reach actual finish")
	check(race.last_result.get("won",false),"full legal preparation and clean driving can beat Takeshi")
	check(HONOR.pending_reward(session.state.world_state),"physical victory unlocks exactly one pending honor choice")
	check(race.snapshot().wins.is_empty(),"optional duel leaves ordinary championship untouched")
	await create_timer(.3).timeout
	if not check(session.dialogue_open,"victory presents Takeshi's honor dialogue"): finish(); return
	await capture("takeshi-victory-dialogue")
	session.dialogue_card.advance_button.pressed.emit()
	await capture("takeshi-choice")
	check(press("Decidir depois") and HONOR.pending_reward(session.state.world_state),"postponing preserves pending choice")
	check(is_instance_valid(race.board_controller.results_layer) and race.board_controller.results_layer.visible,"postponing restores result and return actions")
	race.board_controller.results.buttons[1].pressed.emit()
	for i in 600:
		await physics_frame
		if not session.modal and not race.board_controller.result_busy: break
	check(not session.modal and car.global_position.distance_to(race.staging_point)<15.0,"result returns physical car to safe entry")
	check(race.perform("board"),"entry board reopens after real race")
	race.board_controller.board.takeshi_button.pressed.emit()
	var choose_car := "--reward-car" in OS.get_cmdline_user_args()
	check(session.modal and press("Escolher o Supra" if choose_car else "Escolher a katana"),"reopening pending reward allows selection")
	if choose_car:
		check(HONOR.data(session.state.world_state).reward=="car" and session.state.world_state.get("desert_fleet",{}).has(HONOR.CAR_ID),"Supra delivered through actual reward action")
	else:
		check(HONOR.data(session.state.world_state).reward=="katana" and session.state.economy.snapshot().weapons.has("katana"),"katana delivered through actual reward action")
	check(not HONOR.claim(session,"katana" if choose_car else "car").get("ok",false),"second reward choice is rejected")
	if session.dialogue_open: session.dialogue_card.advance_button.pressed.emit()
	if session.modal: session.close_menu()
	check(not world.player.input_locked and not car.input_locked,"reward closes without leaving controls locked")
	var honor_before := HONOR.data(session.state.world_state)
	check(race.start_rival("takeshi") and session.dialogue_open and not race.active,"rematch speaks before allocating race cars")
	session.interrupt_dialogue()
	session.close_menu()
	check(not race.active and not world.player.input_locked and not car.input_locked,"interrupted introduction cannot start a delayed race or lock controls")
	check(race.start_rival("takeshi") and session.dialogue_open,"interrupted introduction can be retried")
	session.dialogue_card.advance_button.pressed.emit()
	check(race.active and race.rival_id=="takeshi","rematch after interruption uses same physical rival")
	race.cancel_attempt()
	for i in 3: await physics_frame
	check(not race.active and not car.input_locked and not world.player.input_locked,"cancelling the rematch restores all vehicle and player controls")
	check(HONOR.data(session.state.world_state)==honor_before,"cancelled rematch preserves best time and unique reward")
	finish()

func finish() -> void:
	print("TAKESHI_SESSION checks=",checks," failures=",failures," output=",output)
	if is_instance_valid(world): world.free()
	quit(0 if failures.is_empty() else 1)
