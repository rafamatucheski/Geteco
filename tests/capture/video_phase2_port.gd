extends "res://tests/test_video_phase2_port.gd"
## Actual rendered port interaction photos. This is not a frame-time benchmark.
const OUT := "res://evidence/video-review-phase2-20260924/"

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args() or "--skip-arrival" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for _i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "rendered Main ready")
	if not failures.is_empty():
		await finish()
		return
	for _i in 600:
		var curtain := false
		for child in world.get_children():
			if child.get_script() == preload("res://runtime/StartupCurtain.gd"): curtain = true
		if not curtain: break
		await process_frame
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	await place(GUARD + Vector3(0, 0, .8))
	await photo("port-guard-before-payment", GATE + Vector3(2.1, 1, -.8), 14.0)
	check(world.session.interact(), "guard conversation opens")
	await photo("port-payment-menu", GUARD + Vector3(0, 1, 0), 11.0)
	world.session.state.economy.grant_reward("video_phase2_capture_funds", 100)
	var pay := payment_button()
	check(pay != null, "payment button available")
	if pay != null: pay.pressed.emit()
	await frames(18)
	await photo("port-gate-authorized", GATE + Vector3(1, 1, 0), 13.0)
	check(await walk_to(GATE + Vector3(0, 0, -1.3)), "walk from guard to gate")
	check(await walk_to(GATE + Vector3(0, 0, 3.1)), "walk through authorized gate")
	await photo("port-authorized-visit", GATE + Vector3(0, 1, 1.5), 13.0)
	check(world.session.urban_operations.security.authorized_visit, "paid visit recognized")
	await finish()

func photo(label: String, focus: Vector3, size: float) -> void:
	world.camera.focus_on_store(focus, size, .2)
	await frames(30)
	await RenderingServer.frame_post_draw
	var path := OUT + "after-" + label + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "write " + path)
	print("PORT_PHOTO ", label, " player=", world.player.global_position, " permission=", world.session.urban_operations.security.snapshot())
