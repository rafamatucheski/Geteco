extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1200:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	world.camera.target_size = 22
	world.session.weather.time_of_day = 0.40
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	for entry in [
		["urban",Vector3(100,0.06,152),PI],
		["industrial",Vector3(230,0.06,203),0.0],
		["stone",Vector3(529,0.06,105),-PI*0.5],
		["highway",Vector3(390,0.06,-270),-PI*0.5],
		["urban-depth",Vector3(100,0.06,153.5),0.0],
		["bridge",Vector3(462,0.06,-280),PI]]:
		if "--detail-only" in OS.get_cmdline_user_args() and entry[0] not in ["highway","urban-depth"]: continue
		world.player.teleport(entry[1])
		world.production.region.set_focus(entry[1])
		world.camera.heading = entry[2]
		world.camera.initialized = false
		await create_timer(3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/coast-protection-"+entry[0]+".png")
		print("COAST_CAPTURE ",entry[0]," player=",world.player.position)
	world.queue_free()
	await process_frame
	quit()
