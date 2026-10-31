extends "res://tests/measure/measure.gd"
## Comparação renderizada em série no Main/.NET. Cada invocação mede um local.
## --parking-baseline desliga só o recurso novo no gancho de integração dele.
var folder := ""
var region_id := "harbor"
var variant := "before"
var fixture_path := ""
var spawn := Vector3(374,.12,67)
var population_samples: Array = []
var population_clock := 0.0
var sources_before := {}
var debris_events: Array = []

func source_fingerprint() -> Dictionary:
	var result := {}
	for path in ["runtime/ProductionWorld.gd","runtime/FullSession.gd","runtime/RoadsideParking.gd","scripts/Driving.gd","scripts/Vehicle.gd","scripts/Actor.gd","gameplay/VehicleBoardingPresentation.gd","gameplay/VehicleBreakIn.gd","gameplay/roadside_parking/ParkingManeuver.gd","world/roadside_parking/RoadsideParkingLayout.gd","world/roadside_parking/RoadsideParkingBay.gd","world/editing/EditableRegion.gd","world/editing/world_edits.json","world/regions/NativeRegion.gd","world/city_look/CityChunkDressing.gd","world/city_look/CityGroundLitter.gd","project.godot",".godot/mono/temp/bin/Debug/Harbor.dll"]:
		result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "missing"
	for path in ["gameplay/street_physics/StreetPhysics.gd","gameplay/street_physics/DebrisGroundProjection.gd","gameplay/NativeTrafficRoutes.gd","runtime/FleetCatalog.gd","runtime/GameState.gd","runtime/desert/DesertRuntime.gd","runtime/desert/DesertSaveContract.gd","world/urban_detail/HarborRoadGeometry3D.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "missing"
	for path in ["ui/hud/ContextualHUDManager.gd", "world/regions/OriginalWorldData.json", "world/regions/WorldConnection3D.gd"]:
		result[path]=FileAccess.get_sha256("res://"+path)
	return result

func run() -> void:
	create_timer(180).timeout.connect(func(): push_error("Roadside benchmark timeout"); quit(3))
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name()=="headless" or "--no-save" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Requires rendered .NET and --no-save"); quit(2); return
	for arg in args:
		if arg.begins_with("--parking-region="): region_id=arg.trim_prefix("--parking-region=")
		if arg.begins_with("--variant="): variant=arg.trim_prefix("--variant=").validate_filename()
	if region_id=="mountain": spawn=Vector3(656,.12,-298)
	folder="res://evidence/roadside-parking-20261006/%s-%s-%d"%[variant,region_id,OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	fixture_path=folder.path_join("fixture.json")
	var state=preload("res://runtime/GameState.gd").new()
	var intro: Dictionary=state.intro.snapshot()
	intro.phase="complete"
	intro.location_id="harbor_street"
	intro.inventory={}
	intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	if not state.intro.restore_snapshot(intro): quit(2); return
	state.set_location(region_id)
	state.world_state.time=.45
	state.world_state.weather=0
	state.world_state.pedestrian={"region":region_id,"position":[spawn.x,spawn.y,spawn.z]}
	var store=preload("res://runtime/SaveStore.gd").new()
	store.path=fixture_path
	if store.save(state)!=OK: quit(2); return
	seed(610206)
	sources_before=source_fingerprint()
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",fixture_path)
	root.add_child(world)
	current_scene=world
	for index in 6000:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or not world.production.loaded_save:
		push_error("Main checkpoint did not start"); quit(3); return
	if world.dispatch!=null: world.dispatch.router.nearest_edge(spawn)
	if world.dispatch==null or world.dispatch.router._native==null:
		push_error(".NET dispatch router unavailable"); quit(3); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.camera.heading=0
	world.camera.target_size=32
	world.camera.initialized=false
	world.session.weather.time_of_day=.45
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	world.session.weather._update()
	world.diagnostic_label.hide()
	route=PackedVector3Array([spawn,spawn+Vector3(4,0,0)])
	world.player.speed=1.5
	started=Time.get_ticks_usec()
	previous=started

func _process(delta: float) -> bool:
	if started>0:
		# As mesmas três rajadas reais de StreetPhysics nas duas variantes, numa vaga visível.
		# Isto compara a correção relatada de destroços flutuantes junto com a carga do estacionamento.
		if measuring and debris_events.size()<3:
			var elapsed := float(Time.get_ticks_usec()-measured_started)/1000000.0
			if elapsed>=4.0+float(debris_events.size())*10.0:
				var street = world.get_node_or_null("StreetPhysics")
				if street!=null:
					var began := Time.get_ticks_usec()
					street.spawn_glass(spawn+Vector3(0,1.1,4),Vector3.RIGHT)
					debris_events.append({"seconds":elapsed,"cpu_ms":float(Time.get_ticks_usec()-began)/1000.0})
		population_clock+=delta
		if population_clock>=1:
			population_clock=0
			population_samples.append({"people":world.people.size(),"vehicles":world.production.vehicles.size(),"position":str(world.player.global_position)})
	return super._process(delta)

func finish() -> void:
	world.player.automatic_direction=Vector3.ZERO
	var report={"region":region_id,"variant":variant,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"frames_ms":samples,"warmup_ms":cold,"cpu":stats(cpu),"physics":stats(physics),"population":population_samples,"save_isolated":world.production.store.path==fixture_path,"notes":"Actual Main scene and production population; fixture start, not a driven regional transition. Temporary saves only."}
	var director=world.production.get("roadside_parking")
	report.debris_events=debris_events
	report.debris_baseline="--debris-baseline" in OS.get_cmdline_user_args()
	report.sources_before=sources_before
	report.sources_after=source_fingerprint()
	report.sources_stable=report.sources_before==report.sources_after
	if is_instance_valid(director) and director.has_method("debug_snapshot"): report.parking=director.debug_snapshot()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join("scene.png"))
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROADSIDE_BENCHMARK ",folder," ",JSON.stringify(report.summary))
	world.queue_free()
	await process_frame
	quit()
