extends "res://tests/measure/measure.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=").validate_filename()
	seed(28092026)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.player.teleport(Vector3(238.6,.2,189))
	world.production.region.set_focus(world.player.position)
	world.session.weather.set_process(false)
	world.camera.set_process(false)
	world.camera.size=18
	world.camera.global_position=Vector3(263.6,28.2,214)
	world.camera.look_at(Vector3(238.6,.2,189))
	var folder:="res://evidence/fishing-boats-20260928/"+variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for site in [{"id":"near-day","time":.4,"weather":0},{"id":"near-night-rain","time":.93,"weather":1}]:
		world.session.weather.time_of_day=site.time
		world.session.weather.weather_state=site.weather
		world.session.weather._update()
		var frames: Array[float]=[]
		var warm: Array[float]=[]
		var start:=Time.get_ticks_usec()
		var last:=start
		while Time.get_ticks_usec()-start<38000000:
			await process_frame
			var now:=Time.get_ticks_usec()
			if now-start<8000000: warm.append((now-last)/1000.0)
			else: frames.append((now-last)/1000.0)
			last=now
		var report:={"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames}
		FileAccess.open(folder+"/"+site.id+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+site.id+".png")
		print("FISHING_MEASURE ",site.id," ",JSON.stringify(report.summary))
	quit()
