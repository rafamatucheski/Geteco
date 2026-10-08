extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var intervals := {}
var phase := ""
var tracing := false
var last_tick := 0
var folder := ""
var source_before := {}

func fingerprints() -> Dictionary:
	var result: Dictionary = FIXTURE.source_fingerprint()
	for directory in ["res://world/places/amusement_park","res://runtime/amusement_park","res://activities/amusement_park"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".gd"): result[directory.path_join(file)] = FileAccess.get_sha256(directory.path_join(file))
	for path in ["res://gameplay/urban_v1/FreightOutskirts.gd","res://world/regions/NativeRegion.gd","res://world/city_look/CityChunkDressing.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _process(_delta: float) -> bool:
	if tracing:
		var now := Time.get_ticks_usec()
		if not intervals.has(phase): intervals[phase] = []
		intervals[phase].append(float(now-last_tick)/1000.0)
		last_tick = now
	return false

func sample(id: String, seconds: float) -> void:
	phase = id
	last_tick = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false
	print("PARK_MEASURE_PHASE ",id," frames=",intervals.get(id,[]).size())

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(340).timeout.connect(func(): quit(3))
	seed(100726)
	var baseline := "--park-baseline" in OS.get_cmdline_user_args()
	var preview := "--preview" in OS.get_cmdline_user_args()
	var night := "--park-night" in OS.get_cmdline_user_args()
	Engine.set_meta("amusement_park_baseline",baseline)
	label = "baseline" if baseline else "final"
	if night: label += "-night"
	folder = FIXTURE.output_dir("amusement-park-"+label)
	source_before = fingerprints()
	var entry := Vector3(-130,.1,78)
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	snapshot.world.time = .90 if night else .45
	snapshot.world.weather = 0
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# required"); quit(5); return
	world.session.weather.time_of_day = .90 if night else .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	world.player.teleport(entry)
	world.camera.initialized = false
	await sample("first_visit",8)
	await sample("warmup",5)
	await sample("entrance",1 if preview else 30)
	await capture("entrance")
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.far = 300
	overview.fov = 65
	overview.global_position = Vector3(-118,48,142)
	overview.look_at(Vector3(-176,3,78))
	overview.make_current()
	await sample("overview_warmup",3)
	await sample("overview",1 if preview else 30)
	await capture("overview")
	world.camera.make_current()
	overview.queue_free()
	if not baseline and not night and world.session.get("amusement_park") != null:
		var park = world.session.amusement_park
		world.player.teleport(park.site.boarding_position()+Vector3.UP*.04)
		await create_timer(.3).timeout
		if not park.start_ride(): push_error("Could not start coaster"); quit(6); return
		await sample("ride",30)
		await capture("ride")
		# Inspect the downward view separately; capture/readback never enters the
		# performance sample above. The climbing frame alone cannot reveal gaps.
		park.leave()
		if not park.start_ride(): push_error("Could not repeat coaster for summit view"); quit(8); return
		var summit_deadline := Time.get_ticks_msec()+60000
		while park.active and world.player.global_position.y < 13.0 and Time.get_ticks_msec()<summit_deadline: await physics_frame
		if park.active:
			park.pitch = -.4
			await process_frame
			await capture("summit")
		park.leave()
		var house := "harbor_haunted_house"
		if not await world.session.enter_place(house,false): push_error("Could not enter haunted house"); quit(7); return
		await sample("house_warmup",3)
		await sample("house",30)
		await capture("house")
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"label":label,"baseline":baseline,"summary":summary,"samples_ms":intervals,"position":str(world.player.global_position),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null}
	report.source_before = source_before
	report.night = night
	report.source_after = fingerprints()
	report.source_stable = report.source_before == report.source_after
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AMUSEMENT_PARK_MEASURE ",folder," ",JSON.stringify(summary))
	quit()

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))
