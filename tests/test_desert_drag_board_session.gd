extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var world
var failures: Array[String]=[]
var output := ""
var hud_samples := 0
var hud_stale := 0

func _initialize() -> void:
	create_timer(210).timeout.connect(func(): push_error("BOARD_SESSION timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,label: String) -> bool:
	print("BOARD_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if not check("--no-save" in OS.get_cmdline_user_args() and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"isolated .NET required"): quit(2); return
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-board-session")
	var at := LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data := FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if path.is_empty(): quit(1); return
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not check(world.session!=null and world.session.ready_for_play and world.production.store.path==path,"real Main uses isolated checkpoint"): quit(1); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"C# route backend active")
	var session=world.session
	var race=session.desert.drag
	# Keep this ranked-board suite independent of the visitor heat schedule.
	race.open_meet.enabled = false
	for i in 3: await physics_frame
	world.gameplay.god_mode=true
	check(not get_nodes_in_group("desert_drag_boards").is_empty(),"physical board streams with the meet")
	var board_at := preload("res://activities/desert_drag/DesertDragBoardProp.gd").position()
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(board_at+Vector3(0,1.65,2),board_at+Vector3(0,1.65,-2),1))
	check(not hit.is_empty() and "DragRivalsBoard" in str(hit.collider.get_path()),"visible board panel has physical collision")
	for cycle in 2:
		check(race.perform("board") and session.modal and race.board_controller.layer.visible,"board opens through activity action")
		check(world.player.input_locked,"opening locks player movement")
		race.board_controller.board.rows[3].pressed.emit()
		check(race.board_controller.board.selected=="jessica" and race.board_controller.board.race_button.disabled,"locked portrait remains inspectable")
		session.close_menu()
		check(not session.modal and not race.board_controller.layer.visible and not world.player.input_locked,"closing restores controls; repeated opening is safe")
	check(race.perform("board"),"on-foot preview reopens")
	race.board_controller.board.race_button.pressed.emit()
	check(not race.active and session.modal and not race.board_controller.board.message.is_empty(),"on-foot start explains missing vehicle without creating a race")
	session.close_menu()
	var car=world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not check(is_instance_valid(car),"race car spawned"): quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	check(world.driving.interact(),"ordinary boarding")
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	if not check(world.driving.occupied and not car.input_locked,"driver controls restored after boarding"): quit(1); return
	if "--instruments" in OS.get_cmdline_user_args(): await check_instruments(race,false)
	check(race.perform("board"),"driver opens board")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/board-in-game.png")
	race.board_controller.board.race_button.pressed.emit()
	check(race.active and not session.modal and not race.board_controller.layer.visible,"Correr starts real race and dismisses board")
	check(race.rival_id=="digo" and race.racers.size()==2,"authoritative first rival and two physical cars")
	if "--instruments" in OS.get_cmdline_user_args(): check(race.hud.style_id=="bar","next actual race equips selected free bar HUD")
	race.cancel_attempt()
	for i in 3: await physics_frame
	check(not race.active and not car.input_locked and not world.player.input_locked and race.snapshot().wins.is_empty(),"cancellation restores controls and grants no strike")
	if "--drive" in OS.get_cmdline_user_args():
		if "--instruments" in OS.get_cmdline_user_args(): RenderingServer.frame_post_draw.connect(sample_instruments)
		check(race.perform("board"),"board reopens after cancellation")
		race.board_controller.board.race_button.pressed.emit()
		var deadline := Time.get_ticks_msec()+80000
		while race.active and Time.get_ticks_msec()<deadline:
			race._throttle_override=.54 if race.phase=="staging" else 1.0
			race._nitro_override=race.phase=="racing"
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm:
				var event := InputEventKey.new()
				event.physical_keycode=KEY_SPACE
				event.pressed=true
				Input.parse_input_event(event)
				event=event.duplicate()
				event.pressed=false
				Input.parse_input_event(event)
			await physics_frame
		check(not race.active and race.last_result.get("finished",false),"physical race reaches its finish without injected results")
		check(race.last_result.get("won",false),"ordinary throttle, shifts and nitro win against Digo")
		await create_timer(1.2).timeout
		check(session.modal and race.board_controller.results_layer.visible and race.board_controller.results.buttons.size()==3,"real victory opens persistent result with all three destinations")
		if "--instruments" in OS.get_cmdline_user_args(): check(race.board_controller.results.result.get("instrument_unlock","")=="Street","first real victory announces newly unlocked panel")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/victory.png")
		if "--instruments" in OS.get_cmdline_user_args():
			race.board_controller.results.buttons[1].pressed.emit()
			for i in 900:
				await physics_frame
				if not session.modal and not race.board_controller.result_busy: break
			check(not session.modal and car.global_position.distance_to(race.staging_point)<15.0,"result button returns safely to staging for instrument purchase")
		else: session.close_menu()
		check(not car.input_locked and not world.player.input_locked,"victory board returns controls on close")
		if "--instruments" in OS.get_cmdline_user_args():
			RenderingServer.frame_post_draw.disconnect(sample_instruments)
			check(hud_samples>100 and hud_stale==0,"HUD matches drivetrain on every sampled rendered race frame: %d samples, %d stale"%[hud_samples,hud_stale])
			await check_instruments(race,true)
	print("BOARD_SESSION_DONE ",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func sample_instruments() -> void:
	var race=world.session.desert.drag
	if not race.active or race.phase!="racing" or world.session.modal: return
	if not is_instance_valid(race.hud): return
	hud_samples+=1
	var drive=race.racers[0].drive
	if not is_equal_approx(race.hud.rpm,drive.rpm) or not is_equal_approx(race.hud.speed,drive.speed_mps*3.6) or race.hud.gear!=drive.gear:
		hud_stale+=1

func check_instruments(race, after_win: bool) -> void:
	var session=world.session
	var styles=preload("res://activities/desert_drag/DragInstrumentStyles.gd")
	if not check(race.perform("board"),"open rival board for instruments"): return
	var controller=race.board_controller
	controller.board.instruments_button.pressed.emit()
	var shop=controller.instrument_shop
	check(shop.is_visible_in_tree() and not controller.board.visible and session.modal,"Panels opens shop with modal ownership")
	var balance: int=session.state.economy.balance
	if not after_win:
		shop.rows[4].pressed.emit()
		check(shop.action_button.disabled,"champion style remains locked before victories")
		controller._request_style("champion")
		check(session.state.economy.balance==balance and not styles.owned(session.state.world_state,"champion"),"controller rejects locked purchase without debit")
		shop.rows[1].pressed.emit()
		shop.action_button.pressed.emit()
		check(styles.selection(session.state.world_state)=="bar" and session.state.economy.balance==balance,"free bar selection uses real shop action without charging")
	else:
		shop.rows[2].pressed.emit()
		check(not shop.action_button.disabled,"actual Digo victory unlocks Street")
		shop.action_button.pressed.emit()
		check(session.state.economy.balance==balance and shop.action_button.text.begins_with("CONFIRMAR"),"first purchase click requests confirmation without charging")
		shop.action_button.pressed.emit()
		check(session.state.economy.balance==balance-1500 and styles.owned(session.state.world_state,"street"),"confirmed Street purchase charges once and grants ownership")
		shop.action_button.pressed.emit()
		check(session.state.economy.balance==balance-1500,"repeated equipped click cannot double charge")
		shop.rows[0].pressed.emit()
		shop.action_button.pressed.emit()
		shop.rows[2].pressed.emit()
		shop.action_button.pressed.emit()
		check(styles.selection(session.state.world_state)=="street" and session.state.economy.balance==balance-1500,"owned cosmetic re-equips without repurchase")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/instrument-shop-in-game.png")
	if after_win:
		var event := InputEventKey.new()
		event.physical_keycode=KEY_ESCAPE
		event.pressed=true
		Input.parse_input_event(event)
		event=event.duplicate()
		event.pressed=false
		Input.parse_input_event(event)
		for i in 3: await process_frame
	else: shop.back_button.pressed.emit()
	check(controller.board.visible and not shop.visible and session.modal,"shop Back returns to rival board")
	session.close_menu()
	check(not session.modal and not controller.layer.visible,"closing board releases modal after instrument changes")
	if after_win:
		check(race.perform("start") and race.hud.style_id=="street","purchased style appears in next physical race")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/street-hud-in-game.png")
		race.cancel_attempt()
