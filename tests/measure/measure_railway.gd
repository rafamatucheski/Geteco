extends SceneTree
## Production scene, isolated checkpoint, identical camera and 30s samples.
## --railway-baseline omits only the new railway; no existing feature is disabled.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var output := ""
var label := "after"
var station := "harbor_central"
var recording := false
var previous := 0
var samples: Array[float] = []
var report := {}
var captures := 0
var visual_only := false
var temporal_active := false
var temporal_frames := 0
var temporal_log: FileAccess
var points := {
	"harbor_central":Vector3(156,.12,77),
	"harbor_north":Vector3(375,.12,-169),
	"mountain_pines":Vector3(723,.12,-384),
	"desert_copper":Vector3(-83,.12,-915),
}

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("RAILWAY benchmark timeout"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and previous>0: samples.append(float(now-previous)/1000.0)
	previous=now
	return false

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))
	captures+=1

func record_temporal() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("frames")))
	temporal_log=FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	temporal_log.store_line("frame,timestamp_usec,position,camera")
	while temporal_active and temporal_frames<9000:
		await RenderingServer.frame_post_draw
		if not temporal_active: break
		var frame := root.get_texture().get_image()
		frame.save_jpg(output.path_join("frames/%05d.jpg"%temporal_frames),.85)
		temporal_log.store_line('%d,%d,"%s",%d'%[temporal_frames,Time.get_ticks_usec(),world.player.global_position,world.session.railway.camera_mode])
		temporal_frames+=1
	temporal_log.close()

func sample(id: String) -> void:
	var start_position: Vector3 = world.player.global_position
	var started_riding: bool = world.session.railway != null and world.session.railway.is_riding()
	samples.clear(); previous=Time.get_ticks_usec(); recording=true
	await create_timer(30).timeout
	recording=false
	var ordered := samples.duplicate(); ordered.sort()
	var total := 0.0; var over33 := 0; var over66 := 0
	for value in samples:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	report[id]={"frames":samples.size(),"seconds":total/1000,"fps":samples.size()*1000/total,"p50":ordered[int(ordered.size()*.5)],"p95":ordered[int(ordered.size()*.95)],"p99":ordered[int(ordered.size()*.99)],"max":ordered.back(),"over33":over33,"over66":over66,"raw_ms":samples.duplicate(),"people":world.people.size(),"vehicles":world.production.vehicles.size()}
	report[id].start_position=str(start_position)
	report[id].end_position=str(world.player.global_position)
	report[id].started_riding=started_riding
	report[id].ended_riding=world.session.railway != null and world.session.railway.is_riding()
	if world.session.railway_world != null: report[id].railway=world.session.railway_world.debug_snapshot()
	var compact: Dictionary=report[id].duplicate(); compact.erase("raw_ms")
	print("RAILWAY_SAMPLE ",id," ",JSON.stringify(compact))

func prepare_station(id: String) -> bool:
	var destination: Dictionary=preload("res://world/railway/RailwayNetwork.gd").get_station(id)
	var point: Vector3=destination.entry
	var token: int=world.session._begin_transition("railway_measurement")
	if token<0: return false
	world.player.set_physics_process(false)
	var region=world.production._mount_region(str(destination.region),point)
	region.set_focus(point)
	region.prepare_collision_at(point)
	if world.session.railway_world!=null:
		world.session.railway_world.set_focus(point)
		world.session.railway_world.ensure_station(id)
	for i in 300:
		await physics_frame
		if region.pending.is_empty() and region.build_jobs.is_empty(): break
	await physics_frame
	var clear: bool=world.session.position_clear(point)
	if clear:
		world.player.teleport(point)
		world.production._commit_logical_region(str(destination.region))
		world.camera.initialized=false
	world.player.set_physics_process(true)
	world.session._finish_transition(token)
	if "--railway-roof-review" in OS.get_cmdline_user_args(): frame_roof(id)
	return clear

