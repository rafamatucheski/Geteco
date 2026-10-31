extends "res://tests/test_sky_menu.gd"
## Clica enquanto o save real ainda está carregando, incluindo um slot diferente pendente.
const OUTPUT := "res://evidence/simple-loading-20261002/continue"

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var blocker := InputBlocker.new()
	blocker.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(blocker)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var original := root.get_node("V2Launch")
	root.remove_child(original)
	original.free()
	launch = IsolatedLaunch.new()
	launch.name = "V2Launch"
	launch.folder = OUTPUT.path_join("slots_%d" % Time.get_ticks_usec())
	launch.direct_start_consumed = true
	root.add_child(launch)
	for id in ["slot_01", "slot_02"]:
		var state = load("res://runtime/GameState.gd").new()
		state.world_state.time = .45
		state.set_location("harbor", "")
		var store = load("res://runtime/SaveStore.gd").new()
		store.path = launch.slot_path(id)
		check(store.save(state) == OK, id + " isolated fixture saved")
	for label in ["cold-click", "same-slot", "different-slot"]:
		var replace_pending: bool = label == "different-slot"
		var menu = load("res://ui/MainMenu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		if label != "cold-click":
			menu.sky.boot_path(launch.slot_path("slot_01"))
			check(menu.sky.loading, label + " click precedes world readiness")
		else:
			check(not menu.sky.loading and not is_instance_valid(menu.sky.world), "cold menu has no world before click")
		var slot := "slot_02" if replace_pending else "slot_01"
		var hash_before := FileAccess.get_sha256(launch.slot_path(slot))
		menu._start(slot, false)
		check(menu.starting and menu.sky.curtain.visible, label + " click immediately starts loading fade")
		check(menu.sky.loading_cover.is_visible_in_tree() and menu.sky.loading_cover.modulate.a == 1.0, label + " pending world fully covered")
		var started := Time.get_ticks_msec()
		var finish := Time.get_ticks_msec() + 180000
		var sampled := false
		var lost_cover := false
		var returned_ui := false
		var menu_hidden := false
		var observed_start := false
		while is_instance_valid(menu) and Time.get_ticks_msec() < finish:
			await process_frame
			if not is_instance_valid(menu): break
			if menu.sky.loading:
				lost_cover = lost_cover or not menu.sky.loading_cover.is_visible_in_tree()
				if label == "cold-click" and not observed_start:
					observed_start = true
					check(not menu.sky.ui_layer.visible and menu.sky.curtain._root.modulate.a >= .999,
						"world loading starts only after the loading screen becomes opaque")
			returned_ui = returned_ui or (menu_hidden and menu.sky.ui_layer.visible)
			menu_hidden = menu_hidden or not menu.sky.ui_layer.visible
			if not sampled and Time.get_ticks_msec() > started + 400:
				sampled = true
				check(menu.sky.curtain._root.material == null, label + " loading cover has no animated shader")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT.path_join(label + "-loading.png"))
		check(not lost_cover and not returned_ui, label + " no menu flash or missing cover during replacement")
		check(sampled, label + " observed static loading phase")
		if label == "cold-click": check(observed_start, "cold click actually starts world loading")
		check(not is_instance_valid(menu), label + " reaches gameplay within deadline")
		if is_instance_valid(menu):
			quit(1)
			return
		var world = current_scene
		check(not paused and world.hud.visible and root.get_camera_3d() == world.camera, label + " gameplay and camera released")
		check(world.production.no_save, label + " personal saves protected")
		check(FileAccess.get_sha256(launch.slot_path(slot)) == hash_before, label + " fixture unchanged")
		world.queue_free()
		await process_frame
		await process_frame
	# A recuperação de falha precisa restaurar o menu em vez de deixar um painel escondido preso.
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.sky.begin_continue()
	menu.sky._boot_failed()
	check(not await menu.sky.continue_game(), "failed preview reports failure")
	await menu.sky.discard_preview()
	menu.sky.cancel_continue()
	check(menu.sky.ui_layer.visible and menu.sky.curtain == null and menu.presentation.background.visible, "failed transition restores menu")
	menu.queue_free()
	await process_frame
	print("CONTINUE_STATIC_LOADING ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
