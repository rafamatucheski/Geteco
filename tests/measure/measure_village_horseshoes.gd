extends "res://tests/measure/measure.gd"
## Compare idle versus repeated real UI rounds at the same court, 8 s warmup +
## 30 s samples. Screenshots are saved only after the measured interval.
const ART := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const SERVICE := preload("res://gameplay/urban_v1/TruckersVillageLeisure.gd")
const FOLDER := "res://evidence/village-leisure-20260929"

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280,720)
	seed(29092026)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for frame in 2400:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.teleport(ART.PLAY_POINT+Vector3.UP*.1)
	world.production.region.set_focus(ART.PLAY_POINT)
	world.camera.heading = 0
	world.camera.target_size = 23
	world.camera.initialized = false
	var leisure = world.session.urban_operations.village_leisure
	for mode in ["idle","active"]:
		var begin := Time.get_ticks_usec()
		var last := begin
		var warm: Array[float] = []
		var frames: Array[float] = []
		var rounds := 0
		while Time.get_ticks_usec()-begin < 38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-begin < 8000000: warm.append((now-last)/1000.0)
			else: frames.append((now-last)/1000.0)
			last = now
			if mode=="active":
				if not leisure.playing:
					if leisure.perform(SERVICE.PREFIX+"play"): rounds += 1
				elif leisure.ui.cooldown <= 0 and leisure.ui.strength >= .68 and leisure.ui.strength <= .73:
					leisure.ui.try_throw()
		var report := {"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"rounds":rounds,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"paused":paused,"world_processing":world.can_process(),"player_position":str(world.player.position)}
		FileAccess.open(FOLDER+"/court-"+mode+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
		print("VILLAGE_COURT_MEASURE ",mode," rounds=",rounds," ",JSON.stringify(report.summary))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(FOLDER+"/court-"+mode+".png")
		if leisure.playing: leisure.ui.cancel_game()
	world.queue_free()
	await process_frame
	quit()
