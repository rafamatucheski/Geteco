extends "res://tests/test_urban_operations.gd"
## Real Main integration and rendered evidence; never accesses a personal save.
const ART := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const LEISURE := preload("res://gameplay/urban_v1/TruckersVillageLeisure.gd")
const FOLDER := "res://evidence/village-leisure-20260929"
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	super.check(value,label)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	Input.use_accumulated_input = false
	seed(29092026)
	check(await _initialize_world(),"Main loads leisure integration")
	if not failures.is_empty(): quit(1); return
	current_scene = world
	check(world.production.no_save,"Personal save remains isolated")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	session.weather.set_process(false)
	session.weather.time_of_day = .4
	session.weather.weather_state = 0
	session.weather._update()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var leisure = urban.village_leisure
	world.player.teleport(ART.PLAY_POINT+Vector3.UP*.1)
	world.production.region.set_focus(ART.PLAY_POINT)
	world.production.region.prepare_collision_at(ART.PLAY_POINT)
	world.camera.heading = 0
	world.camera.target_size = 23
	world.camera.initialized = false
	await settle(120)
	check(urban.nearest_action().get("target","")==LEISURE.PREFIX+"play","Court prompt is reachable through normal urban dispatcher")
	await shot("court")
	check(session.interact(),"Normal player interaction opens horseshoes")
	check(session.modal and world.player.input_locked and leisure.ui.active,"Modal protects player movement during play")
	await shot("minigame")
	var cancellation := InputEventAction.new()
	cancellation.action = "ui_cancel"
	cancellation.pressed = true
	Input.parse_input_event(cancellation)
	Input.flush_buffered_events()
	await settle(3)
	check(not session.modal and not world.player.input_locked and not leisure.ui.active,"Actual Escape action cancels without stuck modal or lock")
	cancellation.pressed = false
	Input.parse_input_event(cancellation)
	Input.flush_buffered_events()
	var before: Dictionary = session.state.economy.snapshot()
	check(session.interact(),"Round can reopen after cancellation")
	var launched := 0
	var start := Time.get_ticks_msec()
	var captured := false
	while leisure.playing and Time.get_ticks_msec()-start < 15000:
		await process_frame
		if not leisure.playing: break
		if leisure.ui.cooldown <= 0 and leisure.ui.strength >= .68 and leisure.ui.strength <= .72:
			var event := InputEventAction.new()
			event.action = "interact"
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			event = InputEventAction.new()
			event.action = "interact"
			event.pressed = false
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			launched += 1
		if launched == 1 and leisure.ui.cooldown > .40 and leisure.ui.cooldown < .70 and not captured:
			await shot("throw")
			captured = true
	await settle(2)
	print("LEISURE_INPUT launched=",launched," attempts=",leisure.ui.attempts," hits=",leisure.ui.hits," best=",leisure.best_score," playing=",leisure.playing)
	check(not leisure.playing and launched==3 and leisure.best_score==3,"Three real input actions score a perfect round")
	check(leisure._paid(LEISURE.PRIZE_ID),"Completed round deposits unique prize receipt")
	check(not session.modal and not world.player.input_locked,"Completed round restores gameplay controls")
	await shot("perfect-round")
	check(session.save_game(),"FullSession checkpoints the new record")
	var saved: Dictionary = session.state.world_state.urban_operations.duplicate(true)
	check(saved.truckers_village_leisure.best_score==3 and urban.validate_snapshot(saved),"Urban save contains validated record")
	check(urban.restore_snapshot(saved),"Integrated urban checkpoint reloads")
	check(leisure.best_score==3,"Reload preserves secret unlock")
	world.player.teleport(ART.CACHE_POINT+Vector3.UP*.1)
	world.production.region.set_focus(ART.CACHE_POINT)
	world.production.region.prepare_collision_at(ART.CACHE_POINT)
	world.camera.target_size = 17
	world.camera.initialized = false
	await settle(90)
	print("LEISURE_CACHE action=",urban.nearest_action()," opened=",leisure.cache_opened," position=",world.player.position)
	check(urban.nearest_action().get("target","")==LEISURE.PREFIX+"cache","Unlocked cache has reachable prompt")
	await shot("cache-closed")
	check(session.interact(),"Normal player interaction opens cache")
	await settle(30)
	check(leisure.cache_opened and leisure._paid(LEISURE.CACHE_ID),"Cache deposits its unique receipt")
	await shot("cache-open")
	check(not urban.perform(LEISURE.PREFIX+"cache"),"Opened cache cannot be looted twice")
	var paid: Dictionary = session.state.economy.snapshot()
	check(leisure.restore_snapshot({"version":1,"best_score":0,"cache_opened":false}),"Old progress restores safely against current receipts")
	check(leisure.cache_opened and leisure.best_score==3 and session.state.economy.snapshot()==paid,"Receipt reconciliation prevents payout duplication")
	check(not urban.validate_snapshot(_corrupt(saved)),"World save rejects malformed leisure state")
	var old: Dictionary = saved.duplicate(true)
	old.erase("truckers_village_leisure")
	check(urban.validate_snapshot(old),"Existing saves remain compatible without leisure entry")
	# Night screenshot retains the actual village lighting and weather.
	session.weather.time_of_day = .9
	session.weather.weather_state = 1
	session.weather._update()
	await settle(80)
	await shot("night-garden")
	print("VILLAGE_LEISURE_MAIN checks=",checks," failures=",JSON.stringify(failures)," initial_wallet=",JSON.stringify(before)," final_wallet=",JSON.stringify(paid))
	FileAccess.open(FOLDER+"/integration.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _corrupt(data: Dictionary) -> Dictionary:
	var bad := data.duplicate(true)
	bad.truckers_village_leisure.best_score = 7
	return bad

func shot(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(FOLDER+"/"+id+".png")
