extends "res://tests/measure/measure.gd"
## One finite Main/.NET comparison of the two requested recreational areas.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const PARK = preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const FISH = preload("res://runtime/FishingLocation.gd")
var folder := ""
var phase := ""
var intervals := {}
var populations := {}
var tracing := false
var tick := 0

func fingerprint() -> Dictionary:
	var result: Dictionary = FIXTURE.source_fingerprint()
	for dir in ["res://world/places/amusement_park","res://runtime/amusement_park","res://world/places/fishing","res://activities/amusement_park","res://activities/fishing"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") or file.ends_with(".gdshader") or file.ends_with(".gdshaderinc"): result[dir.path_join(file)] = FileAccess.get_sha256(dir.path_join(file))
	for path in ["res://runtime/FishingLocation.gd","res://runtime/FishingRuntime.gd","res://gameplay/urban_v1/FreightOutskirts.gd","res://world/regions/NativeRegion.gd","res://world/city_look/CityChunkDressing.gd","res://world/editing/world_edits.json"]:
		result[path] = FileAccess.get_sha256(path)
	for path in ["res://tests/measure/measure_park_countryside.gd","res://activities/motocross/MotocrossLandscape.gdshaderinc","res://activities/motocross/MotocrossGroundDetail.gd","res://world/urban_detail/RuralGroundMaterial.gd","res://world/urban_detail/rural_ground.gdshader"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _process(_delta: float) -> bool:
	if tracing:
		var now := Time.get_ticks_usec()
		intervals[phase].append(float(now-tick)/1000.0)
		tick = now
	return false

func population() -> Dictionary:
	var fish = world.session.fishing_runtime.site
	var park = world.session.amusement_park.site
	return {"people":world.people.size(),"cars":world.production.vehicles.size(),"anglers":fish.anglers.size() if is_instance_valid(fish) else 0,"park_nodes":park.get_child_count() if is_instance_valid(park) else 0,"clowns":get_nodes_in_group("park_clown").size()}

func sample(id: String, seconds: float) -> void:
	phase = id
	intervals[id] = []
	populations[id] = {"start":population()}
	tick = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false
	populations[id].end = population()
	print("COUNTRYSIDE_PHASE ",id," frames=",intervals[id].size())

func photo(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func move_to(at: Vector3) -> void:
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	world.player.teleport(at)
	world.camera.initialized = false
	world.camera.make_current()
	await sample("arrival_"+str(intervals.size()),8)

func panorama(at: Vector3, target: Vector3, id: String) -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.far = 450
	camera.fov = 65
	camera.global_position = at
	camera.look_at(target)
	camera.environment = world.production.environment.environment.duplicate(true)
	camera.environment.fog_depth_begin = 110
	camera.environment.fog_depth_end = 330
	camera.make_current()
	await sample(id+"_warmup",4)
	await sample(id,30)
	await photo(id)
	world.camera.make_current()
	camera.queue_free()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(330).timeout.connect(func(): push_error("Finite measurement timeout"); quit(3))
	seed(81026)
	var ground_review := "--ground-blend" in OS.get_cmdline_user_args()
	var ground_before := "--before" in OS.get_cmdline_user_args()
	if ground_review: Engine.set_meta("recreation_ground_before",ground_before)
	label = ("ground-before" if ground_before else "ground-after") if ground_review else ("before" if ground_before else "after")
	folder = FIXTURE.output_dir("park-countryside-"+label)
	var before := fingerprint()
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	snapshot.world.time = .45
	snapshot.world.weather = 0
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"fixture.json",snapshot))
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Native C# required"); quit(5); return
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	await move_to(PARK.ORIGIN+Vector3(12,.1,19))
	await sample("park_walk",30)
	await photo("park_walk")
	await panorama(PARK.ORIGIN+Vector3(58,48,64),PARK.ORIGIN+Vector3.UP*3,"park_overview")
	await move_to(FISH.ANCHOR+Vector3(0,.1,30))
	await sample("fishing_entry",30)
	await photo("fishing_entry")
	await panorama(FISH.ANCHOR+Vector3(63,58,60),FISH.ANCHOR+Vector3(0,0,-5),"fishing_overview")
	var summary := {}
	for id in intervals:
		var values: Array[float] = []
		values.assign(intervals[id])
		if not values.is_empty(): summary[id] = stats(values)
	var after := fingerprint()
	var report := {"label":label,"summary":summary,"samples_ms":intervals,"populations":populations,"source_before":before,"source_after":after,"source_stable":before==after,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"native":true,"fishing_anchor":str(FISH.ANCHOR),"weather":0,"hour":.45}
	if ground_review:
		report.ground_before = ground_before
		report.comparison = "Original authored ground versus integrated grass, selected once during scene construction; identical Main, actors, weather and .NET route service."
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUNTRYSIDE_MEASURE ",folder," ",JSON.stringify(summary))
	quit()
