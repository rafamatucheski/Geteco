extends SceneTree
var world
func _initialize() -> void: run.call_deferred()
func sample() -> Dictionary:
	var frames: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec()-start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last=now
	frames.sort()
	return {"frames":frames.size(),"fps":frames.size()*1000000.0/(last-start),"p50":frames[int(frames.size()*.5)],"p95":frames[int(frames.size()*.95)],"p99":frames[int(frames.size()*.99)],"max":frames.back(),"over33":frames.filter(func(v): return v>33.3).size(),"over66":frames.filter(func(v): return v>66.7).size(),"samples_ms":frames}
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	OS.low_processor_usage_mode=false
	seed(21102026)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: push_error("Main startup timeout"); quit(3); return
	var car = world.driving.car
	car.external_input=true
	car.brake_input=true
	world.camera.locked=true
	world.camera.target=car
	world.camera.offset=Vector3(0,12,-12)
	world.camera.target_size=12.0
	world.production.set_population(24)
	world.session.weather.set_process(false)
	await create_timer(30).timeout
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"vsync":DisplayServer.window_get_vsync_mode(),"cap":Engine.max_fps,"size":str(root.size)}
	print("BLOOD baseline")
	report.before=await sample()
	car.restore_blood_stains(15)
	await create_timer(5).timeout
	print("BLOOD stained")
	report.after=await sample()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/vehicle-blood"))
	FileAccess.open("res://artifacts/vehicle-blood/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/vehicle-blood/stained.png")
	print("BLOOD measured ",report.before.p95," -> ",report.after.p95)
	world.free()
	quit()
