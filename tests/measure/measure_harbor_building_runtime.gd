extends "res://tests/measure/measure.gd"
## A/B of the real Main scene. Never use headless results as frame evidence.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
var folder := ""
var scenario := "street"
var place := "harbor_customs_house"
var service_id := ""
var night := false
var tracing := false
var trace_last := 0
var phase := ""
var intervals := {}

func fingerprints() -> Dictionary:
	var paths: Array[String] = ["project.godot","Main.tscn","scripts/CameraRig.gd","runtime/FullSession.gd","runtime/ProductionWorld.gd","runtime/HarborBuildingRuntime.gd","runtime/HarborServiceRoofRuntime.gd","runtime/Weather.gd","runtime/Settings.gd","world/regions/NativeRegion.gd","world/editing/world_edits.json","world/regions/OriginalWorldData.json","world/city_look/CityChunkDressing.gd","gameplay/urban_v1/PortDepotBuilding.gd"]
	for filename in DirAccess.get_files_at("res://world/places/harbor_buildings"):
		if filename.ends_with(".gd") or filename.ends_with(".gdshader"): paths.append("world/places/harbor_buildings/"+filename)
	paths.append_array(["world/city_look/CityLook.gd","world/city_look/CityLocalLighting.gd","world/city_look/CityContextIndex.gd","world/city_look/CityTransitReservations.gd"])
	for filename in ["UrbanOperations","TruckersVillageVisuals","TruckersVillageHomes","TruckersVillageFleet","PortOperations","PortCargoOperations","PortLogistics","VerticeCompany","CemeteryOperations"]:
		paths.append("gameplay/urban_v1/"+filename+".gd")
	var result := {}
	for path in paths: result[path] = FileAccess.get_sha256("res://"+path)
	return result

func _process(_delta: float) -> bool:
	if not tracing: return false
	var now := Time.get_ticks_usec()
	if not intervals.has(phase): intervals[phase] = []
	intervals[phase].append(float(now-trace_last)/1000.0)
	trace_last = now
	return false

func sample_phase(next: String, seconds: float) -> void:
	phase = next
	trace_last = Time.get_ticks_usec()
	tracing = true
	await create_timer(seconds).timeout
	tracing = false

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Rendered Main required"); quit(2); return
	create_timer(240).timeout.connect(func(): quit(3))
	seed(100726)
	var batch_baseline := "--batch-baseline" in OS.get_cmdline_user_args()
	var lights_baseline := "--lights-baseline" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=")
		if arg.begins_with("--scene="): scenario=arg.trim_prefix("--scene=")
		if arg.begins_with("--place="): place=arg.trim_prefix("--place=")
		if arg.begins_with("--service="): service_id=arg.trim_prefix("--service=")
		night = night or arg == "--night"
	var definition := CATALOG.find(place).duplicate(true)
	var service: Dictionary = preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd").find(service_id)
	if not service_id.is_empty():
		if service.is_empty() or service_id not in ["harbor_bank","vertice_roof"] or batch_baseline: quit(4); return
		place = service_id
		definition = service.duplicate(true)
		definition.entry_position = service.exterior_position+Vector3(0,.08,service.size.y*.5+2)
		definition.return_position = definition.entry_position
	if definition.is_empty() or (batch_baseline and scenario!="street"): quit(4); return
	Engine.set_meta("harbor_buildings_measure_baseline",batch_baseline)
	Engine.set_meta("harbor_building_lights_baseline",lights_baseline)
	var source_before := fingerprints()
	folder = FIXTURE.output_dir("harbor-runtime-"+label)
	# Start beyond staging range so the first approach includes facade carving,
	# the first room, residents and rendering uploads rather than a warmed room.
	var snapshot := FIXTURE.full_snapshot(definition.return_position+Vector3(0,.08,24),true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.world.time = .90 if night else .45
	snapshot.world.weather = 0
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("C# runtime required"); quit(5); return
	world.session.weather.time_of_day = snapshot.world.time
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	phase = "first_approach"
	trace_last = Time.get_ticks_usec()
	tracing = true
	world.production.region.set_focus(definition.entry_position)
	world.player.teleport(definition.return_position+Vector3.UP*.08)
	await create_timer(5.0).timeout
	tracing = false
	if service_id.is_empty() and not batch_baseline and (not is_instance_valid(world.session.building_entrance.staged) or world.session.building_entrance.staged.definition.id!=place):
		push_error("First approach did not stage the measured building")
		quit(9)
		return
	if scenario!="street":
		phase = "first_entry"
		trace_last = Time.get_ticks_usec()
		tracing = true
		if service_id.is_empty():
			if not await world.session.enter_place(place,true): quit(6); return
		elif service_id=="harbor_bank":
			if not await world.session.enter_place(service_id,true): quit(6); return
		else:
			var depot = world.session.urban_operations.cargo_handling.depot
			world.player.teleport(depot.to_global(Vector3(29.05,.04,28.3)))
		if not service_id.is_empty():
			var runtime = world.session.service_roofs
			var deadline := Time.get_ticks_msec()+8000
			while runtime.access_definition.get("id","")!=service_id and Time.get_ticks_msec()<deadline: await physics_frame
			if runtime.access_definition.get("id","")!=service_id: quit(7); return
			world.player.teleport(runtime.access_point)
			if scenario=="roof" and not await runtime.use_stairs(): quit(7); return
		elif scenario=="roof":
			var room = world.session.room
			for level in range(1,int(definition.floor_count)+1):
				world.player.teleport(room.to_global(room.stair_point())+Vector3.UP*.04)
				if not await room.change_floor(level): quit(7); return
		tracing = false
	await sample_phase("warmup",5.0)
	await sample_phase("steady",30.0)
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("scene.png"))
	var source_after := fingerprints()
	var report := {"label":label,"scenario":scenario,"place":place,"service":service_id,"night":night,"batch_baseline":batch_baseline,"lights_baseline":lights_baseline,"summary":summary,"samples_ms":intervals,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"people":world.people.size(),"cars":world.production.vehicles.size(),"native":world.dispatch.router._native!=null,"source_before":source_before,"source_after":source_after,"source_stable":source_before==source_after}
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BUILDING_RUNTIME_MEASURE ",folder," ",JSON.stringify(summary))
	quit(0 if report.source_stable else 8)
