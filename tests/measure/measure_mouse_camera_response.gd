extends "res://tests/measure/measure_combat.gd"
## Rendered production integration; no saves, real input dispatch, bounded phases.
var failures: Array[String] = []
var temporal: Array = []
var output := "res://evidence/mouse-camera-20261011/integration"
var functional_only := false

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func button(index: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	var mask: int = Input.get_mouse_button_mask()
	event.button_mask = mask | (1 << (index - 1)) if pressed else mask & ~(1 << (index - 1))
	event.position = root.get_final_transform() * root.get_mouse_position()
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func _run() -> void:
	functional_only = "--functional-only" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	create_timer(240).timeout.connect(func(): push_error("Mouse camera integration timeout"); quit(2))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Production session did not become ready")
		quit(2)
		return
	gameplay = world.gameplay
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	controls.using_gamepad = false
	gameplay.state.economy.activate_arsenal_cheat()
	gameplay.state.equip_weapon("pistol")
	await frames(6)
	check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN, "Gameplay confines the invisible cursor")
	var screen := root.get_visible_rect().size * Vector2(0.72, 0.45)
	root.warp_mouse(screen)
	button(MOUSE_BUTTON_RIGHT, true)
	await frames(6)
	check(gameplay.aim_feedback_active(), "Actual right mouse press activates aim")
	await screenshot("manual-aim")
	button(MOUSE_BUTTON_RIGHT, false)
	await frames(3)
	check(not gameplay.aim_feedback_active(), "Actual right mouse release stops aim")
	for cycle in 5:
		button(MOUSE_BUTTON_RIGHT, true)
		await frames(2)
		check(gameplay.aim_feedback_active(), "Aim press responds in cycle %d" % cycle)
		button(MOUSE_BUTTON_RIGHT, false)
		await frames(2)
		check(not gameplay.aim_feedback_active(), "Aim release responds in cycle %d" % cycle)
	gameplay.customization["hunting_rifle"] = {"owned":true, "installed":true, "owned_parts":["scope_2x"], "parts":{"scope":"scope_2x"}}
	gameplay.state.equip_weapon("hunting_rifle")
	button(MOUSE_BUTTON_RIGHT, true)
	await frames(6)
	check(gameplay.scope_active(), "Scope activates with right button")
	# O comportamento na borda do botão foi testado acima. Fixa a ação segurada no limite
	# de física para esta longa observação de estabilidade (o foco do desktop pode mudar).
	var hold_aim := func() -> void: Input.action_press("aim")
	physics_frame.connect(hold_aim)
	var tracking := {"last": world.camera.focus - world.player.get_global_transform_interpolated().origin, "max_step": 0.0, "all_scoped": true}
	var record := func(seconds: float) -> void:
		# Fixa o estímulo durante toda a observação, como o benchmark de varredura
		# faz. Senão um ponteiro do desktop pode se mover durante uma rodada longa sem supervisão.
		root.warp_mouse(screen)
		var focus: Vector3 = world.camera.focus
		var player_position: Vector3 = world.player.get_global_transform_interpolated().origin
		var relative_focus := focus - player_position
		if seconds > 2.0:
			tracking.all_scoped = tracking.all_scoped and gameplay.scope_active()
			tracking.max_step = maxf(tracking.max_step, relative_focus.distance_to(tracking.last))
		tracking.last = relative_focus
		var cursor := root.get_mouse_position()
		temporal.append([seconds, focus.x, focus.y, focus.z, world.camera.size, cursor.x, cursor.y, player_position.x, player_position.y, player_position.z, gameplay.scope_active(), Input.is_action_pressed("aim"), world.player.input_locked, world.session.modal, gameplay.state.place_id])
	if functional_only:
		var observation_started := Time.get_ticks_msec()
		while Time.get_ticks_msec() - observation_started < 30000:
			await process_frame
			record.call(float(Time.get_ticks_msec() - observation_started) / 1000.0)
	else:
		await sample_phase("scope_stationary_cursor", record)
	physics_frame.disconnect(hold_aim)
	check(tracking.all_scoped, "Held aim stays scoped throughout stability observation")
	check(tracking.max_step < 0.02, "Stationary scoped cursor settles without persistent camera drift")
	check(world.camera.focus.distance_to(world.player.position) < 8.0, "Scoped framing keeps player nearby")
	await screenshot("scope-settled")
	button(MOUSE_BUTTON_RIGHT, false)
	var orbit_cursor := root.get_mouse_position()
	button(MOUSE_BUTTON_MIDDLE, true)
	await frames(2)
	check(world.camera.mouse_orbit_active(), "Middle button enters orbit through production input")
	var start_heading: float = world.camera.heading
	var orbit := func(_seconds: float) -> void:
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(4.0 if functional_only else 0.8, 0)
		motion.screen_relative = motion.relative
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		Input.parse_input_event(motion)
	if functional_only:
		for frame in 120:
			await process_frame
			orbit.call(float(frame) / 60.0)
	else:
		await sample_phase("mouse_orbit", orbit)
	check(absf(world.camera.heading - start_heading) > 1.0, "Continuous mouse drag rotates production camera")
	button(MOUSE_BUTTON_MIDDLE, false)
	await frames(2)
	check(not world.camera.mouse_orbit_active(), "Release ends production orbit")
	check(root.get_mouse_position().distance_to(orbit_cursor) < 2.0, "Orbit restores the same aim position with viewport scaling")
	check(Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN, "Orbit restores confined manual aiming")
	button(MOUSE_BUTTON_MIDDLE, true)
	await frames(2)
	world.pause_panel.pause_game()
	for frame in 3: await process_frame
	check(not world.camera.mouse_orbit_active() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Pause interrupts orbit and frees menu pointer")
	button(MOUSE_BUTTON_MIDDLE, false)
	world.pause_panel.resume_game()
	await frames(3)
	button(MOUSE_BUTTON_RIGHT, true)
	await frames(3)
	check(gameplay.scope_active(), "Manual scope recovers after pause")
	button(MOUSE_BUTTON_RIGHT, false)
	var summary := {"failures":failures, "functional_only":functional_only, "scope":{} if functional_only else summarize("scope_stationary_cursor"), "orbit":{} if functional_only else summarize("mouse_orbit"), "max_scope_step":tracking.max_step,
		"gpu":RenderingServer.get_video_adapter_name(), "engine":Engine.get_version_info(), "window":DisplayServer.window_get_size(), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps}
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(summary, "  "))
	FileAccess.open(output.path_join("samples.json"), FileAccess.WRITE).store_string(JSON.stringify(samples))
	FileAccess.open(output.path_join("camera-temporal.json"), FileAccess.WRITE).store_string(JSON.stringify(temporal))
	print("MOUSE_CAMERA_INTEGRATION ", JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
