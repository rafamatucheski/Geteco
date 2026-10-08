extends "res://tests/measure/measure.gd"
## Rendered Main scene, isolated checkpoint, finite 30-second samples.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var folder := ""
var phase := ""
var intervals: Dictionary = {}
var last_tick := 0
var source_start := {}

func fingerprints() -> Dictionary:
	var result := {}
	var paths: Array[String] = ["res://runtime/FullSession.gd","res://runtime/ProductionWorld.gd","res://world/regions/NativeRegion.gd","res://world/places/PlaceCatalog.gd","res://runtime/Weather.gd","res://project.godot"]
	for directory in ["res://runtime","res://world","res://activities","res://gameplay","res://traffic","res://ui","res://data","res://native"]:
		_source_paths(directory,paths)
	for path in paths: result[path] = FileAccess.get_sha256(path)
	return result

func _source_paths(directory: String, paths: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(directory): return
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() in ["gd","cs","tscn","tres","gdshader","json"]:
			paths.append(directory.path_join(filename))
	for child in DirAccess.get_directories_at(directory):
		if not child.begins_with("."): _source_paths(directory.path_join(child),paths)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(240).timeout.connect(func(): quit(3))
	seed(81026)
	var before := "--arcade-before" in OS.get_cmdline_user_args()
	Engine.set_meta("arcade_baseline", before)
	label = "arcade-before" if before else "arcade-after"
	folder = FIXTURE.output_dir(label)
	source_start = fingerprints()
	var snapshot := FIXTURE.full_snapshot(Vector3(80,.2,16.55), true)
	snapshot.campaign.aftermath = {"call_complete":true}
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# runtime required"); quit(4); return
	world.session.weather.weather_timer = 9999
	await sample_arcade("street-warmup",5)
	await photo("street")
	await sample_arcade("street",31)
	if not before and "--interior" in OS.get_cmdline_user_args():
		phase = "entry"
		last_tick = Time.get_ticks_usec()
		if not await world.session.enter_place("harbor_arcade"): quit(5); return
		phase = ""
		await sample_arcade("room-warmup",5)
		await photo("room")
		await sample_arcade("room",31)
		world.player.teleport(world.session.room.interaction_points.arcade_racer+Vector3.UP*.05)
		await physics_frame
		if not world.session.arcade.perform("racer"): quit(6); return
		await sample_arcade("racer-warmup",3)
		world.session.arcade.ui.start_game()
		await process_frame
		await process_frame
		Input.action_press("move_up")
		await sample_arcade("racer",31)
		Input.action_release("move_up")
		await photo("racer")
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"summary":summary,"samples_ms":intervals,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null,"baseline":before}
	report.source_start = source_start
	report.source_end = fingerprints()
	report.source_stable = report.source_start == report.source_end
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARCADE_MEASURE ",folder," ",JSON.stringify(summary))
	quit(0)

func sample_arcade(id: String, seconds: float) -> void:
	phase = id
	last_tick = Time.get_ticks_usec()
	await create_timer(seconds).timeout
	phase = ""

func _process(_delta: float) -> bool:
	if not phase.is_empty():
		var now := Time.get_ticks_usec()
		if not intervals.has(phase): intervals[phase] = []
		intervals[phase].append(float(now-last_tick)/1000.0)
		last_tick = now
	return false

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))
