extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ENTRY := preload("res://runtime/FishingLocation.gd").ENTRY+Vector3.UP*.1
var folder := ""
var intervals := {}
var phase := ""
var tracing := false
var last_tick := 0
var fishing_driver: Node
var reeling := false

func fingerprint() -> Dictionary:
	var result := {}
	for path in ["res://runtime/FullSession.gd","res://runtime/ProductionWorld.gd","res://world/regions/NativeRegion.gd","res://project.godot","res://gameplay/Gameplay.gd","res://world/editing/world_edits.json"]:
		result[path] = FileAccess.get_sha256(path)
	for directory in ["res://activities/fishing","res://world/places/fishing"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".gd") or file.ends_with(".gdshader"): result[directory.path_join(file)] = FileAccess.get_sha256(directory.path_join(file))
	for path in ["res://runtime/FishingRuntime.gd","res://runtime/FishingLocation.gd","res://gameplay/urban_v1/FreightOutskirts.gd","res://activities/motocross/MotocrossGroundDetail.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _process(_delta: float) -> bool:
	if is_instance_valid(fishing_driver) and fishing_driver.active:
		match str(fishing_driver.phase):
			"ready": fishing_input(true)
			"charging":
				if fishing_driver._charge > .7: fishing_input(false)
			"bite": fishing_input(true)
			"reeling":
				if reeling and fishing_driver.fight.tension > .72: fishing_input(false)
				elif not reeling and fishing_driver.fight.tension < .3: fishing_input(true)
			"caught", "missed", "line_broke":
				if reeling: fishing_input(false)
	if tracing:
		var now := Time.get_ticks_usec()
		intervals[phase].append(float(now-last_tick)/1000.0)
		last_tick = now
	return false

func fishing_input(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = pressed
	reeling = pressed
	world.session._input(event)

func sample(next: String, seconds: float) -> void:
	phase = next
	intervals[phase] = []
	last_tick = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240).timeout.connect(func(): quit(3))
	seed(71026)
	var baseline := false
	Engine.set_meta("fishing_baseline",baseline)
	label = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	folder = FIXTURE.output_dir("fishing-life-"+label)
	var before := fingerprint()
	var snapshot := FIXTURE.full_snapshot(ENTRY,false)
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"isolated-save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# routing required"); quit(5); return
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	world.production.region.set_focus(ENTRY)
	world.production.region.prepare_collision_at(ENTRY)
	world.player.teleport(ENTRY)
	world.camera.initialized = false
	await sample("first_visit",8)
	await sample("entrance",5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("entrance.png"))
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.global_position = Vector3(-112,58,57)
	overview.look_at(Vector3(-175,0,-8))
	overview.environment = world.production.environment.environment.duplicate(true)
	overview.environment.fog_depth_begin = 110
	overview.environment.fog_depth_end = 220
	overview.make_current()
	await sample("overview_warmup",5)
	await sample("overview",5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("overview.png"))
	if not baseline:
		world.camera.make_current()
		overview.queue_free()
		world.session.state.campaign.cancel("fishing_measurement")
		world.session.state.economy.grant_reward("fishing_measurement",100)
		var site = world.session.fishing_runtime.site
		world.player.teleport(site.fishing_spots()[0].position+Vector3.UP*.03)
		world.camera.initialized = false
		await create_timer(.5).timeout
		fishing_driver = world.session.fishing
		fishing_driver._rng.seed = 71026
		if not fishing_driver.start(-1): push_error("Fishing measurement did not equip rod"); quit(6); return
		await sample("fishing_warmup",5)
		await sample("fishing",30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("fishing.png"))
		fishing_driver.cancel_attempt()
		fishing_driver = null
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"baseline":baseline,"summary":summary,"frames_ms":intervals,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"vehicles":world.production.vehicles.size(),"source_before":before,"source_after":fingerprint(),"position":str(world.player.global_position)}
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FISHING_MEASURE ",folder," ",JSON.stringify(summary))
	quit()

