extends SceneTree
## Integrated Main walkthrough, commerce UI, actual drinks, physical return,
## isolated persistence, and a continuous 30s interior lighting sequence.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const WINES := preload("res://gameplay/wine/WineCatalog.gd")
const CELLAR_ID := "harbor_curitiba_cellar"
var world
var folder := ""
var save_path := ""
var checks := 0
var failures: Array[String] = []
var temporal: Array[Dictionary] = []
var original_source: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	checks += 1
	print("CELLAR_SESSION ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET and --no-save required"); quit(2); return
	create_timer(360).timeout.connect(func(): check(false, "finite session timeout"); finish(3))
	root.size = Vector2i(1280, 720)
	seed(7102026)
	folder = FIXTURE.output_dir("curitiba-cellar-session")
	original_source = FIXTURE.source_fingerprint()
	var definition := PLACES.get_definition(CELLAR_ID)
	if not check(not definition.is_empty(), "dedicated Harbor cellar registered"): finish(); return
	var snapshot := FIXTURE.full_snapshot(definition.return_position + Vector3.UP * .08, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.world.time = .45
	snapshot.world.weather = 0
	save_path = FIXTURE.write_fixture(folder, "checkpoint.json", snapshot)
	if not check(not save_path.is_empty(), "isolated valid checkpoint created"): finish(); return
	await boot()
	if not check(world.session != null and world.session.ready_for_play, "Main playable"): finish(); return
	var session = world.session
	check(world.production.store.path == save_path and not world.production.save_invalid, "isolated checkpoint loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "compiled C# router active")
	check(session.wine != null and session.wine.get_intensity() == 0, "old checkpoint loads sober with empty wine stock")
	await photo("01-exterior")
	check(session.nearest().get("id", "") == "enter", "compact transfer access exposes the remappable interaction")
	if not check(await cross_threshold(true), "walk to Curitiba Cellar and use the live entry interaction"): finish(); return
	check(session.position_clear(world.player.global_position), "entry has full-body clearance and floor support")
	check(not world.player.input_locked, "entry restores player control")
	await photo("02-interior")
	check(await walk(session.room.interaction_points.service + Vector3.UP * .04), "walk aisle to Nelson")
	check(session.nearest().get("id", "") == "wine", "Nelson is an actual interaction")
	check(await session.interact(), "functional interaction opens wine shop")
	check(session.wine.ui.visible and session.modal, "wine commerce panel visible")
	await photo("03-shop")
	check(session.wine.ui.card.get_global_rect().end.x <= 1280 and session.wine.ui.card.get_global_rect().end.y <= 720, "shop fits the gameplay viewport")
	# O dinheiro isolado na carteira é preparação da fixture, não asserção de recompensa de missão.
	check(session.state.economy.grant_reward("curitiba_session_test_funds", 2500), "test wallet funded")
	# Acertar as conquistas de dinheiro ganho é parte da preparação da fixture. Senão
	# o save da primeira compra também concede first_grand (+50), escondendo o débito
	# quando só o saldo líquido é conferido.
	session.activities.refresh_achievements()
	var balance: int = session.state.economy.balance
	session.wine.ui.selected = "zacharias_malagousia"
	session.wine.ui.refresh()
	await physics_frame
	var buy_button: Button = session.wine.ui.buy_button
	check(buy_button != null and not buy_button.disabled, "selected bottle can be purchased")
	if buy_button != null: buy_button.pressed.emit()
	await physics_frame
	var purchase_receipt: Dictionary = session.state.economy.snapshot().transactions.get("spend:curitiba_wine_1", {})
	var price := int(WINES.spec("zacharias_malagousia").price)
	check(session.wine.model.count("zacharias_malagousia") == 3 and session.state.economy.balance == balance - price and purchase_receipt.get("amount", -1) == price, "real UI purchase debits one bottle and stores three servings")
	check(session.wine.claim_gift(), "Nelson gives first-visit useful reward")
	check(not session.wine.claim_gift(), "gift receipt blocks duplicate request")
	session.wine.tell_story()
	check(session.dialogue_open, "Nelson tells Greek history through dialogue")
	await photo("04-nelson-story")
	for line in 4:
		if session.dialogue_open: session._advance_dialogue()
	if session.modal: session.close_menu()
	check(await walk(session.room.to_global(Vector3(1.7, .04, -1.1))), "walk around counter toward office")
	check(await walk(session.room.interaction_points.luisa + Vector3.UP * .04), "Luisa's office has an unobstructed approach")
	check(session.wine.perform("luisa") and session.dialogue_open, "Luisa has financial-office conversation")
	await photo("05-luisa-financial")
	for line in 4:
		if session.dialogue_open: session._advance_dialogue()
	if session.modal: session.close_menu()
	check(await walk(session.room.to_global(Vector3(1.7, .04, -1.1))), "leave office around furniture")
	check(await walk(session.room.to_global(Vector3(0, .04, 3.5))), "clear central circulation returns toward entry")
	if "--skip-temporal" not in OS.get_cmdline_user_args(): await temporal_capture()
	world.gameplay.health = 40
	world.player.automatic_direction = Vector3.ZERO
	check(session.wine.drink("zacharias_malagousia"), "actual runtime drinks purchased wine")
	check(world.gameplay.health > 40 and session.wine.model.count("zacharias_malagousia") == 5, "drink heals and consumes exactly one serving")
	check(not session.wine.drink("zacharias_malagousia"), "runtime prevents simultaneous repeated sipping")
	await create_timer(2.7).timeout
	for glass in 3:
		check(session.wine.drink("zacharias_malagousia"), "additional real drink " + str(glass + 2))
		await create_timer(2.7).timeout
	check(session.wine.get_intensity() > .8, "four glasses produce strong intoxication")
	check(float(world.player.get_meta("alcohol_intensity", 0.0)) > .8 and session.wine.overlay.visible, "actor and visible HUD receive intoxication")
	await photo("06-drunk-interior")
	if not check(await cross_threshold(false), "walk to exit and leave while intoxicated"): finish(); return
	check(session.wine.get_intensity() > .5 and session.state.place_id.is_empty(), "alcohol persists after leaving")
	await photo("07-drunk-exterior")
	var outside_wine: Dictionary = session.wine.snapshot()
	var outside_wallet: Dictionary = session.state.economy.snapshot()
	check(not session.wine.buy("ancla_merlot") and session.wine.snapshot() == outside_wine and session.state.economy.snapshot() == outside_wallet, "remote purchase rejected without mutation")
	# no-save captura o estado do mundo, mas não grava o slot do usuário. Persiste
	# o snapshot resultante explicitamente em outra fixture isolada validada.
	check(session.save_game(), "session captures wine state")
	var full: Dictionary = session.state.snapshot()
	full.combat = world.gameplay.snapshot()
	var stored_stock: Dictionary = session.wine.snapshot().servings
	var stored_alcohol: float = session.wine.get_intensity()
	var restored_path := FIXTURE.write_fixture(folder, "restore.json", full)
	if not check(not restored_path.is_empty(), "wine persists in a validated isolated file"): finish(); return
	world.queue_free()
	await process_frame
	await process_frame
	save_path = restored_path
	await boot()
	session = world.session
	check(not world.production.save_invalid and session.wine.snapshot().servings == stored_stock, "cold Main restore preserves purchased servings")
	check(session.wine.get_intensity() > .3 and session.wine.get_intensity() <= stored_alcohol, "cold Main restore resumes intoxication")
	check(session.position_clear(world.player.global_position), "restored outside player is supported and clear")
	check(await cross_threshold(true), "intoxicated reentry uses the same live access")
	check(await walk(session.room.interaction_points.service + Vector3.UP * .04), "restored player reaches Nelson again")
	check(not session.wine.claim_gift(), "cold restore does not duplicate gift")
	var paused_wine: Dictionary = session.wine.snapshot()
	paused = true
	await create_timer(.5, true).timeout
	check(session.wine.snapshot() == paused_wine, "pause freezes intoxication and sip cooldown")
	paused = false
	var retained_stock: Dictionary = session.wine.snapshot().servings
	world.gameplay.damage_environment(1000.0)
	check(world.gameplay.health == 0 and session.rescue_pending, "actual gameplay death starts rescue from the wine shop")
	check(not session.wine.drink("zacharias_malagousia") and session.wine.snapshot().servings == retained_stock, "dead player cannot consume wine during rescue")
	var rescue_end := Time.get_ticks_msec() + 30000
	while (world.gameplay.health <= 0 or session.rescue_pending or session.respawn_busy) and Time.get_ticks_msec() < rescue_end: await physics_frame
	check(world.gameplay.health > 0 and not session.rescue_pending and not session.respawn_busy and session.state.place_id.is_empty(), "real rescue finishes outdoors")
	check(session.wine.get_intensity() == 0 and session.wine.snapshot().servings == retained_stock, "real rescue clears impairment while preserving wine stock")
	check(not session.wine.overlay.visible and float(world.player.get_meta("alcohol_intensity", 1)) == 0, "recovery removes actor and HUD effects")
	check(session.position_clear(world.player.global_position) and not world.player.input_locked and world.player.is_physics_processing(), "rescued player has support, collision and control")
	await photo("08-recovered")
	finish()

func boot() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", save_path)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play: return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.0
	world.session.weather.weather_timer = 3600
	await create_timer(1).timeout

func walk(point: Vector3) -> bool:
	var end := Time.get_ticks_msec() + 12000
	while _flat_distance(world.player.global_position, point) > .2 and Time.get_ticks_msec() < end:
		var direction: Vector3 = point - world.player.global_position
		direction.y = 0
		world.player.automatic_direction = direction.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var ok := _flat_distance(world.player.global_position, point) < .35
	if not ok: print("CELLAR_WALK_BLOCKED actual=", world.player.global_position, " expected=", point)
	return ok

func cross_threshold(entering: bool) -> bool:
	var expected := CELLAR_ID if entering else ""
	var point: Vector3
	if entering:
		var definition := PLACES.get_definition(CELLAR_ID)
		point = definition.entry_position + Vector3.UP * .04
	else:
		point = world.session.room.exit_position + Vector3.UP * .04
	if not await walk(point): return false
	if not await world.session.interact(): return false
	var end := Time.get_ticks_msec() + 15000
	while world.session.state.place_id != expected and Time.get_ticks_msec() < end:
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	while world.session.is_transition_blocked() and Time.get_ticks_msec() < end: await physics_frame
	await create_timer(.7).timeout
	return world.session.state.place_id == expected and not world.session.is_transition_blocked()

func _flat_distance(a: Vector3, b: Vector3) -> float: return Vector2(a.x - b.x, a.z - b.z).length()

func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "photo saved: " + label)

func temporal_capture() -> void:
	var directory := folder.path_join("temporal")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var original_limit := Engine.max_fps
	var original_speed: float = world.player.speed
	Engine.max_fps = 30
	world.player.speed = .40
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < 30000000:
		var seconds := (Time.get_ticks_usec() - start) / 1000000.0
		world.player.automatic_direction = Vector3.FORWARD if seconds >= 10 and seconds < 15 else Vector3.BACK if seconds >= 15 and seconds < 20 else Vector3.ZERO
		await RenderingServer.frame_post_draw
		var ticks := Time.get_ticks_usec()
		var filename := "%05d.jpg" % temporal.size()
		var saved := root.get_texture().get_image().save_jpg(directory.path_join(filename), .88)
		temporal.append({"frame":Engine.get_frames_drawn(), "time_us":ticks - start, "file":filename, "saved":saved == OK})
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = original_speed
	Engine.max_fps = original_limit
	check(temporal.size() > 100 and temporal[-1].time_us >= 29900000, "continuous 30s interior frame sequence captured")

func finish(code := -1) -> void:
	var current := FIXTURE.source_fingerprint()
	var report := {"checks":checks, "failures":failures, "source_stable":original_source == current, "source_before":original_source, "source_after":current, "temporal":temporal, "engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "notes":"Main real C# with isolated saves. Walking to compact transfer marker and actual entry/exit interactions, walking aisles, UI purchase and runtime drinking, conversations, drunk exit, cold restore, paused game, actual fatal gameplay damage and rescue. Optional 30s every-render-frame JPEG sequence at a temporary30FPS cap:10s still,5s forward,5s return,10s still. Capture/readback cost is not FPS evidence. Wallet/health initialized by fixture; story missions were not replayed."}
	if not folder.is_empty(): FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CELLAR_SESSION_RESULT ", folder, " checks=", checks, " failures=", failures)
	quit(code if code >= 0 else 0 if failures.is_empty() else 1)
