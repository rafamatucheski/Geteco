extends SceneTree
var world
var fleet: Array = []
var folder := "res://artifacts/vehicle-blood-fleet/performance-before"
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
	var raw := frames.duplicate()
	frames.sort()
	return {"frames":frames.size(),"fps":frames.size()*1000000.0/(last-start),"p50":frames[int(frames.size()*.5)],"p95":frames[int(frames.size()*.95)],"p99":frames[int(frames.size()*.99)],"max":frames.back(),"over33":frames.filter(func(v): return v>33.3).size(),"over66":frames.filter(func(v): return v>66.7).size(),"samples_ms":raw}
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	OS.low_processor_usage_mode=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): folder="res://artifacts/vehicle-blood-fleet/performance-"+arg.trim_prefix("--label=").validate_filename()
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
	var ids := ["police_cruiser","police_suv","police_transport","bike_urban","bike_police","bike_sport"]
	for i in ids.size():
		var extra = preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
		extra.archetype=ids[i]
		extra.vehicle_id="blood_perf_"+ids[i]
		extra.position=car.position+Vector3((i%3-1)*4,0,(i/3)*6-6)
		world.add_child(extra)
		extra.set_physics_process(false)
		fleet.append(extra)
	world.camera.target_size=24.0
	world.production.set_population(24)
	world.session.weather.set_process(false)
	await create_timer(30).timeout
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"vsync":DisplayServer.window_get_vsync_mode(),"cap":Engine.max_fps,"size":str(root.size)}
	print("BLOOD baseline")
	report.before=await sample()
	var began := Time.get_ticks_usec()
	for extra in fleet: extra.restore_blood_stains(15)
	car.restore_blood_stains(15)
	report.apply_ms=(Time.get_ticks_usec()-began)/1000.0
	await create_timer(5).timeout
	print("BLOOD stained")
	report.after=await sample()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder+"/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/stained.png")
	print("BLOOD measured ",report.before.p95," -> ",report.after.p95)
	world.free()
	quit()
