extends "res://tests/measure/measure_desert.gd"
## Main/.NET A/B using preserved sources, never replacing workspace files.
## --visual records every rendered frame separately; those timings are not FPS.
const BEFORE := "res://evidence/weather-follow-20261012/Weather.before.gd"
var visual := false
var recorder: Node
var max_speed := 0.0
var visual_failures: Array[String] = []

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	visual = "--visual" in OS.get_cmdline_user_args()
	seed(12102026)
	root.size = Vector2i(1280,720)
	output = FIXTURE.output_dir("weather-follow-visual" if visual else "weather-follow-paired")
	var path := FIXTURE.write_fixture(output,"checkpoint.json",FIXTURE.full_snapshot(Vector3(77,.08,96),true))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play or world.production.store.path!=path: quit(2); return
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native==null: quit(2); return
	fingerprint = source_fingerprint()
	for file in ["res://runtime/atmosphere/PrecipitationCoverage.gd","res://runtime/atmosphere/WeatherSurfaceEffects.gd"]:
		fingerprint[file] = FileAccess.get_sha256(file)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.gameplay.god_mode = true
	world.session.set_process_input(false)
	world.camera.set_process_unhandled_input(false)
	world.session.cold.set_process(false)
	Engine.max_fps = 60 if visual else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if visual else DisplayServer.VSYNC_DISABLED)
	for setup in [
		{"id":"city-rain","region":"harbor","point":Vector3(77,.08,96),"hour":.36},
		{"id":"desert-wind","region":"desert","point":Vector3(345,.08,-742),"hour":.45}]:
		if setup.region != world.session.state.region_id:
			if not world.production.travel(setup.region,setup.point): quit(2); return
			for i in 1800:
				await physics_frame
				if not world.production.travel_busy and world.session.ready_for_play: break
		world.player.teleport(setup.point)
		world.camera.initialized = false
		world.camera.target_size = 39
		for phase in (["after"] if visual else ["before","after"]):
			var old = world.session.weather
			world.remove_child(old)
			old.free()
			await process_frame
			var weather = load(BEFORE if phase=="before" else "res://runtime/Weather.gd").new()
			weather.controller = world.production
			world.session.weather = weather
			world.add_child(weather)
			weather.weather_state = 2
			weather.weather_timer = 10000
			weather.time_of_day = setup.hour
			weather._update()
			weather.storm.lightning_timer = 10000
			print("WEATHER_FOLLOW_BEGIN ",setup.id," ",phase," ",output)
			samples.clear()
			previous = Time.get_ticks_usec()
			sampling = not visual
			await create_timer(8).timeout
			sampling = false
			var warmup := samples.duplicate()
			if visual:
				await capture_drive(setup)
			else:
				await measure(setup.id+"-"+phase)
				reports[-1]["warmup"] = stats(warmup)
				reports[-1]["warmup_intervals_ms"] = warmup
				print("WEATHER_FOLLOW_SAMPLE ",setup.id," ",phase," ",reports[-1].summary)
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"source_stable":fingerprint==source_fingerprint(fingerprint),"source_start":fingerprint,"source_end":source_fingerprint(fingerprint),"scenarios":reports,"visual_only":visual,"max_drive_speed_mps":max_speed,"notes":"Main with live traffic/population and .NET. Paired static gameplay view at driving zoom: 8s warmup + 30s actual intervals. Visual mode separately uses real boarding and throttle with collisions, 30s per area, capture overhead excluded from performance claims. External process inventory required."}
	report["visual_failures"] = visual_failures
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WEATHER_FOLLOW_DONE ",output)
	world.queue_free()
	await process_frame
	quit(0 if visual_failures.is_empty() else 1)

func capture_drive(setup: Dictionary) -> void:
	var start := Vector3(45,.08,27) if setup.region=="harbor" else Vector3(345,.08,-470)
	world.production.region.set_focus(start)
	world.production.region.prepare_collision_at(start)
	# Keep the player outside the spawn footprint; production admission correctly
	# rejects a car that would overlap a pedestrian.
	world.player.teleport(start+Vector3(0,0,4))
	await create_timer(2).timeout
	var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start+Vector3.UP*20,start-Vector3.UP*5,1))
	if ground.is_empty(): visual_failures.append(setup.id+": no road support"); return
	start.y = ground.position.y+.12
	# Existing owned car is the fixture; weather validation does not depend on
	# ambient fleet admission or proximity-option caching after a teleport.
	var car = world.driving.car
	car.place(start,-PI*.5 if setup.region=="harbor" else 0.0)
	car.set_meta("region_id",setup.region)
	car.stolen = true
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	await physics_frame
	if not world.driving._begin_entry(car,1): visual_failures.append(setup.id+": boarding failed"); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
	if not world.driving.occupied or not car.controlled or car.input_locked:
		visual_failures.append(setup.id+": boarding incomplete")
		return
	recorder = preload("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(recorder)
	recorder.segment = setup.id
	if not recorder.begin(world,null,output.path_join(setup.id),1800):
		visual_failures.append(setup.id+": capture unavailable")
		return
	var began := Time.get_ticks_msec()
	var driving := false
	var braking := false
	var peak_speed := 0.0
	while Time.get_ticks_msec()-began<30000:
		await process_frame
		var elapsed := Time.get_ticks_msec()-began
		if elapsed>3000 and not driving:
			Input.action_press("accelerate",1.0)
			driving = true
		max_speed = maxf(max_speed,absf(car.speed))
		peak_speed = maxf(peak_speed,absf(car.speed))
		if (setup.region=="harbor" and car.global_position.x>375) or (setup.region=="desert" and car.global_position.z< -1430):
			Input.action_release("accelerate")
			Input.action_press("handbrake")
			braking = true
		if elapsed>24000 and braking: world.camera.heading = .3
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	var summary: Dictionary = recorder.stop()
	reports.append({"id":setup.id,"capture":summary,"max_speed_mps":peak_speed,"end":str(car.global_position)})
	if peak_speed<25: visual_failures.append(setup.id+": high speed not reached")
	recorder.queue_free()
	world.driving.leave()
	for i in 600:
		await physics_frame
		if not world.driving.occupied and not world.driving.is_body_transition_active(): break
