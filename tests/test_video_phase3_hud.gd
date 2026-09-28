extends SceneTree
## Real boarding/minimap and isolated on-disk autosave feedback regression.
var world
var checks := 0
var failures: Array[String] = []
var label := "after"
var output_dir := ""

func _initialize() -> void: run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	print("VIDEO_HUD ", "PASS " if ok else "FAIL ", text)
	if not ok: failures.append(text)

func frames(count: int) -> void:
	for i in count: await physics_frame

func check_world_marker() -> void:
	var session = world.session
	check(session.marker.update_position == session._update_world_indicator and session.marker.process_priority > world.camera.process_priority,"marker updates after camera, outside text timer")
	check(await session.enter_place("maciota",false,"maciota"),"real Maciota room available")
	if session.state.place_id != "maciota": return
	session.state.intro.stage = "meet_maciota"
	world.camera.set_process(false)
	var previous := Vector2.INF
	var follows := true
	for _i in 5:
		world.camera.position.x += .2
		await process_frame
		await process_frame
		var expected: Vector2 = world.camera.unproject_position(session.room.interaction_points.maciota+Vector3.UP*.06)
		follows = follows and session.marker.visible and session.marker.position.distance_to(expected) < .1 and session.marker.position != previous
		previous = session.marker.position
	check(follows,"world marker follows each actual process frame as camera moves")
	check(not session.state.weapons_allowed(),"garage weapon restriction preserved")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--output-dir="): output_dir = arg.trim_prefix("--output-dir=")
	if output_dir.is_empty():
		push_error("Requires --output-dir=<isolated evidence directory>")
		quit(2)
		return
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
	check(world.production.no_save, "personal save disabled at startup")
	if "--marker-only" in OS.get_cmdline_user_args():
		await check_world_marker()
		world.queue_free()
		await frames(3)
		print("WORLD_MARKER_RESULT checks=",checks," failures=",failures.size())
		quit(0 if failures.is_empty() else 1)
		return
	world.production.set_population(0)
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.session.weather.time_of_day = .45
	if "--death-only" in OS.get_cmdline_user_args():
		await check_boarding_death()
		print("VIDEO_HUD_DEATH checks=", checks, " failures=", failures.size())
		world.queue_free()
		await frames(6)
		quit(0 if failures.is_empty() else 1)
		return
	var session = world.session
	var map = world.hud.minimap
	var car = world.driving.car
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .35)
	await frames(3)
	map.refresh()
	check(map.visible, "map visible before boarding")
	check(world.driving.interact(), "real boarding admitted")
	await check_boarding("entry")
	check(world.driving.occupied, "boarding reaches occupied state")
	map.refresh()
	check(map.visible and map.center.distance_to(Vector2(car.global_position.x, car.global_position.z)) < .1, "occupied map follows actual vehicle")
	car.stop_boarding_motion()
	check(world.driving.leave(), "real exit admitted")
	await check_boarding("exit")
	check(not world.driving.occupied and world.player.visible, "exit restores visible pedestrian")
	map.refresh()
	check(map.visible, "map visible after exit")
	world.player.input_locked = true
	map.refresh()
	check(not map.visible, "unrelated movement lock still hides map")
	world.player.input_locked = false
	session.modal = true
	map.refresh()
	check(not map.visible, "modal hides map")
	session.modal = false
	paused = true
	map.refresh()
	check(not map.visible, "pause hides map")
	paused = false
	map.refresh()
	check(map.visible, "map returns after modal and pause")
	await check_saves()
	await check_forced_death()
	await check_boarding_death()
	print("VIDEO_HUD checks=", checks, " failures=", failures.size())
	world.queue_free()
	await frames(6)
	quit(0 if failures.is_empty() else 1)

func check_boarding(kind: String) -> void:
	var sampled := 0
	var hidden := 0
	for i in 240:
		await physics_frame
		if not world.driving.is_body_transition_active(): break
		world.hud.minimap.refresh()
		sampled += 1
		if not world.hud.minimap.visible: hidden += 1
		if sampled == 8: await capture(kind + "-minimap")
	check(sampled > 8, kind + " samples real body transition")
	check(hidden == 0, kind + " map stays visible in every sampled frame (%d/%d hidden)" % [hidden, sampled])
	check(not world.driving.is_body_transition_active(), kind + " completes within original budget")

