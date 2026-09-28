extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.player.teleport(Vector3(-340,.1,-50))
	world.production.region.set_focus(world.player.position)
	world.camera.heading = 0
	world.camera.target_size = 105
	world.camera.locked = true
	world.camera.initialized = false
	for i in 180: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/port-logistics-20260928/after/warehouse-review.png")
	world.player.teleport(Vector3(-305,.1,-66))
	world.production.region.set_focus(world.player.position)
	for i in 90: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/port-logistics-20260928/after/interior-review.png")
	print("PORT_LOGISTICS_CAPTURE saved")
	quit()
