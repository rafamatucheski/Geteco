extends SceneTree
## Targeted integration edges, not a replacement for the full normal fishing session.
## Uses real production, paid entries, touch events and phase transitions. Explicit
## fixtures select a 14 kg fish and shorten waiting/fight progress to reach edges.
## Run with --no-save --touch-controls; all files stay in an isolated evidence folder.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
const FISH_STATE := preload("res://activities/fishing/FishingState.gd")
var world
var fishing
var touch
var folder := ""
var checks := 0
var failures: Array[String] = []
var _finishing := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("FISHING_EDGES ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func press(action: String, down := true) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = down
	world.session._input(event)

func finger(action: String, down: bool, index := 81) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = touch.buttons[action].rect.get_center() if down else Vector2.ZERO
	event.pressed = down
	root.push_input(event, true)
	await process_frame
	await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func until_phase(target: String, seconds := 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while fishing.active and fishing.phase != target and Time.get_ticks_msec() < deadline:
		await physics_frame
	return fishing.active and fishing.phase == target

func until_closed(seconds := 3.5) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while fishing.active and Time.get_ticks_msec() < deadline: await physics_frame
	return not fishing.active

func start_attempt(tier: int) -> bool:
	for frame in 4: await physics_frame
	var started: bool = fishing.start(tier)
	check(started and fishing.controls_locked(), "paid entry equips rod at the real fishing station")
	if not started or not fishing.controls_locked(): return false
	touch._refresh()
	check(touch.playable and touch.fishing and touch.buttons.has("interact") and touch.buttons.has("exit_vehicle"), "touch fishing controls remain usable while pedestrian is locked")
	return true

func hook_large_fish(use_touch := false) -> bool:
	if use_touch: await finger("interact", true)
	else: press("interact")
	check(fishing.phase == "charging", "held action starts charging")
	await create_timer(.12).timeout
	if use_touch: await finger("interact", false)
	else: press("interact", false)
	check(fishing.phase == "casting", "release launches the real cast")
	# Selection fixture: valid maximum specimen, chosen after the production roll.
	fishing.current_fish = {"id":"pirarara", "grams":14000}
	if not (await until_phase("waiting")):
		check(false, "cast reaches waiting")
		return false
	await create_timer(.2).timeout
	# Skip only random bite delay. The normal waiting transition opens the bite.
	fishing._phase_time = 0.0
	if not (await until_phase("bite")):
		check(false, "float opens the hook window")
		return false
	if use_touch: await finger("interact", true)
	else: press("interact")
	check(fishing.phase == "hooking", "hook input enters the hook animation")
	return fishing.phase == "hooking"

func reach_landing() -> bool:
	if not (await until_phase("reeling")):
		check(false, "hook animation reaches reeling")
		return false
	await create_timer(.25).timeout
	fishing._update_hud()
	await capture("large-fish-reeling-%d" % int(fishing.serial))
	# Boundary fixture: full-session runner already covers the sustained fight.
	# Keep actual Fight.update and the landing transition under test.
	fishing.fight.progress = .99
	fishing.fight.tension = .45
	press("interact")
	var landed := await until_phase("landing")
	check(landed, "reeling completes into extraction, before awarding the fish")
	return landed

func expect_released(label: String) -> void:
	check(not fishing.active and not world.player.input_locked, label + " releases the player")
	check(world.get_viewport().get_camera_3d() == world.camera and not world.camera.locked, label + " restores the normal camera")
	check(fishing._rod == null and fishing._hud == null, label + " releases fishing presentation owners")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--touch-controls" not in OS.get_cmdline_user_args():
		push_error("Fishing edges requires --no-save --touch-controls")
		quit(2)
		return
	create_timer(300).timeout.connect(func():
		if not _finishing:
			check(false, "targeted fishing edges timed out")
			finish.call_deferred()
	)
	folder = FIXTURE.output_dir("fishing-redesign-edges")
	var data := FIXTURE.full_snapshot(LOCATION.ENTRY + Vector3.UP * .1, true)
	data.economy.balance = 500
	var path := FIXTURE.write_fixture(folder, "isolated-save.json", data)
	check(not path.is_empty(), "isolated valid save prepared")
	if path.is_empty(): await finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled:
		await physics_frame
		if _finishing: return
	# Apply after startup settings, which may restore the user's ultrawide window.
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	print("FISHING_EDGES_ENV ", JSON.stringify({"pid":OS.get_process_id(), "engine":Engine.get_version_info().string, "display":DisplayServer.get_name(), "renderer":RenderingServer.get_current_rendering_method(), "adapter":RenderingServer.get_video_adapter_name(), "viewport":str(root.size), "window":str(DisplayServer.window_get_size()), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "locale":TranslationServer.get_locale()}))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.production.region.set_focus(LOCATION.ENTRY + Vector3.UP * .1)
	world.session.fishing_runtime.refresh()
	await create_timer(1).timeout
	for line in 12:
		if not world.session.dialogue_open: break
		press("interact")
		await physics_frame
	check(not world.session.modal, "fixture epilogue releases controls")
	fishing = world.session.fishing
	var site = world.session.fishing_runtime.site
	touch = world.find_child("AndroidControls", true, false)
	check(is_instance_valid(site) and is_instance_valid(touch), "production fishing venue and real touch overlay exist")
	if not is_instance_valid(site) or not is_instance_valid(touch): await finish(); return
	var point: Vector3 = site.fishing_spots()[0].position + Vector3.UP * .03
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	for frame in 12: await physics_frame
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "production C# router is loaded")
	var count_before: int = fishing.snapshot().catches

	# Hooking cancellation through actual mobile buttons, without a catch or prize.
	if not (await start_attempt(0)) or not (await hook_large_fish(true)): await finish(); return
	await finger("interact", false)
	fishing._update_hud()
	check(str(fishing._hud.state.action_key) == "Pescar", "touch HUD names the visible Pescar button")
	await capture("touch-hooking")
	await finger("exit_vehicle", true, 82)
	await finger("exit_vehicle", false, 82)
	expect_released("hooking cancellation")
	check(int(fishing.snapshot().catches) == count_before and fishing.snapshot().rewards.is_empty(), "cancelled hook awards neither fish nor prize")
	check(world.session.state.economy.balance == 490, "cancelled hook costs only its entry")

	# Cancellation during extraction must not persist the still-unlanded fish.
	if not (await start_attempt(0)) or not (await hook_large_fish()) or not (await reach_landing()): await finish(); return
	await create_timer(.65).timeout
	check(fishing.phase == "landing" and int(fishing.snapshot().catches) == count_before, "partially extracted fish has not been persisted")
	await capture("landing-before-cancel")
	press("exit_vehicle")
	expect_released("landing cancellation")
	check(int(fishing.snapshot().catches) == count_before and fishing.snapshot().rewards.is_empty(), "cancelled landing awards neither fish nor prize")
	check(world.session.state.economy.balance == 480, "cancelled landing costs only its entry")

	# Free catch stays on screen for inspection of the large model and result card.
	if not (await start_attempt(-1)) or not (await hook_large_fish()) or not (await reach_landing()): await finish(); return
	var fish_id: int = fishing._rod._fish.get_instance_id()
	await create_timer(.9).timeout
	await capture("large-fish-extraction")
	if not (await until_phase("caught")):
		check(false, "large fish reaches caught")
		await finish(); return
	check(fishing._rod._fish.get_instance_id() == fish_id, "one fish model survives reeling and extraction")
	check(int(fishing.snapshot().catches) == count_before + 1 and fishing.best == 14000, "large free catch is persisted exactly once at 14 kg")
	await create_timer(.25).timeout
	await capture("large-fish-caught-touch")
	check(fishing._hud.state.catch_name == "Pirarara" and fishing._hud.state.catch_grams == 14000 and fishing._hud.state.catch_record, "result HUD carries large species, weight and new record")
	press("exit_vehicle")
	press("exit_vehicle", false)
	check(fishing.active and fishing.phase == "releasing" and fishing._rod._fish.get_instance_id() == fish_id, "caught cancellation releases the same held fish before closing")
	await create_timer(.4).timeout
	check(fishing.active and world.player.input_locked, "caught cancellation preserves presentation ownership during release")
	check(await until_closed(), "caught cancellation completes after its release animation")
	expect_released("caught cancellation")
	check(world.session.state.economy.balance == 470, "free fishing grants no tournament prize")

	# Expiry preserves the earned fish, then waits for choice and its animation.
	if not (await start_attempt(0)) or not (await hook_large_fish()) or not (await reach_landing()): await finish(); return
	fishing.remaining = .04
	await create_timer(.3).timeout
	check(fishing.active and fishing.phase == "landing" and is_zero_approx(fishing.remaining), "zero clock preserves extraction already in progress")
	check(int(fishing.snapshot().catches) == count_before + 1 and world.session.state.economy.balance == 460, "zero-clock extraction has no premature fish or prize")
	await capture("zero-clock-landing")
	if not (await until_phase("caught")):
		check(false, "zero-clock extraction reaches the catch decision")
		await finish(); return
	# Cross the former automatic 3.5 second dismissal deadline.
	await create_timer(3.7).timeout
	check(fishing.active and fishing.phase == "caught" and world.player.input_locked, "zero-clock catch waits for an explicit decision")
	check(int(fishing.snapshot().catches) == count_before + 2 and world.session.state.economy.balance == 460, "waiting for a decision records the fish once without paying the prize")
	press("reload")
	press("reload", false)
	check(fishing.active and fishing.phase == "releasing", "release action starts the zero-clock catch animation")
	await create_timer(.4).timeout
	check(fishing.active and world.session.state.economy.balance == 460, "zero-clock prize waits for the release animation")
	check(await until_closed(), "zero-clock release completes before closing the tournament")
	check(not fishing.active and fishing.last_result.get("finished", false) and fishing.last_result.get("won", false), "resolved zero-clock catch settles the earned win")
	check(int(fishing.snapshot().catches) == count_before + 2 and world.session.state.economy.balance == 560, "resolved catch grants exactly one fish and one 100 prize")
	check(FISH_STATE.claim(world.session.state.world_state, world.session.state.economy) == 0, "settled prize cannot be claimed twice")
	expect_released("zero-clock completion")
	check(FISH_STATE.validate_world(world.session.state.world_state, world.session.state.economy.snapshot()), "all edge outcomes preserve fish and wallet invariants")
	await record_regime("day", .45)
	await record_regime("night", .93)
	await finish()

func record_regime(regime: String, time_of_day: float) -> void:
	if DisplayServer.get_name() == "headless":
		check(false, regime + " temporal evidence requires a rendered window")
		return
	world.session.weather.time_of_day = time_of_day
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	if not (await start_attempt(-1)): return
	fishing._rng.seed = 12345
	await create_timer(.3).timeout
	var frame_folder := folder.path_join(regime + "-sequence")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_folder))
	var old_cap := Engine.max_fps
	Engine.max_fps = 30
	var frames: Array[Dictionary] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var reel := false
	while fishing.active and previous - started < 32000000:
		# Same seed and inputs as the normal session: preserve naturally rolled size.
		match str(fishing.phase):
			"ready": press("interact"); reel = true
			"charging":
				if fishing._charge > .7: press("interact", false); reel = false
			"bite": press("interact"); reel = true
			"reeling":
				if reel and fishing.fight.tension > .72: press("interact", false); reel = false
				elif not reel and fishing.fight.tension < .30: press("interact"); reel = true
			"caught":
				if reel: press("interact", false); reel = false
				if fishing._phase_time >= .6:
					press("reload")
					press("reload", false)
			"missed", "line_broke":
				if reel: press("interact", false); reel = false
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		root.get_texture().get_image().save_jpg(frame_folder.path_join("frame-%05d.jpg" % frames.size()), .82)
		frames.append({"frame":frames.size(), "ms":float(now-started)/1000.0, "interval_ms":float(now-previous)/1000.0, "phase":fishing.phase, "fish":str(fishing._rod._fish.global_position) if is_instance_valid(fishing._rod) else "", "species":str(fishing.current_fish.get("id", "")), "grams":int(fishing.current_fish.get("grams", 0)), "tension":fishing.fight.tension, "fight_hint":fishing._fight_hint})
		previous = now
	Engine.max_fps = old_cap
	FileAccess.open(folder.path_join(regime + "-sequence.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"every_rendered_frame":true,"fps_cap_for_capture":30,"performance_evidence":false,"weather":"clear","time_of_day":time_of_day,"seed":12345,"fish_selection":"natural roll"}, "\t"))
	check(frames.size() > 0 and float(frames.back().ms) >= 32000, "continuous rendered " + regime + " sequence covers at least 32 seconds")
	print("FISHING_TEMPORAL_SEQUENCE ", regime, " ", folder, " frames=", frames.size())
	press("exit_vehicle")
	press("exit_vehicle", false)
	check(await until_closed(), regime + " sequence exit completes any catch animation")
	expect_released(regime + " sequence cancellation")

func finish() -> void:
	if _finishing: return
	_finishing = true
	if is_instance_valid(touch): touch.release_all()
	if is_instance_valid(fishing) and fishing.active: fishing.cancel_attempt("test_teardown")
	if not folder.is_empty():
		FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "fixtures":["14 kg Pirarara", "skip random bite delay", "fight progress .99", "tournament clock .04 during landing"]}, "\t"))
	print("FISHING_EDGES_RESULT ", folder, " checks=", checks, " failures=", failures)
	print("FISHING_EDGES_PROCESS ", JSON.stringify({"pid":OS.get_process_id(), "nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "objects":Performance.get_monitor(Performance.OBJECT_COUNT), "resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "static_memory":OS.get_static_memory_usage(), "fps_observed":Performance.get_monitor(Performance.TIME_FPS), "performance_evidence":false}))
	if is_instance_valid(world): world.queue_free()
	for frame in 8: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	quit(0 if failures.is_empty() else 1)