func check_saves() -> void:
	var session = world.session
	var controller = world.production
	var original_store = controller.store
	var isolated_store = preload("res://runtime/SaveStore.gd").new()
	isolated_store.path = output_dir.path_join(label + "-isolated-save-%d.json" % Time.get_ticks_usec())
	check(isolated_store.path != original_store.path and not isolated_store.path.begins_with("user://"), "disk saves target isolated evidence file")
	controller.store = isolated_store
	controller.no_save = false
	session.show_message("Mensagem funcional de controle")
	check(session.save_game(), "automatic save succeeds on real disk")
	check(session.notice.text == "Mensagem funcional de controle", "autosave preserves functional notice")
	world.hud.refresh_from_state()
	await frames(18)
	await capture("autosave-feedback")
	var restored = preload("res://runtime/GameState.gd").new()
	check(isolated_store.load_into(restored).get("ok", false), "quiet save remains readable")
	var manual := InputEventKey.new()
	manual.physical_keycode = KEY_F5
	manual.pressed = true
	session._input(manual)
	check(session.notice.text == "Mensagem funcional de controle" and session.get_node("SaveFeedback/Indicator").visible, "manual F5 confirms in corner without replacing notice")
	session.show_message("Mensagem funcional de controle")
	world.pause_panel.pause_game()
	world.pause_panel.get_node("%BtnSaveGame").pressed.emit()
	check(not paused and session.notice.text == "Mensagem funcional de controle", "pause menu save resumes without central save message")
	# A real filesystem error must still be reported for automatic saves.
	isolated_store.path = output_dir.path_join("missing-parent-%d" % Time.get_ticks_usec()).path_join("blocked/progress.json")
	var blocker_path: String = isolated_store.path.get_base_dir().get_base_dir()
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("This file intentionally prevents creating the save directory.")
		blocker.close()
	check(blocker != null, "isolated filesystem failure fixture created")
	check(not session.save_game() and session.last_save_error.begins_with("Não foi possível salvar") and session.get_node("SaveFeedback/Indicator").failed, "automatic save failure uses corner indicator")
	check(session.notice.text == "Mensagem funcional de controle", "disk failure does not replace central gameplay notice")
	await capture("save-error")
	controller.no_save = true
	controller.store = original_store

func check_forced_death() -> void:
	world.gameplay.health = 100
	world.gameplay.armor = 50
	world.player.teleport(world.player.global_position * Vector3(1, 0, 1) + Vector3(0, -15, 0))
	world.session._process(0.0)
	check(world.session.rescue_pending, "fall out of world starts actual rescue")
	check(world.gameplay.health == 0 and world.player.dead and world.player.input_locked, "forced death establishes dead actor and health immediately")
	check(world.hud.health_bar.value == 0, "death presentation never starts over full-health HUD")
	await capture("forced-death")
	for i in 600:
		await physics_frame
		if not world.session.rescue_pending and not world.session.respawn_busy: break
	check(not world.session.rescue_pending and not world.session.respawn_busy, "forced death completes rescue")
	check(world.gameplay.health == 100 and not world.player.dead and not world.player.input_locked, "rescue restores living controllable actor")
	check(world.player.global_position.y > -1 and world.player.visible, "rescue returns above actual exterior floor")

func check_boarding_death() -> void:
	var car = world.driving.car
	world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .35)
	await frames(3)
	check(world.driving.interact(), "ordinary damage fixture begins actual boarding")
	await frames(8)
	check(world.driving.is_body_transition_active(), "ordinary damage occurs during body transition")
	world.gameplay.damage_player(1000)
	check(world.gameplay.health == 0 and world.player.dead and world.session.rescue_pending, "ordinary damage starts consistent death")
	check(not world.driving.is_body_transition_active() and not world.driving.occupied, "death cancels boarding and ownership presentation")
	check(world.player.collision_layer == 0 and world.player.collision_mask == 0 and not world.player.is_physics_processing(), "cancelled boarding cannot restore dead-body collision")
	check(world.hud.health_bar.value == 0, "ordinary death HUD is zero in the damage frame")
	for i in 600:
		await physics_frame
		if not world.session.rescue_pending and not world.session.respawn_busy: break
	check(world.gameplay.health == 100 and not world.player.dead and world.player.is_physics_processing(), "ordinary rescue restores living physics")
	check(world.player.collision_layer == 2 and world.player.collision_mask == 7 and not world.player.input_locked, "ordinary rescue restores collision and control")

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output_dir.path_join(label + "-" + name + ".png"))
	check(result == OK, "capture " + name)
