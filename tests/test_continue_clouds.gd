extends "res://tests/test_sky_menu.gd"
## Click while the real save is still loading, including a pending different slot.
const OUTPUT := "res://evidence/continue-clouds-20260928"

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
	for replace_pending in [false, true]:
		var label := "different-slot" if replace_pending else "same-slot"
		var menu = load("res://ui/MainMenu.tscn").instantiate()
		root.add_child(menu)
		current_scene = menu
		menu.sky.boot_path(launch.slot_path("slot_01"))
		check(menu.sky.loading, label + " click precedes world readiness")
		var slot := "slot_02" if replace_pending else "slot_01"
		var hash_before := FileAccess.get_sha256(launch.slot_path(slot))
		menu._start(slot, false)
		check(menu.starting and not menu.sky.ui_layer.visible, label + " menu disappears at click")
		check(menu.sky.clouds.visible, label + " clouds cover immediately")
		check(is_equal_approx(menu.sky.material.get_shader_parameter("coverage"), 1.0), label + " pending world fully covered")
		var clock_before: float = menu.sky.elapsed
		var finish := Time.get_ticks_msec() + 180000
		var sampled := false
		var lost_cover := false
		var returned_ui := false
		while is_instance_valid(menu) and Time.get_ticks_msec() < finish:
			await process_frame
			if not is_instance_valid(menu): break
			lost_cover = lost_cover or not menu.sky.clouds.visible
			returned_ui = returned_ui or menu.sky.ui_layer.visible
			if not sampled and menu.sky.elapsed > clock_before + 0.3:
				sampled = true
				check(menu.sky.elapsed > clock_before, label + " cloud clock advances while waiting")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUTPUT.path_join(label + "-loading.png"))
		check(not lost_cover and not returned_ui, label + " no menu flash or missing cover during replacement")
		check(sampled, label + " observed moving cloud phase")
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
	# Failure recovery must restore the menu rather than strand a hidden panel.
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	menu.sky.begin_continue()
	menu.sky._boot_failed()
	check(not await menu.sky.continue_game(), "failed preview reports failure")
	await menu.sky.discard_preview()
	menu.sky.cancel_continue()
	check(menu.sky.ui_layer.visible and not menu.sky.clouds.visible and menu.presentation.background.visible, "failed transition restores menu")
	menu.queue_free()
	await process_frame
	print("CONTINUE_CLOUDS ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)
