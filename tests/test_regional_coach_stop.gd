extends SceneTree
## Real Cobre scene: controlled rendering comparison plus physical access.
const F := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STOPS := preload("res://runtime/regional/RegionalCoachRoute.gd")
var world
var checks := 0
var failures := 0
var folder := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("COBRE_STOP ","PASS " if ok else "FAIL ",label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	create_timer(180).timeout.connect(func(): push_error("COBRE_STOP timeout"); quit(3))
	seed(7102026)
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	folder=F.output_dir("cobre-stop-before" if baseline else "cobre-stop-final")
	var point: Vector3=STOPS.station("desert").arrival
	var snapshot := F.full_snapshot(point+Vector3.UP*.12,true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[point.x,.12,point.z]}
	snapshot.campaign.aftermath={"call_complete":true}
	var path := F.write_fixture(folder,"save.json",snapshot)
	if path.is_empty(): quit(2); return
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await process_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day=.4
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.camera.heading=0
	world.camera.target_size=18
	world.camera.initialized=false
	await create_timer(1).timeout
	var stop: Node = world.find_child("CobreCoachStop",true,false)
	check(is_instance_valid(stop),"authored stop loaded with desert chunk")
	if not is_instance_valid(stop): quit(1); return
	if baseline:
		stop.queue_free()
		await physics_frame
		await physics_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	var frames: Array[float]=[]
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began<38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-began>=8000000: frames.append(float(now-previous)/1000.0)
		previous=now
	var sorted := frames.duplicate(); sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in frames:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	var report := {"fps":frames.size()*1000.0/total,"seconds":total/1000.0,"frames_ms":frames,"p50":sorted[int((sorted.size()-1)*.5)],"p95":sorted[int((sorted.size()-1)*.95)],"p99":sorted[int((sorted.size()-1)*.99)],"max":sorted[-1],"over33":over33,"over66":over66,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"baseline_omits_only_stop":baseline,"map_hash":preload("res://world/editing/WorldEditData.gd").disk_hash()}
	FileAccess.open(folder+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	await photo("station")
	Engine.max_fps=144
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if not baseline:
		check(world.session.position_clear(point),"arrival capsule clear above pavement")
		check(world.session.nearest().get("id","")=="regional_coach","visible stop exposes bus menu")
		world.player.teleport(point+Vector3.UP*.10)
		world.player.automatic_direction=Vector3.FORWARD
		for frame in 150: await physics_frame
		world.player.automatic_direction=Vector3.ZERO
		check(world.player.position.z<-887.2 and world.player.position.z>-889.4,"walk enters shelter and stops against solid bench")
		check(absf(world.player.position.y)<.15 and world.player.is_on_floor(),"walking retains ground support")
		await photo("bench-collision")
		world.player.teleport(point+Vector3.UP*.10)
		var service=world.session.regional_coach
		check(service.travel_to("harbor",true),"boarding works from new stop")
		while service.riding: await process_frame
		check(world.session.state.region_id=="harbor","outward transfer completes")
		await create_timer(.6).timeout
		check(service.travel_to("desert",true),"return to new stop admitted")
		while service.riding: await process_frame
		await create_timer(1).timeout
		check(world.session.state.region_id=="desert" and world.session.position_clear(world.player.position),"return has clear supported landing")
		var rebuilt: Array = world.find_children("CobreCoachStop","",true,false)
		check(rebuilt.size()==1,"streamed revisit restores exactly one stop")
		await photo("arrival")
	print("COBRE_STOP_RESULT checks=",checks," failures=",failures," folder=",folder," fps=",report.fps," p95=",report.p95)
	world.free(); await process_frame
	quit(0 if failures==0 else 1)
func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
