extends "res://tests/measure/measure.gd"
const DATA = preload("res://world/editing/WorldEditData.gd")

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var folder := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder=arg.trim_prefix("--out-dir=")
	if folder.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	seed(29092026)
	root.size=Vector2i(1280,720)
	var map_hash := DATA.disk_hash()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<60000:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3); return
	# Session video preferences can resize the window during initialization.
	# Apply the measurement resolution after those preferences have loaded.
	root.size=Vector2i(1280,720)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	# A stationary observer must not die of cold or be hit while measuring.
	# Keep traffic, pedestrians, weather and their collisions fully enabled.
	world.session.cold.set_process(false)
	world.player.collision_layer=0
	world.camera.set_process_unhandled_input(false)
	world.camera.heading=0
	world.camera.target_size=65
	world.session.weather.time_of_day=.35
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	for spec in [["mountain_access",Vector3(707,.15,-330)],["mountain_junction",Vector3(687.45,.15,-412.03)],["city",Vector3(110,.15,95)]]:
		world.player.teleport(spec[1])
		world.production._update_physical_residency(spec[1])
		world.camera.initialized=false
		var warm: Array[float]=[]
		var frames: Array[float]=[]
		var population=[]
		var start := Time.get_ticks_usec()
		var last := start
		while Time.get_ticks_usec()-start<38000000:
			await process_frame
			var now := Time.get_ticks_usec()
			if now-start<8000000: warm.append((now-last)/1000.0)
			else: frames.append((now-last)/1000.0)
			if Engine.get_process_frames()%60==0: population.append([float(now-start)/1000000,world.production.vehicles.size(),world.people.size()])
			last=now
		var observer_stayed:bool=world.player.global_position.distance_to(spec[1])<2.0
		var report={"site":spec[0],"position":str(spec[1]),"actual_position":str(world.player.global_position),"observer_stayed":observer_stayed,"seed":29092026,"map_hash":map_hash,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames,"warmup_ms":warm,"population":population}
		FileAccess.open(folder+"/"+spec[0]+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+spec[0]+".png")
		print("ROAD_PERF ",spec[0]," ",stats(frames))
		if not observer_stayed:push_error("Observer left benchmark site");quit(4);return
	print("ROAD_PERF_DONE map_unchanged=",map_hash==DATA.disk_hash())
	world.queue_free()
	await process_frame
	quit()

# The base class has a per-frame prototype runner; this diagnostic owns its loop.
func _process(_delta: float) -> bool: return false
