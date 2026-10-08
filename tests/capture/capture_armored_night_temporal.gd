extends SceneTree
## Visual evidence only: continuous rendered frames, never an FPS benchmark.
## The fixture represents a delayed evening service already loading at North Pier.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const SCHEDULE := preload("res://gameplay/armored/ArmoredSchedule.gd")
var world
var output := ""
var fingerprint: Dictionary = {}
var timestamps: Array[Dictionary] = []
var states: Array[Dictionary] = []
var gateway_driving := false
var bridge_seam := false
const BRIDGE_SEAM := Vector3(344.1,2.4,-373.5)
var _follow_at := 0
var observer_moves := 0

func _initialize() -> void:
	create_timer(320).timeout.connect(func(): push_error("ARMORED_NIGHT_TIMEOUT"); quit(3))
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var rear_view := "--rear" in args
	bridge_seam = "--bridge-seam" in args
	gateway_driving = "--gateway-driving" in args or bridge_seam
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--benchmark" not in args or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered .NET with --benchmark --no-save required")
		quit(2); return
	seed(7102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("armored-night-temporal")
	fingerprint = FIXTURE.source_fingerprint()
	for filename in DirAccess.get_files_at("res://gameplay/armored"):
		if filename.ends_with(".gd"):
			var path: String = "res://gameplay/armored/"+filename
			fingerprint[path] = FileAccess.get_sha256(path)
	for path in ["res://gameplay/VehicleEquipment.gd","res://gameplay/VehicleLightProfiles.gd","res://runtime/FleetCatalog.gd","res://tests/capture/capture_armored_night_temporal.gd"]:
		fingerprint[path] = FileAccess.get_sha256(path)
	if bridge_seam:
		for path in ["res://world/desert/DesertRoadGeometry.gd","res://world/desert/DesertRegion.gd"]:
			fingerprint[path] = FileAccess.get_sha256(path)
	var point := Vector3(37.625,.12,18.875)
	if gateway_driving: point = Vector3(372,.12,-240)
	if bridge_seam: point = Vector3(335,2.52,-285)
	var snapshot := FIXTURE.full_snapshot(point,true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "harbor"
	snapshot.world.pedestrian = {"region":"harbor","position":[point.x,point.y,point.z]}
	snapshot.world.moon_day = 5
	snapshot.world.time = .90
	snapshot.world.weather = 0
	var event := SCHEDULE.initial(SCHEDULE.departure(5,17.0/24.0),0)
	if bridge_seam:
		snapshot.world.moon_day = 1
		snapshot.world.time = 9.0/24.0
		event = SCHEDULE.initial(SCHEDULE.departure(1,9.0/24.0),0)
	if gateway_driving:
		event.phase = "driving"
		event.cargo_cycles = [2,2]
		event.route_offset = 560.0
		if bridge_seam: event.route_offset = 690.0
	snapshot.world[SCHEDULE.KEY] = {"version":1,"last_event":event.id,"security_level":0,"event":event}
	var save_path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	if save_path.is_empty(): quit(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	for frame in 7000:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session == null or not world.session.ready_for_play or world.production.save_invalid or world.production.store.path != save_path:
		push_error("ARMORED_NIGHT startup/isolation failed"); quit(1); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = 9.0/24.0 if bridge_seam else .90
	world.session.weather._update()
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("ARMORED_NIGHT requires native routes"); quit(1); return
	var convoy = world.session.armored_transport
	var deadline := Time.get_ticks_msec()+18000
	while convoy.fleet.size() != 4 and Time.get_ticks_msec() < deadline: await physics_frame
	if convoy.fleet.size() != 4: push_error("ARMORED_NIGHT fleet admission failed"); quit(1); return
	# Retain the production lens, pitch, framing and camera update. A stationary
	# observation target centers the existing camera on the two real cash trucks.
	var camera_target := Node3D.new()
	world.add_child(camera_target)
	camera_target.global_position = (convoy.fleet[0].global_position+convoy.fleet[1].global_position)*.5
	if bridge_seam: camera_target.global_position = BRIDGE_SEAM
	world.camera.target = camera_target
	world.camera.initialized = false
	world.camera.heading = PI if rear_view else 0.0
	if gateway_driving: world.camera.heading = PI+.65
	await create_timer(5).timeout
	Engine.max_fps = 30
	var frames_dir := output.path_join("frames")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_dir))
	var began := Time.get_ticks_usec()
	var previous_frame := -1
	var missed_frames := 0
	var previous_state_second := -1
	var writes_ok := true
	while Time.get_ticks_usec()-began < (10000000 if rear_view else 30000000):
		var seconds := float(Time.get_ticks_usec()-began)/1000000.0
		if gateway_driving:
			if convoy.fleet.size() != 4: push_error("ARMORED_NIGHT physical fleet lost"); break
			if not bridge_seam: camera_target.global_position = (convoy.fleet[0].global_position+convoy.fleet[1].global_position)*.5
			_follow_observer(convoy)
		# 10s static, 10s slow available orbit, 10s return to the initial heading.
		if not gateway_driving: world.camera.heading = PI if rear_view else (0.0 if seconds < 10 else minf(seconds-10,30-seconds)*.045)
		await RenderingServer.frame_post_draw
		var captured_at := Time.get_ticks_usec()
		seconds = float(captured_at-began)/1000000.0
		var render_frame := Engine.get_frames_drawn()
		if previous_frame >= 0: missed_frames += maxi(0,render_frame-previous_frame-1)
		previous_frame = render_frame
		var frame := root.get_texture().get_image()
		var index := timestamps.size()
		writes_ok = frame.save_jpg(frames_dir.path_join("%05d.jpg" % index),.9) == OK and writes_ok
		if index == 0: frame.save_png(output.path_join("night-start.png"))
		timestamps.append({"frame":index,"render_frame":render_frame,"usec":captured_at,"elapsed_seconds":seconds,"heading":world.camera.heading,"camera":str(world.camera.global_transform)})
		if int(seconds) != previous_state_second:
			previous_state_second = int(seconds)
			states.append(_lighting_state(convoy,seconds))
	var stable := true
	for path in fingerprint:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != fingerprint[path]: stable = false
	var report := {"rear_view":rear_view,"recording_complete":writes_ok and missed_frames == 0 and stable,"source_stable":stable,"source_sha256":fingerprint,"save":save_path,"frames":timestamps.size(),"seconds":float(Time.get_ticks_usec()-began)/1000000.0,"missed_render_frames":missed_frames,"timestamps":timestamps,"states":states,"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"viewport":str(root.get_visible_rect().size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"notes":"Continuous rendered frame capture with timestamps at temporary 30FPS cap; readback/encoding overhead is included, so NOT FPS/performance evidence. Actual Main bank service, normal population and production camera pitch/framing. Evening service is admitted from a valid late-loading fixture, not evidence that its entire afternoon route was played. Default: first10s camera static, next10s slow orbit, last10s return. With --rear: 10s static rear view only. recording_complete concerns recording integrity only; visual stability requires inspection. Does not cover highway motion, rain or streaming re-entry."}
	report["gateway_driving"] = gateway_driving
	report["observer_validated_teleports"] = observer_moves
	if gateway_driving:
		report["notes"] = "Actual Main restored driving checkpoint at route offset560, late-night dry gateway approach. Four physical vehicles, normal traffic controller/collisions and production camera pitch/framing. Camera follows truck midpoint; only observer is repositioned onto position_clear footholds for streaming. Captures every rendered frame with timestamps. NOT FPS evidence: concurrent functional tests, temporary30FPS capture cap and JPEG/readback overhead. Does not prove prior route, rain, distant streaming re-entry or entire bridge traversal; inspect recorded positions and support."
	report["bridge_seam"] = bridge_seam
	if bridge_seam:
		report["notes"] = "Actual Main restored post-gateway driving checkpoint offset690. Dry09:00, fixed production camera angle/pitch/framing aimed at bridge/desert asphalt seam(344.1,2.4,-373.5). Four vehicles drive physically; only observer may be repositioned onto position_clear footholds.30s all-render-frame recording, timestamps and one-second body/wheel support rays. Includes lead approach then both trucks and tail; scene visibility must be inspected because a fixed seam camera intentionally does not follow distant bodies. NOT FPS evidence. Baseline physical failure recorded in armored-route-post-gateway-cobre.log; no rendered baseline was present in its evidence folder. Does not certify whole desert, complete bridge, rain, reverse crossing or streaming re-entry."
	FileAccess.open(output.path_join("temporal.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARMORED_NIGHT_TEMPORAL ",output," frames=",timestamps.size()," missed=",missed_frames," source_stable=",stable)
	quit(0 if report.recording_complete else 1)

func _lighting_state(convoy,seconds: float) -> Dictionary:
	var cars: Array[Dictionary] = []
	for car in convoy.fleet:
		if not is_instance_valid(car): continue
		var lights: Array[Dictionary] = []
		for lamp in car.find_children("*","Light3D",true,false):
			lights.append({"name":str(lamp.name),"visible":lamp.is_visible_in_tree(),"position":str(lamp.global_position),"energy":lamp.light_energy,"shadows":lamp.shadow_enabled})
		var query := PhysicsRayQueryParameters3D.create(car.global_position+Vector3.UP,car.global_position-Vector3.UP*1.2,1)
		var supported: bool = not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		cars.append({"id":car.vehicle_id,"point":str(car.global_position),"speed":car.speed,"health":car.health,"visible":world.production._on_screen(car.global_position,3.0),"supported":supported,"lights":lights,"equipment_ready":is_instance_valid(car.equipment)})
		if bridge_seam:
			var wheel_support: Array[Dictionary] = []
			for wheel in car.wheels:
				var wheel_query := PhysicsRayQueryParameters3D.create(wheel.global_position+Vector3.UP*.5,wheel.global_position-Vector3.UP*1.2,1)
				var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(wheel_query)
				wheel_support.append({"wheel":str(wheel.global_position),"ground":str(hit.get("position",Vector3.INF)),"normal":str(hit.get("normal",Vector3.ZERO)),"supported":not hit.is_empty()})
			cars[-1]["wheel_support"] = wheel_support
	return {"seconds":seconds,"phase":convoy.data.get("phase",""),"cars":cars,"guards":convoy.guards.size(),"ambient_vehicles":world.production.vehicles.size(),"people":world.people.size(),"hour":world.session.weather.time_of_day}

func _follow_observer(convoy) -> void:
	if Time.get_ticks_msec() < _follow_at: return
	_follow_at = Time.get_ticks_msec()+500
	var lead = convoy.fleet[2]
	if world.player.global_position.distance_to(lead.global_position) < 28: return
	for lateral in [5.0,-5.0,3.8,-3.8,8.0,-8.0,11.0,-11.0,15.0,-15.0]:
		for along in [0.0,5.0,-5.0]:
			var point: Vector3 = lead.global_position+lead.global_basis.x*lateral+lead.global_basis.z*along
			if world.session.position_clear(point):
				world.player.teleport(point)
				observer_moves += 1
				return
