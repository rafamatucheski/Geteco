extends "res://tests/test_video_phase3_hud.gd"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	output_dir = "res://evidence/save-indicator/" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(output_dir)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main ready")
	if not failures.is_empty(): quit(1); return
	for i in 600:
		var curtain := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): curtain = true
		if not curtain: break
		await process_frame
	var session = world.session
	check(session.save_game() and session.get_node_or_null("SaveFeedback") == null, "no-save mode never indicates disk success")
	await check_saves()
	await check_checkpoint_policy()
	var indicator = session.get_node_or_null("SaveFeedback/Indicator")
	check(indicator != null, "real disk save creates feedback")
	if indicator != null:
		await create_timer(1.6).timeout
		check(not indicator.visible and not indicator.is_processing(), "feedback expires and stops processing")
		indicator.acknowledge()
		var initial_angle: float = indicator.angle
		paused = true
		await create_timer(0.15).timeout
		check(indicator.visible and indicator.angle != initial_angle, "indicator rotates even while paused")
		paused = false
		await create_timer(1.6).timeout
		world.production.save_invalid = true
		check(not session.save_game() and not indicator.visible, "blocked save does not display success")
	world.queue_free()
	await frames(3)
	print("SAVE_INDICATOR_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func check_checkpoint_policy() -> void:
	var session = world.session
	var controller = world.production
	var original_store = controller.store
	var isolated = preload("res://runtime/SaveStore.gd").new()
	isolated.path = output_dir.path_join("checkpoints.json")
	controller.store = isolated
	controller.no_save = false
	check(session.save_game(), "safe checkpoint published")
	check(session._intro_interact("maciota"), "intro begins after pre-mission checkpoint")
	var before := FileAccess.get_file_as_string(isolated.path)
	check(JSON.parse_string(before).intro.phase == "meet_maciota", "intro restart is before acceptance")
	check(session._intro_interact("mechanic") and session._intro_interact("workbench"), "intro objectives advance in memory")
	check(not session.save_game(true) and FileAccess.get_file_as_string(isolated.path) == before, "intro cannot publish intermediate objectives")
	check(session._intro_interact("maciota"), "intro completion accepted")
	check(JSON.parse_string(FileAccess.get_file_as_string(isolated.path)).intro.phase == "complete", "intro completion publishes checkpoint")
	session.close_menu()
	check(session.mission_world.begin("primeiro_giro"), "campaign accepts mission after checkpoint")
	session.close_menu()
	before = FileAccess.get_file_as_string(isolated.path)
	var backup := FileAccess.get_file_as_string(isolated.path + ".bak")
	check(JSON.parse_string(before).campaign.active_id == "", "campaign restart checkpoint has no active mission")
	check(not session.save_game() and not session.save_game(true), "automatic and manual save blocked in mission")
	world.pause_panel.pause_game()
	check(world.pause_panel.get_node("%BtnSaveGame").disabled, "pause save disabled during mission")
	world.pause_panel.resume_game()
	check(session.mission_world._event("bank_receipt_received", "helena"), "first objective advances")
	check(session.mission_world._event("harbor_parcel_collected", "harbor_parcel"), "second objective advances")
	check(FileAccess.get_file_as_string(isolated.path) == before and FileAccess.get_file_as_string(isolated.path + ".bak") == backup, "objectives preserve both checkpoint and backup bytes")
	world.gameplay.stars = 1
	check(session.mission_world._event("maciota_delivery_received", "maciota"), "mission ends while wanted")
	check(session.state.campaign.active_id.is_empty() and FileAccess.get_file_as_string(isolated.path) == before, "completion waits for zero stars")
	for stars in range(1, 7):
		world.gameplay.stars = stars
		check(not session.save_game() and not session.save_game(true), "all save paths reject %d stars" % stars)
	world.pause_panel.pause_game()
	check(world.pause_panel.get_node("%BtnSaveGame").disabled, "pause save disabled while wanted")
	world.pause_panel.resume_game()
	world.gameplay.clear_wanted()
	paused = true
	await create_timer(1.3).timeout
	check(FileAccess.get_file_as_string(isolated.path) == before, "pending autosave waits while paused")
	paused = false
	await create_timer(1.3).timeout
	var restored = preload("res://runtime/GameState.gd").new()
	check(isolated.load_into(restored).get("ok", false) and restored.campaign.snapshot().completed.has("primeiro_giro"), "pending completion checkpoint becomes readable after escape")
	check(restored.campaign.active_id.is_empty() and restored.combat_state.crime_points == 0, "resumed checkpoint contains neither mission attempt nor pursuit")
	check(session._checkpoint_retry.is_stopped(), "pending timer stops after successful publication")
	before = FileAccess.get_file_as_string(isolated.path)
	session.activities.motorsport.mode = "race"
	check(not session.save_game(true), "side race blocks save")
	session.activities.motorsport.mode = ""
	session.activities._data.tow_contract = {"token":"test-active-contract"}
	check(not session.save_game(true), "tow contract blocks save")
	session.activities._data.tow_contract = {}
	session.mountain_progression.race.mode = "race"
	check(not session.save_game(true), "ski race blocks save")
	session.mountain_progression.race.mode = ""
	session.urban_operations.freight.active_bay = 0
	check(not session.save_game(true), "freight delivery blocks save")
	session.urban_operations.freight.active_bay = -1
	check(FileAccess.get_file_as_string(isolated.path) == before, "side activities preserve checkpoint bytes")
	check(session.save_game(true), "manual saving available again after activities")
	var quest = session.urban_operations.get("village_quest")
	check(is_instance_valid(quest), "Tonico quest connected to session")
	if is_instance_valid(quest):
		var origin: Vector3 = world.player.position
		world.player.position = quest.TONICO_POINT
		check(session._perform_urban_action("truckers_village_tonico"), "Tonico acceptance passes through pre-mission checkpoint")
		before = FileAccess.get_file_as_string(isolated.path)
		check(not JSON.parse_string(before).world.urban_operations.truckers_village.started, "Tonico checkpoint precedes acceptance")
		world.player.position = quest.BELT_POINT
		check(session._perform_urban_action("truckers_village_belt"), "Tonico objective advances")
		check(not session.save_game(true) and FileAccess.get_file_as_string(isolated.path) == before, "Tonico progress cannot overwrite checkpoint")
		world.player.position = quest.CRANK_POINT
		check(session._perform_urban_action("truckers_village_crank"), "Tonico second objective advances")
		world.player.position = quest.PUMP_POINT
		check(session._perform_urban_action("truckers_village_repair"), "Tonico completion accepted")
		check(JSON.parse_string(FileAccess.get_file_as_string(isolated.path)).world.urban_operations.truckers_village.completed, "Tonico completion publishes checkpoint")
		world.player.position = origin
	controller.no_save = true
	controller.store = original_store
