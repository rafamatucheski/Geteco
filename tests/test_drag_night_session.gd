extends SceneTree
## Real Main/.NET, input-driven four-pass night. Isolated saved checkpoint;
## no injected crossing, finish time, score or reward.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/desert/DesertLayout.gd")
const NIGHT = preload("res://activities/desert_drag/DragNightProgress.gd")
var world
var output := ""
var failures: Array[String] = []
var checks := 0
var temporal: Node

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("NIGHT_SESSION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("NIGHT_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated .NET required"): finish(); return
	root.size=Vector2i(1280,720)
	TranslationServer.set_locale("pt_BR")
	output=FIXTURE.output_dir("drag-night-session")
	var at := LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data := FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.time=.9
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"real Main uses isolated checkpoint"): finish(); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"C# route backend active")
	var session=world.session
	var race=session.desert.drag
	race.open_meet.enabled=false
	world.gameplay.god_mode=true
	session.weather.set_process(false)
	session.weather.time_of_day=.9
	session.weather._update()
	var car=world.production.spawn_vehicle("desert_mirage",at+Vector3(0,0,-6),-PI*.5)
	if not check(is_instance_valid(car),"player vehicle admitted"): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	check(world.driving.interact(),"ordinary boarding")
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not check(world.driving.occupied and not car.input_locked,"boarding releases controls"): finish(); return
	var region=world.production.regions.desert
	for i in 1800:
		await process_frame
		if region.is_streaming_idle(): break
	check(region.drag_view_cells.size()==26 and region.drag_view_pending.is_empty(),"bounded course prepared before race")
	var resident_ids := {}
	for key in region.drag_view_cells: resident_ids[key]=region.chunks[key].get_instance_id()
	var legacy: Dictionary=race.snapshot().duplicate(true)
	var before_campaign: Dictionary=session.state.campaign.snapshot().duplicate(true)
	var balance: int=session.state.economy.balance
	if "--temporal" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		temporal=preload("res://tests/capture/DesertDragTemporalCapture.gd").new()
		root.add_child(temporal)
		check(temporal.begin(world,race,output.path_join("temporal"),5400),"continuous rendered evidence begins")
		temporal.segment="drag"
		temporal._report.clock_control="Night fixed at0.9; all four passes and physical return use production cameras."
		temporal._report.coverage="Noite de Acerto201/402/402/800, actual race physics, results, return and stable course cell identity."
	# Os pontos de entrada de controlador/UI são resolvidos aqui para exercitar as mesmas ações
	# do jogador, incluindo fechar modais e a volta segura entre passadas.
	for step in 4:
		check(race.perform("board"),"board opens for pass%d"%(step+1))
		race.board_controller.board.night_button.pressed.emit()
		await process_frame
		await capture("night-board-%d"%(step+1))
		if not check(not race.night_controller.panel.buttons.continue.disabled and not race.night_controller.panel.buttons.back.disabled,"night actions remain usable after return%d"%(step+1)): finish(); return
		race.night_controller.panel.buttons.continue.pressed.emit()
		for i in 120:
			await physics_frame
			if race.active: break
		if not check(race.active and race._night_attempt and race.distance==NIGHT.DISTANCES[step],"night starts correct physical distance%d"%(step+1)): finish(); return
		if step==0:
			race.cancel_attempt()
			check(NIGHT.next_pass(session.state.world_state).step==0 and session.state.economy.balance==balance,"cancelled attempt preserves series without score or prize")
			if not check(race.night_controller.request_next() and race.active,"cancelled first pass restarts normally"): finish(); return
		check(race.racers[0].drive.race_mode and race.racers[1].drive.race_mode,"race feel enabled for both cars")
		var keyboard_clock := 0.0
		while race.active:
			# Binary presses only. No ideal analog staging override.
			var pressed := true
			if race.phase=="staging":
				keyboard_clock+=1.0/Engine.physics_ticks_per_second
				pressed=keyboard_clock<1.3 or keyboard_clock>2.3
			var event := InputEventKey.new()
			event.physical_keycode=KEY_W
			event.pressed=pressed
			Input.parse_input_event(event)
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
			await physics_frame
		var release := InputEventKey.new()
		release.physical_keycode=KEY_W
		release.pressed=false
		Input.parse_input_event(release)
		print("NIGHT_SESSION_RESULT ",JSON.stringify(race.last_result))
		if not check(race.last_result.get("finished",false) and race.last_result.get("night",false),"real crossing produces night result%d"%(step+1)): finish(); return
		check(race.last_result.night_pass==step+1,"pass counter advances once")
		check(race.night_controller.record_finish(1.0,2.0,car).is_empty(),"duplicate callback pays nothing")
		for key in resident_ids:
			if not region.chunks.has(key) or region.chunks[key].get_instance_id()!=resident_ids[key]:
				check(false,"course chunk replaced during race at"+str(key))
		await create_timer(.3).timeout
		await capture("night-result-%d"%(step+1))
		check(session.modal and race.board_controller.results_layer.visible,"real result shown")
		if step<3:
			race.board_controller.results.buttons[1].pressed.emit()
			for i in 900:
				await physics_frame
				if race.night_controller.layer.visible and not race.board_controller.result_busy: break
			check(session.modal and race.night_controller.layer.visible and car.global_position.distance_to(race.staging_point)<15,"result returns to paddock safely")
			session.close_menu()
			var saved: Dictionary=session.state.snapshot()
			check(NIGHT.validate_world(saved.world,saved.economy),"full snapshot accepts intermediate night")
			var restored=preload("res://runtime/GameState.gd").new()
			check(restored.restore_snapshot(saved) and NIGHT.next_pass(restored.world_state).pass==step+2,"checkpoint restores next pass")
		else: session.close_menu()
	check(race.snapshot()==legacy,"night leaves ranked strikes/rewards intact")
	check(session.state.campaign.snapshot()==before_campaign,"night does not trigger campaign story")
	var ledger := NIGHT.data(session.state.world_state)
	check(ledger.finishes==1 and ledger.current.is_empty(),"four crossings complete exactly one night")
	var expected := NIGHT.FINISH_PRIZE+(NIGHT.WIN_PRIZE if ledger.wins==1 else 0)
	check(session.state.economy.balance==balance+expected,"completion and victory receipts pay once")
	check(not car.input_locked and not world.player.input_locked,"finish releases ordinary controls")
	if is_instance_valid(temporal):
		var report: Dictionary=temporal.stop()
		check(report.failure.is_empty() and report.duration_seconds>=30 and report.skipped_rendered_frames==0,"continuous temporal sequence complete")
	finish()

func finish() -> void:
	if is_instance_valid(temporal) and temporal.recording: temporal.stop()
	print("NIGHT_SESSION_DONE checks=",checks," failures=",failures," output=",output)
	quit(0 if failures.is_empty() else 1)
