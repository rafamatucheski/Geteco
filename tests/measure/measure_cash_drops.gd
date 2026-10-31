extends "res://tests/measure/measure.gd"
## Cidade de produção renderizada, mesmas mortes semeadas na multidão antes/depois; sem saves pessoais.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	seed(6102026)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.teleport(Vector3(132,.15,72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 30
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	if world.gameplay.get("_cash_rng") != null: world.gameplay._cash_rng.seed = 6102026
	await create_timer(8).timeout
	var frames: Array[float] = []
	var previous_time := Time.get_ticks_usec()
	var victims := 0
	for actor in world.people:
		if not is_instance_valid(actor) or actor.dead: continue
		actor.teleport(world.player.position + Vector3(3 + victims % 6,0,-5 + int(victims / 6) * 2))
		actor.receive_damage(1000)
		victims += 1
		if victims == 10: break
	var drops: int = world.gameplay._loot.size()
	var folder := "res://evidence/cash-drops/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var elapsed := 0.0
	var captured := false
	while elapsed < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - previous_time) / 1000.0
		previous_time = now
		frames.append(ms)
		elapsed += ms
		if not captured and elapsed > 1500:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + "/scene.png")
			captured = true
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"victims":victims,"drops":drops,"summary":stats(frames),"frames_ms":frames,"caveat":"Other user-owned Godot processes were running; comparison is diagnostic, not performance approval."}
	FileAccess.open(folder + "/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("CASH_BENCH ", variant, " ", JSON.stringify(report.summary), " victims=",victims," drops=",drops)
	if world.gameplay.has_method("drop_cash"):
		var collected := 0
		var initial_balance: int = world.session.state.economy.balance
		for pickup in world.gameplay._loot.duplicate():
			if not is_instance_valid(pickup) or pickup.kind != "cash": continue
			collected += int(pickup.cash_amount)
			world.player.teleport(pickup.global_position)
			world.gameplay._update_loot(0)
		var paid: int = world.session.state.economy.balance - initial_balance
		if collected <= 0 or paid != collected:
			push_error("Real city cash collection failed: expected %d, got %d" % [collected,paid])
			world.free(); quit(4); return
		print("CASH_CITY_COLLECTION expected=",collected," paid=",paid)
		world.gameplay.clear_loot()
		await create_timer(.4).timeout
		print("CASH_CITY_CLEANUP active=",world.gameplay._loot.size())
	world.free()
	quit()
