extends "res://tests/measure/measure.gd"
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var folder := ""
var intervals := {}
var phase := ""
var tracing := false
var last_tick := 0
var overview: Camera3D

func fingerprints() -> Dictionary:
	var paths := ["res://project.godot","res://runtime/FullSession.gd","res://runtime/ProductionWorld.gd","res://runtime/Weather.gd","res://gameplay/Gameplay.gd","res://world/regions/NativeRegion.gd","res://world/desert/DesertHorizon.gd","res://world/desert/DesertHorizonRelief.gd"]
	for directory in ["res://runtime/coastal_lookout","res://world/places/coastal_lookout"]:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".gd") or file.ends_with(".gdshader"): paths.append(directory.path_join(file))
	var hashes := {}
	for path in paths: hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _process(_delta: float) -> bool:
	if tracing:
		var now := Time.get_ticks_usec()
		if not intervals.has(phase): intervals[phase] = []
		intervals[phase].append(float(now-last_tick)/1000.0)
		last_tick = now
	return false

func sample(next: String, seconds: float) -> void:
	phase = next
	last_tick = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240).timeout.connect(func(): quit(3))
	seed(100726)
	var source_before := fingerprints()
	var baseline := "--lookout-baseline" in OS.get_cmdline_user_args()
	var preview := "--preview" in OS.get_cmdline_user_args()
	Engine.set_meta("coastal_lookout_baseline",baseline)
	label = "baseline" if baseline else "final"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	folder = FIXTURE.output_dir("coastal-lookout-"+label)
	# Start at the existing Maciota return, outside scenic residency. The first
	# approach below includes construction of this feature, not a prebuilt site.
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	snapshot.world.time = .45
	snapshot.world.weather = 0
	world = load("res://Main.tscn").instantiate()
	var save_path := FIXTURE.write_fixture(folder,"save.json",snapshot)
	if save_path.is_empty(): push_error("Invalid isolated measurement fixture"); quit(7); return
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# required"); quit(5); return
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	# --skip-arrival deliberately returns to Maciota; establish the measured site
	# after that productive startup flow, never assume fixture coordinates survived.
	var entry := Vector3(319.5,.1,-130.5)
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	world.player.teleport(entry)
	world.camera.initialized = false
	await sample("first_approach",8)
	if world.player.global_position.distance_to(entry) > 2.0:
		push_error("Measurement did not remain at lookout entrance: "+str(world.player.global_position)); quit(6); return
	await sample("warmup",5)
	await sample("entrance",1 if preview else 30)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("entrance.png"))
	overview = Camera3D.new()
	overview.far = 4000
	overview.fov = 58
	world.add_child(overview)
	overview.global_position = Vector3(350,43,-128)
	overview.look_at(Vector3(303,5,-190))
	# The diagnostic overview uses panorama distances rather than Harbor's 75m
	# orthographic haze. Identical environment on both sides of the A/B.
	overview.environment = world.production.environment.environment.duplicate(true)
	overview.environment.fog_depth_begin = 150
	overview.environment.fog_depth_end = 2400
	overview.make_current()
	await sample("overview_warmup",5)
	await sample("overview",1 if preview else 30)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("overview.png"))
	if preview:
		print("COASTAL_LOOKOUT_PREVIEW ",folder)
		quit()
		return
	if not baseline:
		world.camera.make_current()
		overview.queue_free()
		var site = world.session.coastal_lookout.site
		world.player.teleport(site.binocular_interaction_position()+Vector3.UP*.04)
		await create_timer(1).timeout
		if not await world.session.interact() or not world.session.coastal_lookout.active:
			push_error("Optical performance scenario did not enter the real binocular"); quit(8); return
		await sample("optic_warmup",5)
		await sample("optic",30)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("optic.png"))
		world.session.coastal_lookout.leave()
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"label":label,"baseline":baseline,"summary":summary,"samples_ms":intervals,"position":str(world.player.global_position),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null}
	report.source_before = source_before
	if world.session.coastal_lookout!=null:
		var runtime = world.session.coastal_lookout
		report.template_prepare_ms = runtime.get_meta("template_prepare_ms",0)
		report.residency_install_ms = runtime.get_meta("last_residency_install_ms",0)
		report.template_generation_count = runtime.get_meta("template_generation_count",0)
	report.source_after = fingerprints()
	report.source_stable = report.source_before == report.source_after
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COASTAL_LOOKOUT_MEASURE ",folder," ",JSON.stringify(summary))
	quit()
