extends SceneTree
## Legacy five-win checkpoint -> real final -> result -> rematch cancellation.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const PROGRESS := preload("res://activities/desert_drag/DesertDragProgress.gd")
var world
var output := ""
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(210).timeout.connect(func(): push_error("RAUHZ_SESSION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	print("RAUHZ_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated .NET session required"): quit(2); return
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("rauhz-session")
	var at: Vector3 = LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data := FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	for id in ["digo","livia","raul","jessica","nadir"]: PROGRESS.record_finish(data.world,id,true,20)
	preload("res://systems/campaign/DigoProgress.gd").complete_desert_race(data.world,"digo_desert_race",true)
	var path := FIXTURE.write_fixture(output,"legacy-champion.json",data)
	if not check(not path.is_empty(),"real legacy champion checkpoint accepted"): quit(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"Main loads isolated legacy checkpoint"): quit(1); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"C# route backend active")
	world.gameplay.god_mode = true
	var session = world.session
	var race = session.desert.drag
	check(PROGRESS.current_rival(session.state.world_state)=="rauhz","legacy champion's next playable rival is Rauhz")
	PROGRESS.claim_rewards(session.state.world_state,session.state.economy)
	var balance: int = session.state.economy.balance
	var car = world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not check(is_instance_valid(car),"player car spawned"): quit(1); return
	preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(car,race.rival_parts("rauhz"))
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	check(world.driving.interact(),"ordinary player boarding")
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not check(world.driving.occupied and not car.input_locked,"boarding restores driver controls"): quit(1); return
	check(race.perform("board"),"board opens in gameplay")
	var board = race.board_controller.board
	board.rows[5].pressed.emit()
	check(board.selected=="rauhz" and not board.race_button.disabled,"sixth portrait starts the unlocked final")
	await capture("final-board")
	board.race_button.pressed.emit()
	if not check(race.active and race.rival_id=="rauhz","real final starts from Correr"): quit(1); return
	var opponent = race.racers[1].car
	check(opponent.archetype=="rauhz_focus_mk1" and opponent.wheels.size()==4,"opponent is physical Focus with four animated wheels")
	check(opponent.get_node("DragRivalDriver").get_meta("character_identity")=="rauhz","Rauhz sits in his own Focus")
	check(race.racers[1].drive.spec.id=="rauhz_focus_mk1","rival races with actual Focus engine")
	await capture("final-grid")
	session._menu("Pausa")
	check(session.modal,"final accepts pause")
	session.close_menu()
	var photographed := false
	var deadline := Time.get_ticks_msec()+80000
	while race.active and Time.get_ticks_msec()<deadline:
		race._throttle_override = .54 if race.phase=="staging" else 1.0
		race._nitro_override = race.phase=="racing"
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		if race.elapsed>5 and not photographed:
			photographed = true
			await capture("final-racing")
		await physics_frame
	check(not race.active and race.last_result.get("finished",false),"physical final reaches finish")
	check(race.last_result.get("won",false),"player-available preparation and clean shifts can beat final boss")
	check(PROGRESS.data(session.state.world_state).wins.has("rauhz"),"physical victory records final rival")
	check(session.state.economy.balance==balance+9000,"real first final victory pays exactly once")
	await create_timer(.3).timeout
	check(session.modal and race.board_controller.results_layer.visible,"final opens result actions")
	await capture("final-result")
	race.board_controller.results.buttons[0].pressed.emit()
	for i in 600:
		await physics_frame
		if race.active: break
	check(race.active and race.rival_id=="rauhz","result rematch starts same final boss")
	race.cancel_attempt()
	for i in 4: await physics_frame
	check(not race.active and not car.input_locked and not world.player.input_locked,"cancelled rematch restores control")
	check(session.state.economy.balance==balance+9000,"rematch cancellation preserves exact wallet")
	check(not is_instance_valid(opponent),"completed opponent is cleaned up")
	print("RAUHZ_SESSION_DONE checks=",checks," failures=",failures," output=",output)
	quit(0 if failures.is_empty() else 1)
