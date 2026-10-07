extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var world
var failures: Array[String]=[]
var output := ""

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
	check(race.perform("board"),"driver opens board")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/board-in-game.png")
	race.board_controller.board.race_button.pressed.emit()
	check(race.active and not session.modal and not race.board_controller.layer.visible,"Correr starts real race and dismisses board")
	check(race.rival_id=="digo" and race.racers.size()==2,"authoritative first rival and two physical cars")
	race.cancel_attempt()
	for i in 3: await physics_frame
	check(not race.active and not car.input_locked and not world.player.input_locked and race.snapshot().wins.is_empty(),"cancellation restores controls and grants no strike")
	if "--drive" in OS.get_cmdline_user_args():
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
		check(session.modal and race.board_controller.layer.visible and race.board_controller.board.strike.get("digo",0.0)==1.0,"real victory automatically opens board and animates the saved strike")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/victory.png")
		session.close_menu()
		check(not car.input_locked and not world.player.input_locked,"victory board returns controls on close")
	print("BOARD_SESSION_DONE ",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)
