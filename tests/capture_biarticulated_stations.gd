extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	var world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for frame in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	var ops=world.production.urban_transit.urban_service
	for frame in 180:
		await physics_frame
		if ops.prepared: break
	if ops.stops.size()!=6: quit(3); return
	ops.set_physics_process(false)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.time_of_day=.35
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var bus=ops.fleet[0]
	world.camera.target=bus; world.camera.heading=0; world.camera.target_size=38
	world.camera.set_process_unhandled_input(false)
	for index in ops.stops.size():
		if "--station=1" in OS.get_cmdline_user_args() and ops.stops[index].id!=1: continue
		for other in ops.fleet: other.set_active(false)
		bus.service_stop=index
		bus.route_distance=ops.stops[index].offset
		bus._apply_poses(ops.path_poses.at(bus.route_distance),false)
		world.player.teleport(ops.stops[index].inside+Vector3.UP*.04)
		world.production._update_physical_residency(world.player.position)
		world.camera.initialized=false
		ops.refresh_presence()
		bus.set_active(true); bus.set_doors(1); ops.gate(index,true)
		for frame in 90: await process_frame
		await RenderingServer.frame_post_draw
		var filename: String="res://evidence/biarticulated/station_%d.png" % ops.stops[index].id
		root.get_texture().get_image().save_png(filename)
		print("STATION_CAPTURE ",filename)
	quit()