func frame_roof(id: String) -> void:
	var station_data: Dictionary=preload("res://world/railway/RailwayNetwork.gd").get_station(id)
	var center: Vector3=station_data.position+Vector3(float(station_data.side)*5.0,1.0,0)
	world.camera.set_process(false)
	world.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size=43.0
	world.camera.global_position=center+Vector3(29,28,34)
	world.camera.look_at(center,Vector3.UP)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	visual_only="--railway-visual" in args
	if DisplayServer.get_name()=="headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	for arg in args:
		if arg.begins_with("--station="): station=arg.trim_prefix("--station=")
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
	if not points.has(station): quit(2); return
	output=FIXTURE.output_dir("railway-"+label+"-"+station)
	var point: Vector3=preload("res://world/railway/RailwayNetwork.gd").get_station(station).entry
	var data := FIXTURE.full_snapshot(point,true)
	data.campaign.aftermath={"call_complete":true}
	var region := "mountain" if station=="mountain_pines" else "desert" if station=="desert_copper" else "harbor"
	data.region_id=region; data.world.pedestrian.region=region
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	if path.is_empty(): quit(2); return
	if "--railway-roof-review" in args: seed(61007)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 7200:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	if world.player.global_position.distance_to(point)>4:
		push_error("Benchmark spawn fell back from station: "+str(world.player.global_position)+" expected "+str(point)); world.free(); quit(1); return
	world.dispatch.router.nearest_edge(point)
	if world.dispatch.router._native==null: push_error("C# path unavailable"); quit(1); return
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1280,720)
	world.gameplay.god_mode=true
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	# Keep regional weather/atmosphere updating during travel. Freezing this Node
	# manufactured a sky jump at the logical region seam in the first capture.
	world.session.weather.weather_timer=10000
	world.session.weather.time_of_day=.88 if "--railway-night" in args else .45
	world.session.weather._update()
	world.camera.set_process_unhandled_input(false)
	if "--railway-roof-review" in args: frame_roof(station)
	if not visual_only:
		Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	report.environment={"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"scene":"Main.tscn","native":true,"station":station,"baseline":"--railway-baseline" in args,"position":str(world.player.position),"args":args}
	report.sources={}
	for file in ["res://runtime/FullSession.gd","res://runtime/ProductionWorld.gd","res://gameplay/Gameplay.gd","res://world/editing/world_edits.json","res://world/railway/RailwayNetwork.gd","res://world/railway/RailwayWorld.gd","res://world/railway/TrainModel.gd","res://runtime/railway/RailwayTransit.gd","res://ui/railway/RailwayUI.gd","res://.godot/mono/temp/bin/Debug/Harbor.dll"]:
		report.sources[file]=FileAccess.get_sha256(file) if FileAccess.file_exists(file) else "MISSING"
	report.budget={"target_ms":16.667,"regression_confirmation_percent":5.0,"warmup_seconds":6,"sample_seconds":30}
	await create_timer(6).timeout
	await capture("station")
	if "--railway-roof-review" in args:
		world.camera.size=26.0
		await capture("roof-detail")
		frame_roof(station)
	if not visual_only: await sample("station")
	if "--railway-all-stations" in args:
		for id in ["harbor_north","mountain_pines","desert_copper"]:
			if not await prepare_station(id): push_error("No clear measurement entrance: "+id); world.free(); quit(1); return
			await create_timer(12).timeout
			await capture(id)
			if not visual_only: await sample(id)
	if "--railway-trip" in args:
		var railway=world.session.get("railway")
		if railway==null: push_error("No railway installed"); quit(1); return
		var network=load("res://world/railway/RailwayNetwork.gd")
		var origin: Dictionary=network.get_station(station)
		world.player.teleport(origin.arrival)
		await physics_frame
		if not railway.perform(station): push_error("Station not accessible"); quit(1); return
		await capture("destinations")
		var target := "mountain_pines" if station.begins_with("harbor") else "harbor_central"
		if not railway.travel_to(target,false): push_error("Board rejected"); quit(1); return
		if "--railway-temporal" in args:
			temporal_active=true
			record_temporal()
			var trip_started := Time.get_ticks_msec()
			var capture_limit := 8000 if "--railway-boarding-only" in args else 140000
			while railway.busy() and Time.get_ticks_msec()-trip_started<capture_limit:
				await process_frame
				var wanted_mode := 1 if Time.get_ticks_msec()-trip_started<14000 else 0
				if railway.camera_mode!=wanted_mode: railway.set_camera_mode(wanted_mode)
			temporal_active=false
			await process_frame
			if "--railway-boarding-only" in args:
				railway.skip_trip()
				for i in 1800:
					await physics_frame
					if not railway.busy(): break
			await capture("arrival")
			report.temporal={"frames":temporal_frames,"duration_ms":Time.get_ticks_msec()-trip_started,"arrived":not railway.busy(),"capture":"every rendered frame, full resolution; capture cost excluded from performance claims"}
			FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			print("RAILWAY_TEMPORAL ",output," frames=",temporal_frames)
			var arrived: bool=not railway.busy()
			world.free(); quit(0 if arrived else 1); return
		await create_timer(3).timeout
		await capture("inside")
		if visual_only:
			for i in 10:
				await create_timer(2).timeout
				await capture("inside-%02d"%i)
		else: await sample("inside")
		railway.set_camera_mode("exterior")
		await capture("exterior")
		if visual_only:
			for i in 10:
				await create_timer(2).timeout
				await capture("exterior-%02d"%i)
		else: await sample("exterior")
		if railway.is_riding(): railway.skip_trip()
		for i in 1800:
			await physics_frame
			if not railway.busy(): break
		await capture("arrival")
	FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RAILWAY_EVIDENCE ",output," captures=",captures)
	world.free(); quit(0)
