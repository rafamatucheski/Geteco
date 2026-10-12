extends "res://tests/measure/measure_katana_session.gd"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output_dir = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true)
	root.add_child(world); current_scene = world
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	var point := Vector3(1650.0/16.0,0,2070.0/16.0)
	world.player.teleport(point+Vector3(0,.1,7))
	world.production.region.set_focus(point)
	await frames(100)
	var car = world.driving.car
	car.place(point+Vector3(0,.1,7),0)
	car.external_input = true; car.controlled = true; car.traffic = false
	car.throttle_input = 0; car.brake_input = true
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm < 8000000: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec(); var last := start
	car.brake_input = false; car.throttle_input = 1
	car.speed = 12; car.horizontal_velocity = Vector3(0,0,-12)
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec(); samples.append(float(now-last)/1000.0); last = now
		if now-start > 1500000: car.throttle_input = 0; car.brake_input = true
	var summary := summarize(samples)
	summary.merge({"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"viewport":str(root.size),"car_position":str(car.global_position)})
	FileAccess.open(output_dir.path_join("measure.json"),FileAccess.WRITE).store_string(JSON.stringify(summary,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join("after-impact.png"))
	summary.erase("samples_ms"); print("BREAKABLE_MEASURE ",summary)
	world.queue_free(); await process_frame; quit(0)
