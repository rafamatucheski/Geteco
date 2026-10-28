extends "res://tests/measure/measure.gd"
## Real Main and isolated saves. Baseline disables only bars; never certifies
## performance when another rendered game is running (check process inventory).
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var folder := ""
var issues: Array[String] = []

func verify(ok: bool, message: String) -> void:
	print("BARS_MAIN ", "PASS " if ok else "FAIL ", message)
	if not ok: issues.append(message)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240).timeout.connect(func(): push_error("BARS_MAIN timeout"); quit(3))
	var id := "harbor_bar"
	var baseline := "--bars-before" in OS.get_cmdline_user_args()
	var measure := "--measure-bars" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bar="): id = arg.trim_prefix("--bar=")
	Engine.set_meta("bars_baseline", baseline)
	var definition: Dictionary = load("res://world/places/bars/BarCatalog.gd").definition(id)
	folder = FIXTURE.output_dir("bars-" + id + ("-before" if baseline else "-after"))
	var point: Vector3 = definition.return_position + Vector3(0, .08, 1.5)
	var snapshot := FIXTURE.full_snapshot(point, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = definition.region
	snapshot.world.pedestrian = {"region":definition.region,"position":[point.x,point.y,point.z]}
	snapshot.world.time = .8
	var save_path := FIXTURE.write_fixture(folder, "save.json", snapshot)
	verify(not save_path.is_empty(), "isolated save accepted")
	if save_path.is_empty(): quit(2); return
	var settings = root.get_node("V2Settings")
	settings.window_mode = 0; settings.resolution = 0; settings.vsync = true; settings.fps_limit = 1; settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world); current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	while world.session.is_transition_blocked(): await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.target_size = 24
	await photo("01-exterior")
	var results := {}
	if measure: results.exterior = await sample()
	if not baseline:
		var session = world.session
		# Start on the real approach; only this initial placement is fixture setup.
		var doorway: Vector3 = definition.entry_position
		var entered := await walk(doorway - Vector3(0,0,2.0), 6.0)
		while session.is_transition_blocked(): await physics_frame
		verify(session.state.place_id == id, "physical push door admits " + id + " (walk=" + str(entered) + ")")
		if session.state.place_id != id:
			# Diagnostic fallback permits checking independent downstream contracts;
			# the failed physical approach stays a failure in the report.
			verify(await session.enter_place(id, false), "direct admission diagnostic")
		while session.is_transition_blocked(): await physics_frame
		if session.state.place_id == id:
			var room = session.room
			verify(session.position_clear(world.player.global_position + Vector3.UP * .04), "full-body interior spawn")
			verify(session.room_npcs.size() == 4, "four native drinking patrons")
			verify(world.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic camera")
			verify(room.speaker.playing, "local music playing")
			await photo("02-interior")
			if measure: results.interior = await sample()
			var starting_inventory: Dictionary = session.state.economy.inventory
			var starting_cash: int = session.state.economy.balance
			var aisle_z := 1.6 if id == "desert_bar" else 2.8
			for game_id in ["bar_pool", "bar_darts"]:
				var target: Vector3 = room.interaction_points[game_id]
				verify(await walk(room.to_global(Vector3(0,0,aisle_z)), 4), game_id + " central aisle")
				verify(await walk(room.to_global(Vector3(room.to_local(target).x,0,aisle_z)), 4), game_id + " cross aisle")
				verify(await walk(target, 5), game_id + " walk to play station")
				verify(session.nearest().get("target", "") == game_id, game_id + " contextual action")
				verify(await session.interact(), game_id + " start via real interaction")
				verify(room.game_active and session.modal and world.player.input_locked, game_id + " owns controls")
				verify(not session.save_block_reason().is_empty(), game_id + " save blocked during round")
				verify(not world.gameplay._free_play_ok(), game_id + " real combat blocked")
				if not room.game_active: continue
				world.player.controlled_automatically = false
				for i in 4: await physics_frame
				var shots: int = room.game_ui.game.shots
				await press("interact")
				verify(room.game_ui.game.shots == shots + 1, game_id + " remapped action launches a shot")
				room.game_ui.paused = true
				var position: Vector3 = world.player.global_position
				await press("move_left")
				verify(world.player.global_position.distance_to(position) < .08, game_id + " movement belongs to game")
				await photo("03-" + game_id)
				await press("ui_cancel")
				verify(not room.game_active and not session.modal and not world.player.input_locked, game_id + " releases controls")
				verify(not paused, game_id + " cancel does not pause world")
				world.player.controlled_automatically = true
				verify(room.start_game(game_id, session), game_id + " reopen for menu interruption")
				session._menu("Teste")
				verify(not room.game_active and session.modal and world.player.input_locked, game_id + " replacement modal retains controls")
				session.close_menu()
				verify(await walk(room.to_global(Vector3(room.to_local(target).x,0,aisle_z)), 5), game_id + " return down games aisle")
			verify(session.state.economy.inventory == starting_inventory and session.state.economy.balance == starting_cash, "games preserve inventory and wallet")
			verify(await walk(room.to_global(Vector3(0,0,aisle_z)), 5), "walk to exit aisle")
			await walk(room.exit_position + Vector3(0,0,1.0), 6)
			while session.is_transition_blocked(): await physics_frame
			verify(session.state.place_id.is_empty(), "physical exit")
			if not session.state.place_id.is_empty(): await session.leave_place()
			await wait_access()
			verify(world.player.global_position.distance_to(definition.return_position) < 3, "return to original facade")
			await walk(definition.entry_position - Vector3(0,0,2.0), 6)
			while session.is_transition_blocked(): await physics_frame
			await wait_access()
			verify(session.state.place_id == id, "second physical admission")
			verify(session.room_npcs.size() == 4, "reentry without duplicate patrons")
			verify(session.save_game(), "save interior to isolated file")
			var saved := preload("res://runtime/SaveStore.gd").read_valid(save_path)
			var restored = preload("res://runtime/GameState.gd").new()
			verify(not saved.is_empty() and restored.restore_snapshot(saved) and restored.place_id == id, "saved bytes restore through real contract")
	results.environment = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"target_ms":16.67,"regression_signal_percent":5,"baseline":baseline,"place":id,"note":"Fixture initializes at destination; inter-region travel is not covered. Check external process inventory before using timing."}
	results.issues = issues
	FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("BARS_MAIN_RESULTS ",folder," issues=",issues)
	world.queue_free(); await process_frame
	quit(0 if issues.is_empty() else 1)

func walk(point: Vector3, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	var origin: String = world.session.state.place_id
	while Time.get_ticks_msec() < deadline and world.session.state.place_id == origin:
		var offset: Vector3 = point - world.player.global_position
		offset.y = 0
		if offset.length() < .15:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false

func photo(id: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id + ".png"))

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action; event.pressed = true
	Input.parse_input_event(event)
	for i in 2: await physics_frame
	event = InputEventAction.new()
	event.action = action; event.pressed = false
	Input.parse_input_event(event)
	for i in 2: await physics_frame

func wait_access() -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline and (world.player.input_locked or world.session.weapon_shop_entrance._entering or world.session.weapon_shop_entrance._leaving): await physics_frame

func sample() -> Dictionary:
	print("BARS_SAMPLE_START ",folder," at=",world.player.global_position)
	var warm: Array[float] = []
	var raw: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var interval := float(now - previous) / 1000.0
		previous = now
		if now - start < 8000000: warm.append(interval)
		else: raw.append(interval)
	var summary := stats(raw)
	print("BARS_SAMPLE_END ",JSON.stringify(summary))
	return {"summary":summary,"warmup":stats(warm),"raw_ms":raw,"warmup_ms":warm}
