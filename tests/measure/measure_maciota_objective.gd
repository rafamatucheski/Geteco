extends "res://tests/measure/measure.gd"
## Real Main, bounded 30-second rendered sample; isolated APPDATA and --no-save required.
var output := "res://artifacts/car-maciota-20261022"
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	if not await world.session.enter_place("maciota",false): quit(3); return
	world.player.controlled_automatically = true
	world.player.speed = 1.5
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.driving.set_process_unhandled_input(false)
	route = PackedVector3Array()
	for point in [Vector3(0,0,2.8),Vector3(1.2,0,1.5),Vector3(3.4,0,1.5),Vector3(3.4,0,-.55),Vector3(3.4,0,1.5),Vector3(1.2,0,1.5)]:
		route.append(world.maciota_place.room.to_global(point))
	print("MACIOTA_ROUTE ",JSON.stringify({"origin":str(world.maciota_place.room.global_position),"player":str(world.player.global_position),"place":world.session.state.place_id,"route":str(route)}))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+"-garage.png"))
	started = Time.get_ticks_usec()
	previous = started

func finish() -> void:
	var report := {"label":label,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"frame_intervals_ms":samples,"distance":world.player.travelled}
	var file := FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("MACIOTA_BENCHMARK ",JSON.stringify(report.summary))
	world.free()
	await process_frame
	quit()
