extends SceneTree
## Real Main.tscn capture at the authored Maciota entrance. No save writes.

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if output.is_empty():
		quit(2)
		return
	seed(22092026)
	var world: Variant = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.weather != null:
			break
	if world.production == null or not world.production.ready_for_play or world.session == null or world.session.weather == null:
		push_error("Maciota city did not finish loading")
		quit(1)
		return
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	if "--undressed" in OS.get_cmdline_user_args():
		for child in world.maciota_place.facade.get_children():
			if child.name == "MaciotaExteriorDetails" or child.name == "MaciotaName" or str(child.name).begins_with("MaciotaWorkLamp"):
				child.hide()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--time="):
			world.session.weather.time_of_day = argument.trim_prefix("--time=").to_float()
			world.session.weather.weather_state = 0
			world.session.weather._update()
	var point: Vector3 = world.maciota_place.exterior_return + Vector3(0, .08, 2.5)
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.player.teleport(point)
	world.camera.heading = 0.0
	world.camera.target_size = 24.0
	world.camera.focus = point
	world.camera.initialized = true
	for frame in 90:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Maciota city capture save failed: %d" % error)
		quit(1)
		return
	print("MACIOTA_CITY_CAPTURE ", output)
	world.queue_free()
	await process_frame
	quit()
