extends SceneTree
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACE = preload("res://world/places/arcade/ArcadePlace.gd")
var world
var folder := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("ARCADE_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func settle_transition() -> void:
	var deadline := Time.get_ticks_msec()+8000
	while world.session.is_transition_blocked() and Time.get_ticks_msec() < deadline: await physics_frame
func photo(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(id+".png")) == OK,"capture "+id)
func walk(point: Vector3, budget := 5.0) -> bool:
	world.player.controlled_automatically = true
	var deadline := Time.get_ticks_msec()+int(budget*1000)
	while Time.get_ticks_msec() < deadline:
		var offset: Vector3 = point-world.player.global_position
		offset.y = 0
		if offset.length() < .13:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false
func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func run() -> void:
	create_timer(210).timeout.connect(func(): push_error("Arcade session timed out"); quit(3))
	seed(81026)
	folder = FIXTURE.output_dir("arcade-session")
	var definition := PLACE.definition_data()
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3(0,.05,2),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var save_path := FIXTURE.write_fixture(folder,"save.json",snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	var session = world.session
	check(not session.controller.no_save,"real save enabled on isolated fixture path")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"compiled C# routing active in Main")
	check(session.arcade != null,"arcade service installed")
	check(not session.arcade.perform("racer"),"cannot start remotely outside shop")
	check(await walk(definition.entry_position),"walk along real sidewalk to entry")
	await photo("01-facade")
	check(session.nearest().get("place","") == PLACE.ID,"entry action belongs to Fagulha")
	check(await session.interact(),"enter using actual interaction and admission")
	await settle_transition()
	check(session.state.place_id == PLACE.ID,"arrived at arcade")
	if session.state.place_id != PLACE.ID: finish(); return
	check(session.room_npcs.size() == 2,"two native resident actors playing")
	check(session.position_clear(world.player.global_position+Vector3.UP*.04),"whole-body spawn clearance")
	check(world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,"orthographic interior camera")
	await frames(45)
	await photo("02-room")
	var starting_cash: int = session.state.economy.balance
	for id in ["pinball","blocks","racer","fighter"]:
		var target: Vector3 = session.room.interaction_points["arcade_"+id]
		check(await walk(session.room.to_global(Vector3(0,0,-1.1))),id+" central aisle")
		check(await walk(session.room.to_global(Vector3(target.x-session.room.global_position.x,0,-1.1))),id+" cross aisle")
		check(await walk(target),id+" approach cabinet on foot")
		check(session.nearest().get("target","") == id,id+" cabinet prompt")
		check(await session.interact(),id+" actual play interaction")
		world.player.controlled_automatically = false
		var arcade = session.arcade
		check(arcade.active and session.modal and world.player.input_locked,id+" modal owns controls")
		check(not session.save_block_reason().is_empty(),id+" live round not saved")
		check(not world.gameplay._free_play_ok(),id+" real combat blocked")
		await press("ui_accept")
		check(arcade.ui.playing,id+" Enter starts round")
		await frames(5)
		await press("interact")
		await frames(45)
		var before: Vector3 = world.player.global_position
		await press("move_left")
		check(world.player.global_position.distance_to(before) < .08,id+" minigame input does not move Dante")
		arcade.ui.toggle_pause()
		var paused_score: int = arcade.ui.game.score
		await frames(10)
		check(arcade.ui.suspended and arcade.ui.game.score == paused_score,id+" pause freezes minigame")
		arcade.ui.toggle_pause()
		await photo("03-"+id)
		# Deterministic result injection checks only record persistence; game
		# mechanics are independently exercised in test_arcade_games.gd.
		arcade.ui.game.score = 1234
		await press("ui_cancel")
		check(not arcade.active and not session.modal and not world.player.input_locked,id+" Escape returns controls")
		check(not paused,id+" Escape does not also pause the world")
		check(arcade.records.get(id,0) == 1234,id+" record retained")
		world.player.controlled_automatically = true
	check(session.state.economy.balance == starting_cash,"arcades do not charge or mint money")
	check(not session.arcade.perform("unknown"),"invalid cabinet rejected")
	check(await walk(session.room.to_global(Vector3(0,0,.1))),"walk back to aisle")
	# Stop in the interaction zone, before the walk-up door's transition
	# threshold (exit.z - .55). This scenario explicitly tests pressing E.
	check(await walk(session.room.exit_position+Vector3.FORWARD*.8),"walk to exit interaction zone")
	check(session.nearest().get("id","") == "exit","exit action available at approach")
	check(await session.interact(),"actual exit interaction")
	check(session.state.place_id.is_empty() and not session.modal,"exit restores exterior context")
	check(world.player.global_position.distance_to(definition.return_position) < 2.5,"return to same storefront")
	check(await walk(definition.entry_position),"return to entry on foot")
	check(await session.interact(),"second entry")
	await settle_transition()
	check(session.room_npcs.size() == 2,"reentry has two residents without duplicates")
	check(session.save_game(),"write isolated real save")
	var saved := preload("res://runtime/SaveStore.gd").read_valid(save_path)
	check(not saved.is_empty(),"saved bytes pass SaveStore validation")
	if not saved.is_empty():
		check(saved.world.get("arcade_records",{}).get("fighter",0) == 1234,"record exists in saved bytes")
		var restored = preload("res://runtime/GameState.gd").new()
		check(restored.restore_snapshot(saved) and restored.place_id == PLACE.ID,"restore accepts arcade interior and records")
	var runtime = session.arcade
	world.player.teleport(session.room.interaction_points.arcade_blocks+Vector3.UP*.04)
	await frames(3)
	check(runtime.perform("blocks"),"reopen for interruption")
	session._menu("Teste de interrupção")
	check(not runtime.active and session.modal and session.panel.visible,"replacement modal closes arcade without unlocking new modal")
	session.close_menu()
	check(runtime.perform("blocks"),"reopen after replacement modal")
	world.gameplay.health -= 1
	var interrupt_deadline := Time.get_ticks_msec()+1000
	while runtime.active and Time.get_ticks_msec() < interrupt_deadline: await process_frame
	check(not runtime.active and not session.modal,"taking damage interrupts cabinet safely")
	await photo("04-return")
	finish()

func finish() -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("ARCADE_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
