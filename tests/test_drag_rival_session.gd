extends "res://tests/test_drag_night_session.gd"
## All twelve authored proofs through Main, real vehicle movement and result UI.
## Input automation changes throttle/shift only; no finish/score injection.
const CHALLENGES := preload("res://activities/desert_drag/DragRivalChallengeProgress.gd")
const CHALLENGE_CATALOG := preload("res://activities/desert_drag/DragRivalChallengeCatalog.gd")
const CHALLENGE_GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const CHALLENGE_CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")

class InputShield extends Node:
	func _input(_event: InputEvent) -> void:
		get_viewport().set_input_as_handled()
	func _physics_process(_delta: float) -> void:
		for action in InputMap.get_actions(): Input.action_release(action)

func _initialize() -> void:
	create_timer(900).timeout.connect(func(): push_error("RIVAL_SESSION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks+=1
	print("RIVAL_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated .NET required"): finish(); return
	root.size=Vector2i(1280,720)
	TranslationServer.set_locale("pt_BR")
	output=FIXTURE.output_dir("drag-rival-session")
	var at := LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var fixture := FIXTURE.full_snapshot(at,true)
	fixture.region_id="desert"
	fixture.world.time=.9
	fixture.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",fixture)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var shield := InputShield.new()
	shield.process_physics_priority=-100
	root.add_child(shield)
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
	var car=world.production.spawn_vehicle("desert_faisca",at+Vector3(0,0,-6),-PI*.5)
	if not check(is_instance_valid(car),"stock workshop-size vehicle admitted"): finish(); return
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
	check(region.drag_view_pending.is_empty(),"course prewarm settles before physical proof sequence")
	var already_completed := _seed_recorded_proofs(session.state,car)
	if not failures.is_empty(): finish(); return
	var legacy: Dictionary=race.snapshot().duplicate(true)
	var campaign: Dictionary=session.state.campaign.snapshot().duplicate(true)
	for rival in CHALLENGE_CATALOG.IDS:
		if rival in already_completed: continue
		for step in 2:
			check(race.perform("board"),"board opens for %s %d"%[rival,step+1])
			race.board_controller.board.challenges_button.pressed.emit()
			await process_frame
			var controller=race.challenge_controller
			controller.panel.buttons["rival:"+rival].pressed.emit()
			controller.panel.buttons["step:"+str(step)].pressed.emit()
			await capture("challenge-%s-%d-board"%[rival,step+1])
			if not check(not controller.panel.buttons.start.disabled,"objective and reward are available before entering %s %d"%[rival,step+1]): finish(); return
			controller.panel.buttons.start.pressed.emit()
			for i in 180:
				await physics_frame
				if race.active: break
			if not check(race.active and race._challenge_attempt and race.distance==CHALLENGE_CATALOG.goal(rival,step).distance,"correct physical challenge distance %s %d"%[rival,step+1]): finish(); return
			if rival=="digo" and step==0:
				race.cancel_attempt()
				check(CHALLENGES.data(session.state.world_state).current.is_empty() and CHALLENGES.status(session.state.world_state,"digo").stamps==0,"cancelled physical attempt creates no proof or reward")
				if not check(controller.request_next() and race.active,"cancelled proof can retry normally"): finish(); return
			var keyboard_clock := 0.0
			var captured_live := false
			var captured_staging := false
			var survived_rival_gap := false
			while race.active:
				var pressed := true
				if race.phase=="staging":
					keyboard_clock+=1.0/Engine.physics_ticks_per_second
					pressed=keyboard_clock<1.3 or keyboard_clock>2.3
				var event := InputEventKey.new()
				event.physical_keycode=KEY_W
				event.pressed=pressed
				Input.parse_input_event(event)
				if not captured_staging and rival=="digo" and step==0 and race.phase=="staging" and keyboard_clock>.5:
					captured_staging=true
					await capture("challenge-compact-hud-staging")
				if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
				if rival=="nadir" and step==0 and race.phase=="racing" and is_finite(float(race.racers[1].finish)) and race.elapsed>float(race.racers[1].finish)+8.0 and not is_finite(float(race.racers[0].finish)):
					survived_rival_gap=true
				if not captured_live and step==1 and rival in ["livia","rauhz"] and race.phase=="racing" and race.elapsed>8.0 and race.racers[0].drive.rpm<race.racers[0].drive.redline*.8:
					captured_live=true
					await capture("challenge-%s-live-status"%rival)
				await physics_frame
			var release := InputEventKey.new()
			release.physical_keycode=KEY_W
			release.pressed=false
			Input.parse_input_event(release)
			print("RIVAL_SESSION_RESULT ",JSON.stringify(race.last_result))
			if not check(race.last_result.get("finished",false) and race.last_result.get("challenge_success",false),"real physical crossing fulfills %s %d"%[rival,step+1]): finish(); return
			if rival=="nadir" and step==0: check(survived_rival_gap,"valid stock-car objective stays active more than eight seconds after the rival finishes")
			check(controller.record_finish(1.0,2.0,car).is_empty(),"duplicate callback cannot repeat gift or bonus")
			check(CHALLENGE_CARS.parts_for_vehicle(car).is_empty(),"proofs are achievable in stock car without installing previous prizes")
			for i in 12: await process_frame
			await capture("challenge-%s-%d-result"%[rival,step+1])
			check(session.modal and race.board_controller.results_layer.visible,"challenge result remains inspectable")
			if rival=="digo" and step==0:
				race.board_controller.results.telemetry_button.pressed.emit()
				await capture("challenge-pass-telemetry")
				race.board_controller.results.telemetry_button.pressed.emit()
			race.board_controller.results.buttons[1].pressed.emit()
			for i in 900:
				await physics_frame
				if controller.layer.visible and not race.board_controller.result_busy: break
			check(session.modal and controller.layer.visible and car.global_position.distance_to(race.staging_point)<15,"result returns safely to workshop challenge overview")
			if step==1:
				check(str(CHALLENGE_CATALOG.RIVALS[rival].part) in CHALLENGE_GARAGE.vehicle(session.state.world_state,car.vehicle_id,car.archetype).owned,"mastery gives real installable ownership: "+rival)
			var snapshot: Dictionary=session.state.snapshot()
			var restored=preload("res://runtime/GameState.gd").new()
			check(restored.restore_snapshot(snapshot),"production snapshot restores after %s %d"%[rival,step+1])
			check(not FIXTURE.write_fixture(output,"after-%s-%d.json"%[rival,step+1],snapshot).is_empty(),"isolated physical proof snapshot saved for resumption")
			session.close_menu()
	check(CHALLENGE_CATALOG.IDS.all(func(id): return CHALLENGES.mastered(CHALLENGES.data(session.state.world_state),id)),"all twelve workshop proofs are recorded after the physical sequence")
	check(race.snapshot()==legacy and session.state.campaign.snapshot()==campaign,"workshop proofs preserve ranked and campaign progression")
	check(race.challenge_controller.open("digo"),"mastered rival remains selectable for preparation and replay")
	race.challenge_controller.panel.buttons.install.pressed.emit()
	check(CHALLENGE_CARS.parts_for_vehicle(car).get("ecu","")=="rival_digo_ecu","earned ECU installs on actual vehicle from challenge panel")
	await capture("challenge-mastered-installed")
	session.close_menu()
	check(race.night_controller.open("digo"),"night categories remain accessible after workshop mastery")
	race.night_controller.panel.buttons["category:street"].pressed.emit()
	await capture("night-budget-category")
	session.close_menu()
	check(not car.input_locked and not world.player.input_locked,"final result and installation restore ordinary controls")
	check(not FIXTURE.write_fixture(output,"completed-installed.json",session.state.snapshot()).is_empty(),"installed prize persists in an isolated production snapshot")
	finish()

func _seed_recorded_proofs(state, car: Node) -> Array[String]:
	# Recovery only: previous physical results become explicit fixture prerequisites,
	# never evidence that this process drove the skipped races again.
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-rival-log="): source=argument.trim_prefix("--resume-rival-log=")
	if source.is_empty(): return []
	if not check(FileAccess.file_exists(source),"recorded-proof recovery log exists"): return []
	var seeded := 0
	for line in FileAccess.get_file_as_string(source).split("\n"):
		if not line.begins_with("RIVAL_SESSION_RESULT "): continue
		var parsed: Variant=JSON.parse_string(line.trim_prefix("RIVAL_SESSION_RESULT "))
		if not parsed is Dictionary or not parsed.get("challenge_success",false): continue
		var rival := str(parsed.get("rival_id",""))
		var step := int(parsed.get("challenge_step",-1))
		var entry := CHALLENGES.begin(state.world_state,rival,step,car.vehicle_id,car.archetype,car.archetype,{})
		if not check(entry.get("ok",false),"observed prerequisite can be replayed into recovery fixture: %s %d"%[rival,step+1]): return []
		var restored := CHALLENGES.record_finish(state.world_state,int(entry.entry.id),car.vehicle_id,car.archetype,{},float(parsed.seconds),float(parsed.rival_seconds),float(parsed.distance),parsed.challenge_metrics)
		if not check(restored.get("challenge_success",false),"recorded metrics satisfy prerequisite without fabricating a new crossing"): return []
		seeded+=1
		print("RIVAL_SESSION_FIXTURE prior physical proof ",rival," ",step+1," seconds=",parsed.seconds)
	var completed: Array[String]=[]
	for rival in CHALLENGE_CATALOG.IDS:
		if CHALLENGES.mastered(CHALLENGES.data(state.world_state),rival): completed.append(rival)
	check(seeded==8 and completed==["digo","livia","raul","jessica"],"recovery fixture contains exactly the eight approved earlier physical proofs")
	check(not FIXTURE.write_fixture(output,"recovery-prerequisites.json",state.snapshot()).is_empty(),"recovery prerequisite fixture passes the complete save contract")
	return completed

func finish() -> void:
	print("RIVAL_SESSION_DONE checks=",checks," failures=",failures," output=",output)
	quit(0 if failures.is_empty() else 1)
