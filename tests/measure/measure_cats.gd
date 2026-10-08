extends "res://tests/measure/measure.gd"
## Same production scene/cameras for before/after; isolated save, real frame intervals.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PLACES = preload("res://world/places/PlaceCatalog.gd")
var folder := ""
var intervals := {}
var phase := ""
var tracing := false
var tick := 0
var residents_measured := {}

func fingerprint() -> Dictionary:
	var result := FIXTURE.source_fingerprint()
	for directory in ["res://runtime/cats","res://activities/arcade","res://gameplay/civilian_social"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".gd"): result[directory.path_join(file)] = FileAccess.get_sha256(directory.path_join(file))
	for path in ["res://activities/Residence.gd","res://runtime/ResidenceServices.gd","res://tests/measure/measure_cats.gd"]: result[path] = FileAccess.get_sha256(path)
	return result

func _process(_delta: float) -> bool:
	if tracing:
		var now := Time.get_ticks_usec()
		intervals[phase].append(float(now-tick)/1000.0)
		tick = now
	return false

func sample(id: String, seconds: float) -> void:
	phase = id
	intervals[id] = []
	tick = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(260).timeout.connect(func(): quit(3))
	var baseline := "--cats-baseline" in OS.get_cmdline_user_args()
	Engine.set_meta("cats_baseline",baseline)
	seed(71026)
	folder = FIXTURE.output_dir("cats-baseline" if baseline else "cats-final")
	var source := fingerprint()
	var fixture := FIXTURE.full_snapshot(Vector3(20,.08,15),false)
	var path := FIXTURE.write_fixture(folder,"save.json",fixture)
	if path.is_empty(): quit(4); return
	world = load("res://Main.tscn").instantiate()
	if world.get_script() == null:
		world.free()
		push_error("CATS_MEASURE Main did not compile")
		quit(2)
		return
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# required"); quit(5); return
	var session = world.session
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 9999
	session.weather._update()
	var home = session.activities.residence
	for id in ["westgate_garden","quayside_house","canal_north"]:
		home.data.active_home = id
		home.data.purchases = 1
		if home.has_method("adopt_cat"):
			for index in 10: home.adopt_cat("cat_%02d"%(index+1))
			home.data.cats.furniture = {"bed":10,"ball":3,"scratcher":2}
		var point: Vector3 = PLACES.get_definition(id).entry_position+Vector3(1.8,.08,1.3)
		world.production.region.set_focus(point)
		world.production.region.prepare_collision_at(point)
		world.player.teleport(point)
		world.camera.initialized = false
		await sample(id+"_arrival",5)
		if id == "westgate_garden":
			await sample("yard",30)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("yard.png"))
		if not await session.enter_place(id,false): push_error("Home entry failed "+id); quit(6); return
		await sample(id+"_warmup",5)
		await sample(id,30)
		if session.cats != null: residents_measured[id] = {"cats":session.cats.residents.size(),"props":session.cats.furniture.size(),"unreachable":session.room.get_meta("cat_layout_unreachable_stations",[])}
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(id+".png"))
		if not await session.leave_place(): push_error("Home exit failed "+id); quit(7); return
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"baseline":baseline,"summary":summary,"samples_ms":intervals,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null,"source_before":source,"source_after":fingerprint(),"residents":residents_measured}
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CATS_MEASURE ",folder," ",JSON.stringify(summary))
	quit()
