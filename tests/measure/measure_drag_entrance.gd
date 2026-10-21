extends SceneTree
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PROP := preload("res://activities/desert_drag/DesertDragBoardProp.gd")
var world
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): quit(3))
	run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	var phase := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase=arg.trim_prefix("--phase=")
	var output := "res://evidence/drag-entrance-20261021/"+phase
	DirAccess.make_dir_recursive_absolute(output)
	var at := PROP.position()+Vector3(0,.1,3)
	var data := FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode=true
	world.session.desert.drag.open_meet.enabled=false
	var weather=world.session.weather
	weather.set_process(false)
	weather.time_of_day=.55
	weather.weather_state=0
	weather._update()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position=PROP.position()+Vector3(10,7,13)
	camera.look_at(PROP.position()+Vector3(0,1,0))
	camera.fov=50
	camera.make_current()
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	await create_timer(8).timeout
	var started := Time.get_ticks_usec()
	var stamp := started
	var samples: Array[float]=[]
	while Time.get_ticks_usec()-started<32000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-stamp)/1000.0)
		stamp=now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for sample in samples:
		total+=sample
		if sample>33.3: over33+=1
		if sample>66.7: over66+=1
	var report := {"phase":phase,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"frames":samples.size(),"seconds":total/1000,"fps":samples.size()*1000/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples}
	FileAccess.open(output+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	report.erase("raw_ms")
	print("ENTRANCE_METRICS ",JSON.stringify(report))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/entrance.png")
	camera.global_position=PROP.position()+Vector3(1,2.1,7)
	camera.look_at(PROP.position()+Vector3(0,1.7,0))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/pedestrian.png")
	quit(0)
