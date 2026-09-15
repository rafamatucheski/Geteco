extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func finish_lap(race: Node2D, car: Node2D, seconds: float) -> void:
	if race._state == race.State.RESULT: race._process(5.1)
	car.global_position = race.to_global(race.start_pos)
	car.velocity = Vector2.ZERO
	race._try_start_race(car)
	race._process(3.1)
	check(race._state == race.State.RUNNING, "completed circuit can be raced again")
	for i in race.checkpoints.size() + 1:
		var target: Vector2 = race._get_current_target_position()
		race._previous_position = target - Vector2(90, 0)
		car.global_position = target + Vector2(90, 0)
		race._process(seconds / (race.checkpoints.size() + 1))
	check(race._state == race.State.RESULT, "ordered checkpoints and finish complete the race")

func capture_card(race: Node2D, file_name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	# Let the opening's screen reveal finish before inspecting the event UI.
	await create_timer(0.8).timeout
	var camera := Camera2D.new()
	camera.position = race.to_global(race.start_pos)
	camera.zoom = Vector2(1.4, 1.4)
	root.add_child(camera)
	camera.make_current()
	for layer in get_nodes_in_group("motorsport_card"): layer.visible = false
	race._card.layer.visible = true
	for i in 4: await process_frame
	race.UI.animate(race, race._card, 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "D:/geteco/artifacts/race-records-0910"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(file_name))
	camera.queue_free()

func run() -> void:
	var saves := root.get_node("SaveManager")
	saves._save_dir = OS.get_temp_dir().path_join("race_records_%d" % Time.get_ticks_usec()) + "/"
	saves._save_directory_ready = false
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 8: await process_frame
	world.campaign_controller.skip_cinematic()
	paused = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.get_node("WantedManager").restore({"current_stars": 0, "crime_points": 0})
	var player = world.get_node("Player")
	player.is_in_dialogue = false
	player.is_control_disabled = false
	var car = world.get_node("PlayerCar")
	car.is_driven_by_player = true
	get_first_node_in_group("day_night_manager").time_of_day = 0.9
	var race = get_nodes_in_group("night_race")[0]
	var other = get_nodes_in_group("night_race")[1]
	car.global_position = race.to_global(race.start_pos)
	car.velocity = Vector2.ZERO
	race._process(0.0)
	check(not race._card.title.text.contains("Concluída"), "unplayed circuit is not marked completed")
	check(race._format_time(59.999) == "01:00.00", "record display carries rounded seconds into minutes")
	var money_before: int = player.money
	finish_lap(race, car, 70.25)
	check(is_equal_approx(campaign.get_race_best_time(race.race_id), 70.25), "first finish stores circuit record")
	check(player.money == money_before + race.reward + race.best_time_bonus, "first record earns bonus")
	check(race._card.title.text == "CORRIDA CONCLUÍDA" and race._card.detail.text.contains("Novo recorde"), "finish shows completion and new record")
	check(race._card.hint.text == "Recorde: 01:10.25", "finish shows best time")
	check(campaign.get_race_best_time(other.race_id) < 0.0, "other circuit remains uncompleted")
	check(saves.inspect_slot("autosave").valid, "race completion writes autosave")
	await capture_card(race, "finished.png")
	# Load through the real save manager after clearing runtime progress.
	check(saves.load_game("autosave").success, "race autosave can be loaded")
	campaign.reset_campaign()
	check(saves.apply_pending_save(self), "saved campaign and player are restored")
	# Player.restore releases the controlled vehicle; simulate getting back in.
	car.is_driven_by_player = true
	race._process(5.1)
	car.global_position = race.to_global(race.start_pos)
	race._process(0.0)
	check(race._card.title.text.contains("Concluída") and race._card.detail.text.contains("01:10.25"), "returning to start after load shows completed and saved record")
	check(race._card.hint.text.contains("Correr novamente"), "completed invitation offers replay")
	await capture_card(race, "completed.png")
	money_before = player.money
	finish_lap(race, car, 82.0)
	check(is_equal_approx(race._best_time, 70.25) and player.money == money_before + race.reward, "slower replay preserves record and does not award bonus")
	check(race._card.value.text == "01:22.00" and race._card.hint.text == "Recorde: 01:10.25", "result distinguishes current time from record")
	money_before = player.money
	finish_lap(race, car, 65.0)
	check(is_equal_approx(campaign.get_race_best_time(race.race_id), 65.0) and player.money == money_before + race.reward + race.best_time_bonus, "faster replay replaces record and earns bonus")
	money_before = player.money
	finish_lap(race, car, 65.0)
	check(player.money == money_before + race.reward, "tied time does not earn another record bonus")
	race._process(5.1)
	other._cancel("Teste de cancelamento")
	check(campaign.get_race_best_time(other.race_id) < 0.0, "cancelled race is not completed")
	var saved: Dictionary = campaign.to_save_data()
	saved.erase("race_best_times")
	check(campaign.restore_from_save(saved), "legacy save without per-race records remains compatible")
	race._process(0.0)
	check(race._best_time < 0.0 and not race._card.title.text.contains("Concluída"), "loading legacy save clears records from previous slot")
	campaign.record_race_time(race.race_id, 65.0)
	campaign.reset_campaign()
	race._process(0.0)
	check(race._best_time < 0.0, "new game clears circuit completion")
	saved["race_best_times"] = {"bad": -2, "text": "fast", "zero": 0, "valid": 41.5}
	campaign.restore_from_save(saved)
	check(campaign.race_best_times == {"valid": 41.5}, "invalid record data is discarded")
	print("RACE_RECORDS failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
