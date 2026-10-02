extends SceneTree
## Captura de revisão visual no Main real. Uso: -- --no-save --point=x,z --output=caminho.png

func _initialize() -> void:
	run.call_deferred()

func _arg(key: String, fallback := "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--" + key + "="): return value.trim_prefix("--" + key + "=")
	return fallback

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var output := _arg("output")
	var coords := _arg("point").split(",")
	if output.is_empty() or coords.size() != 2:
		quit(2)
		return
	root.size = Vector2i(1280,720)
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 90000:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.cold.set_process(false)
	world.diagnostic_label.hide()
	world.session.weather.time_of_day = 0.5
	world.session.weather.weather_state = 0
	world.session.weather._update()
	var target := Vector3(float(coords[0]),0.12,float(coords[1]))
	if "--car" in OS.get_cmdline_user_args():
		target.y = preload("res://world/urban_detail/CanalTunnel3D.gd").floor_y(target.x) + 0.12
	world.production._update_physical_residency(target)
	world.production._update_logical_region(target)
	if "--car" in OS.get_cmdline_user_args():
		var car: CharacterBody3D = world.driving.car
		car.place(target,-PI * 0.5)
		for frame in 3: await physics_frame
		for side in [-1,1]:
			world.player.teleport(car.to_global(Vector3(side * (car.half_width + 0.65),0.04,0.15)))
			await physics_frame
			if world.driving.interact(): break
		car.set_external_driver(true)
		car.place(target,-PI * 0.5)
	else:
		world.player.teleport(target)
	world.camera.heading = float(_arg("heading","0"))
	world.camera.target_size = float(_arg("size","50"))
	world.camera.focus = target
	world.camera.initialized = false
	for frame in 180:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output)
	print("VIDEO_VISUAL_CAPTURE ",output," error=",result)
	world.queue_free()
	await process_frame
	quit(0 if result == OK else 1)
