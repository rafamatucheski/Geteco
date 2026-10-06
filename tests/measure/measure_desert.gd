extends SceneTree
## Actual rendered Main/.NET, finite scenarios; no isolated showroom FPS claims.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var output := ""
var samples: Array[float] = []
var cpu: Array[float] = []
var physics: Array[float] = []
var previous := 0
var sampling := false
var reports: Array[Dictionary] = []
var fingerprint: Dictionary = {}
func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("DESERT_MEASURE timeout"); quit(3))
	run.call_deferred()
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if sampling:
		samples.append(float(now-previous)/1000.0)
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	previous=now
	return false
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--benchmark" not in OS.get_cmdline_user_args() or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with --benchmark --no-save required")
		quit(2)
		return
	seed(6102026)
	root.size=Vector2i(1280,720)
	output=FIXTURE.output_dir("desert-main-measure")
	var snapshot:=FIXTURE.full_snapshot(Vector3(300,.08,-742),true)
	snapshot.region_id="desert"
	snapshot.world.pedestrian={"region":"desert","position":[300,.08,-742]}
	var path:=FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if path.is_empty(): quit(1); return
	fingerprint=source_fingerprint()
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path or world.production.save_invalid:
		push_error("Main native startup/isolation failed"); quit(1); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: push_error("Compiled route backend unavailable"); quit(1); return
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.session.weather.weather_state=0
	world.session.weather.weather_timer=3600
	for setup in [
		{"id":"truckstop-day","point":Vector3(300,.08,-742),"hour":.45},
		{"id":"town-night","point":Vector3(-185,.08,-890),"hour":.9},
	]:
		world.production.region.set_focus(setup.point)
		world.production.region.prepare_collision_at(setup.point)
		await physics_frame
		world.player.teleport(setup.point)
		world.session.weather.time_of_day=setup.hour
		world.session.weather._update()
		await create_timer(10).timeout
		await measure(setup.id)
	for id in ["desert_bank","desert_digo"]:
		var definition:=preload("res://world/places/PlaceCatalog.gd").get_definition(id)
		world.production.region.set_focus(definition.entry_position)
		world.production.region.prepare_collision_at(definition.entry_position)
		await physics_frame
		world.player.teleport(definition.entry_position+Vector3.UP*.08)
		if not await world.session.enter_place(id,false): push_error("Interior entry failed: "+id); quit(1); return
		await create_timer(10).timeout
		await measure(id)
		if not await world.session.leave_place(): push_error("Interior exit failed: "+id); quit(1); return
	# The third scenario actually drives the kilometre highway; fixture placement
	# only establishes its start. Normal vehicle handling and streaming remain live.
	var point:=Vector3(345,.1,-470)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point+Vector3.RIGHT*3)
	await create_timer(2).timeout
	var car=world.production.spawn_vehicle("desert_coyote",point,0)
	if not is_instance_valid(car): push_error("Highway car admission failed"); quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+Vector3(.4,.05,0))
	if not world.driving.interact(): push_error("Highway boarding failed"); quit(1); return
	var boarding_deadline:=Time.get_ticks_msec()+10000
	while world.driving.is_body_transition_active() and Time.get_ticks_msec()<boarding_deadline: await physics_frame
	if not world.driving.occupied or world.driving.car!=car or not car.controlled or car.input_locked: push_error("Highway boarding incomplete"); quit(1); return
	world.session.weather.time_of_day=.45
	world.session.weather._update()
	Input.action_press("accelerate",.32)
	var start: Vector3=car.global_position
	await measure("highway-drive")
	Input.action_release("accelerate")
	Input.action_press("handbrake")
	reports[-1].distance=start.distance_to(car.global_position)
	reports[-1].end=str(car.global_position)
	var valid: bool=car.global_position.y>-.3 and reports[-1].distance>150 and fingerprint==source_fingerprint(fingerprint)
	var result:={"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"args":OS.get_cmdline_args(),"user_args":OS.get_cmdline_user_args(),"isolated_save":path,"source_stable":fingerprint==source_fingerprint(fingerprint),"scenarios":reports,"valid":valid,"notes":"Main .NET with real population and ordinary gameplay camera. Four 10s warmups and 30s steady captures, plus a physical 30s highway traversal including first visits. GPU/CPU attribution requires additional instrumentation. Compare bridge before/after separately; these are new-region absolute measurements, not a before/after certification."}
	result["source_sha256_start"]=fingerprint
	result["source_sha256_end"]=source_fingerprint(fingerprint)
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("DESERT_MEASURE ",output," valid=",valid)
	quit(0 if valid else 1)
func measure(id: String) -> void:
	samples.clear(); cpu.clear(); physics.clear()
	previous=Time.get_ticks_usec()
	sampling=true
	await create_timer(30).timeout
	sampling=false
	reports.append({"id":id,"summary":stats(samples),"intervals_ms":samples.duplicate(),"cpu_ms":cpu.duplicate(),"physics_ms":physics.duplicate(),"people":world.people.size(),"vehicles":world.production.vehicles.size(),"hour":world.session.weather.time_of_day,"camera_size":world.camera.size,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(id+".png"))
	# Preserve completed samples if a later transition fails. A partial file never
	# claims a complete benchmark and cannot replace report.json.
	FileAccess.open(output.path_join("partial.json"),FileAccess.WRITE).store_string(JSON.stringify({"complete":false,"source_stable":fingerprint==source_fingerprint(fingerprint),"scenarios":reports},"\t"))
func stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var ordered:=values.duplicate()
	ordered.sort()
	var total:=0.0
	var over33:=0
	var over66:=0
	for value in values:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	return {"frames":values.size(),"seconds":total/1000.0,"fps":values.size()*1000.0/maxf(total,.001),"p50_ms":ordered[int((ordered.size()-1)*.5)],"p95_ms":ordered[int((ordered.size()-1)*.95)],"p99_ms":ordered[int((ordered.size()-1)*.99)],"max_ms":ordered[-1],"over_33_3_ms":over33,"over_66_7_ms":over66}

func source_fingerprint(reference: Dictionary = {}) -> Dictionary:
	if not reference.is_empty():
		var checked: Dictionary={}
		for path in reference: checked[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
		return checked
	var result:=FIXTURE.source_fingerprint()
	for path in ["res://ui/hud/ContextualHUDManager.gd","res://scripts/Vehicle.gd","res://scripts/Driving.gd","res://runtime/Weather.gd","res://runtime/atmosphere/RegionalAtmosphere3D.gd","res://audio/WorldAudio.gd","res://gameplay/VehicleEquipment.gd"]:
		result[path]=FileAccess.get_sha256(path)
	for directory in ["res://world/desert","res://runtime/desert","res://activities/desert_drag","res://gameplay/desert_cars","res://audio/desert_cars","res://audio/desert_ambience"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd") or filename.ends_with(".gdshader"):
				var path: String=directory+"/"+filename
				result[path]=FileAccess.get_sha256(path)
	return result
