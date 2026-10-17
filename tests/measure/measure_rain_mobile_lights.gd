extends "res://tests/measure/measure_rain_driving.gd"
## Actual driving + rain. Reference equipment is injected only in this process.
## Every native rendered frame is archived; JPEG encoding runs on worker threads.
const OUT := "res://evidence/mobile-lights-rain-20261015"
var reference := false
var capture := false
var ffmpeg := ""
var only_cases := "dry-driving,rain-driving"
var tag := "current"
var phase := ""
var records: Array[Dictionary] = []
var capture_pid := -1
var source_failures := 0
var frame_zero := 0
var old_equipment: Script
var record_after := false
var pending_encodes: Array[int] = []
var frame_folder := ""
var reverse_route := false
var record_cases := "rain-driving,rain-belt,rain-weapon"

func present() -> void: pass

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg == "--reference": reference = true
		if arg == "--capture": capture = true
		if arg == "--record-after": record_after = true
		if arg == "--reverse": reverse_route = true
		if arg.begins_with("--record-cases="): record_cases = arg.trim_prefix("--record-cases=")
		if arg.begins_with("--ffmpeg="): ffmpeg = arg.trim_prefix("--ffmpeg=")
		if arg.begins_with("--cases="): only_cases = arg.trim_prefix("--cases=")
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	create_timer(600).timeout.connect(func():
		if capture_pid > 0 and OS.is_process_running(capture_pid): OS.kill(capture_pid)
		quit(3))
	DirAccess.make_dir_recursive_absolute(OUT)
	if reference:
		old_equipment = load(OUT+"/reference/LegacyEquipment.gd")
		assert(old_equipment != null)
		# Vehicle is already preloaded by gameplay dependencies: replace complete
		# equipment instances, including future spawns, rather than just its cache.
		node_added.connect(_reference_node_added)
	seed(15102026)
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_title("GetecoLightsRainValidation")
	DisplayServer.window_move_to_foreground()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	assert(world.session != null and world.session.ready_for_play)
	if reference:
		for vehicle in world.find_children("*","CharacterBody3D",true,false):
			if vehicle.has_method("ensure_equipment") and is_instance_valid(vehicle.equipment): _reference_equipment(vehicle.equipment)
		await process_frame
	world.dispatch.router.nearest_edge(world.player.position)
	assert(world.dispatch.router._native != null and OS.get_environment("HARBOR_NO_CSHARP").is_empty(),"Real C# backend required")
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	game_input = root.get_node("GameInput")
	game_input.using_gamepad = false
	weather = world.session.weather
	weather.time_of_day = .93
	weather.weather_timer = 100000
	car = world.driving.car
	path = world.production.traffic_routes.route_between(Vector3(400,0,25),Vector3(30,0,25),Vector3.LEFT) if reverse_route else world.production.traffic_routes.route_between(Vector3(30,0,25),Vector3(400,0,25),Vector3.RIGHT)
	assert(path != null)
	initial_offset = path.get_closest_offset(Vector3(355,0,25) if reverse_route else Vector3(35,0,25))
	reset_car()
	for i in 6: await physics_frame
	world.player.teleport(car.driver_door_anchor(-1))
	assert(world.driving._begin_entry(car,-1))
	deadline = Time.get_ticks_msec()+15000
	while not car.controlled and Time.get_ticks_msec()<deadline: await physics_frame
	assert(car.controlled)
	car.health = 1000000
	car.equipment.headlights_on = true
	car.equipment._refresh()
	assert(not reference or car.equipment.get_script() == old_equipment,"Reference must actually replace production equipment")
	var probe := Probe.new()
	probe.owner_probe = self
	probe.process_priority = 110
	probe.process_physics_priority = -10
	root.add_child(probe)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var settings := root.get_node("V2Settings")
	report = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,"shadow_quality":settings.shadow_quality,"target_ms":16.67,"regression_confirmation_percent":5,"reference":reference,"capture":capture,"native_csharp":true,"actual_reference_equipment":reference and car.equipment.get_script()==old_equipment,"cases":[],"source_hashes":{}}
	report.reverse_route = reverse_route
	for p in ["res://gameplay/VehicleEquipment.gd","res://gameplay/lights/LightBudget.gd","res://scripts/Vehicle.gd","res://runtime/transit/BiarticulatedBus.gd","res://world/city_look/CityLocalLighting.gd","res://runtime/Weather.gd","res://runtime/atmosphere/CoastalRainPresentation.gd","res://runtime/atmosphere/RainGroundPresentation.gd","res://runtime/atmosphere/PrecipitationCoverage.gd","res://world/city_look/CoastalPlanarReflections.gd"]:
		report.source_hashes[p] = FileAccess.get_sha256(p)
	var scenarios := only_cases.split(",")
	if record_after:
		for scenario in record_cases.split(","): scenarios.append(scenario+"-video")
	var capture_only := capture
	for requested in scenarios:
		var scenario := requested.trim_suffix("-video")
		capture = capture_only or requested.ends_with("-video")
		if capture:
			Engine.max_fps = 60
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		phase = scenario
		var on_foot := scenario in ["rain-belt","rain-weapon"]
		if on_foot and world.driving.occupied:
			world.session.state.intro.stage = "complete"
			running = false
			game_input.touch_move = Vector2.ZERO
			car.place(Vector3(67.5,.1,139),0)
			if car.handling != null: car.handling.reset()
			world.session.controller.region.set_focus(car.global_position)
			await create_timer(2.0).timeout
			assert(world.driving.leave())
			deadline = Time.get_ticks_msec()+15000
			while (world.driving.occupied or world.driving.is_body_transition_active()) and Time.get_ticks_msec()<deadline: await physics_frame
			assert(not world.driving.occupied)
			world.player.teleport(Vector3(64,.1,146))
			world.session.controller.region.set_focus(world.player.global_position)
		if on_foot:
			world.gameplay.state.economy.cheat_infinite_money = true
			if not world.gameplay.belt_flashlight.owned: world.gameplay.belt_flashlight.purchase()
			world.gameplay.belt_flashlight.enabled = scenario == "rain-belt"
			world.gameplay.belt_flashlight.update_visibility()
			world.gameplay.state.grant_weapon("pistol")
			world.gameplay.state.equip_weapon("pistol" if scenario == "rain-weapon" else "fists")
			if scenario == "rain-weapon": world.gameplay.buy_attachment("pistol","flashlight")
			world.gameplay.flashlight_enabled = scenario == "rain-weapon"
			world.gameplay._update_visual()
		weather.weather_state = 0 if scenario.begins_with("dry") else 1
		weather.rain_intensity = .30
		weather.coastal_wetness = 0.0 if scenario.begins_with("dry") else 1.0
		weather.weather_timer = 100000
		weather.time_of_day = .93
		weather._update()
		moving = scenario.ends_with("driving")
		if not on_foot:
			reset_car()
			world.camera.initialized = false
		car.equipment.headlights_on = true
		car.equipment._refresh()
		running = not on_foot
		await sample(8.0)
		DisplayServer.window_move_to_foreground()
		if capture:
			assert(FileAccess.file_exists(ffmpeg))
			frame_folder = OUT.path_join(tag+"-"+scenario+"-frames")
			DirAccess.make_dir_recursive_absolute(frame_folder)
		records = []
		source_failures = 0
		frame_zero = Time.get_ticks_usec()
		var start_distance: float = car.distance_travelled
		print("RAIN_LIGHT_BEGIN ",tag," ",scenario," reference=",reference," capture=",capture)
		var data := await sample_lights(30.0,on_foot)
		var travelled: float = car.distance_travelled-start_distance
		var item := {"scenario":scenario,"capture":capture,"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"summary":stats(data.frames),"frames_ms":data.frames,"cpu_ms":data.cpu,"gpu_ms":data.gpu,"physics_ms":data.physics,"render_cpu_ms":data.render_cpu,"speed_mps":data.speed,"distance_m":travelled,"unfocused_frames":data.unfocused,"draw_calls":data.draws,"camera_size":world.camera.size,"controlled":car.controlled,"external_input":car.external_input,"source_visibility_failures":source_failures,"broken_left":car.equipment.broken_left,"broken_right":car.equipment.broken_right,"telemetry":records}
		for key in ["cpu","gpu","physics","render_cpu","speed"]: item[key+"_summary"] = distribution(data[key])
		report.cases.append(item)
		FileAccess.open(OUT.path_join(tag+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("RAIN_LIGHT_RESULT ",tag," ",scenario," ",JSON.stringify(item.summary)," distance=",travelled," source_failures=",source_failures)
		running = false
		game_input.touch_move = Vector2.ZERO
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(tag+"-"+scenario+".png"))
		if moving: assert(travelled>100.0,"Real driving must cover at least 100 metres")
		if capture:
			for task in pending_encodes: WorkerThreadPool.wait_for_task_completion(task)
			pending_encodes.clear()
			assert(encode_native_frames(scenario),"Native frame video must encode")
	probe.queue_free()
	report.source_hashes_end = {}
	for p in report.source_hashes: report.source_hashes_end[p] = FileAccess.get_sha256(p)
	FileAccess.open(OUT.path_join(tag+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	world.queue_free()
	await process_frame
	quit()

func _reference_node_added(node: Node) -> void:
	var script := node.get_script() as Script
	if script != null and script.resource_path == "res://gameplay/VehicleEquipment.gd":
		_reference_equipment.call_deferred(node)

func _reference_equipment(previous_kit: Node) -> void:
	if not is_instance_valid(previous_kit) or not previous_kit.is_inside_tree() or previous_kit.get_script() == old_equipment: return
	var vehicle = previous_kit.car
	if not is_instance_valid(vehicle) or vehicle.equipment != previous_kit: return
	var replacement = old_equipment.new()
	replacement.configure(vehicle,previous_kit.world)
	replacement.headlights_on = previous_kit.headlights_on
	replacement.siren_on = previous_kit.siren_on
	replacement.broken_left = previous_kit.broken_left
	replacement.broken_right = previous_kit.broken_right
	vehicle.remove_child(previous_kit)
	previous_kit.queue_free()
	vehicle.equipment = replacement
	vehicle.add_child(replacement)

func sample_lights(seconds: float,on_foot: bool) -> Dictionary:
	var frame_samples: Array[float] = []
	var data := {"frames":frame_samples,"cpu":[],"gpu":[],"physics":[],"render_cpu":[],"speed":[],"draws":[],"unfocused":0}
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < int(seconds*1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		data.frames.append(float(now-previous)/1000.0)
		previous = now
		data.cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		data.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		data.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		data.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		data.speed.append(car.horizontal_velocity.length())
		data.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if not DisplayServer.window_is_focused(): data.unfocused += 1
		var active := 0
		for entry in car.equipment.lamps:
			if entry.lamp.is_visible_in_tree() and entry.lamp.light_energy > 0: active += 1
		if not on_foot and active != car.equipment.lamps.size(): source_failures += 1
		if on_foot and phase == "rain-belt" and not world.gameplay.belt_flashlight.lamp.is_visible_in_tree(): source_failures += 1
		if on_foot and phase == "rain-weapon" and not world.gameplay.flashlight.is_visible_in_tree(): source_failures += 1
		if capture:
			var npc: Array = []
			for vehicle in world.production.vehicles:
				if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.equipment): continue
				var beam: SpotLight3D = vehicle.equipment.npc_beam
				if beam.is_visible_in_tree(): npc.append({"id":vehicle.get_instance_id(),"position":str(vehicle.global_position),"energy":beam.light_energy})
			await RenderingServer.frame_post_draw
			var stamp := Time.get_ticks_usec()
			var picture := root.get_texture().get_image()
			var filename := "frame-%06d.jpg" % records.size()
			var destination := frame_folder.path_join(filename)
			var task := WorkerThreadPool.add_task(func(): picture.save_jpg(destination,.85),false,"light frame JPEG")
			pending_encodes.append(task)
			for finished in pending_encodes.duplicate():
				if WorkerThreadPool.is_task_completed(finished):
					WorkerThreadPool.wait_for_task_completion(finished)
					pending_encodes.erase(finished)
			if pending_encodes.size()>8: WorkerThreadPool.wait_for_task_completion(pending_encodes.pop_front())
			records.append({"us":stamp-frame_zero,"engine_frame":Engine.get_process_frames(),"file":filename,"car_position":str(car.global_position),"speed":car.horizontal_velocity.length(),"player_lamps":active,"npc":npc,"camera":str(world.camera.global_position)})
	return data

func encode_native_frames(scenario: String) -> bool:
	var manifest := FileAccess.open(frame_folder.path_join("frames.txt"),FileAccess.WRITE)
	for index in records.size():
		manifest.store_line("file '%s'" % records[index].file)
		manifest.store_line("option framerate 1000")
		var duration := float(records[index+1].us-records[index].us)/1000000.0 if index+1<records.size() else 1.0/60.0
		manifest.store_line("duration %.6f" % duration)
	manifest.close()
	var log: Array = []
	var output := ProjectSettings.globalize_path(OUT.path_join(tag+"-"+scenario+".mp4"))
	var result := OS.execute(ffmpeg,["-hide_banner","-loglevel","warning","-y","-f","concat","-safe","0","-i",ProjectSettings.globalize_path(frame_folder.path_join("frames.txt")),"-fps_mode","vfr","-an","-c:v","h264_nvenc","-preset","p1","-cq","20","-pix_fmt","yuv420p",output],log,true,false)
	FileAccess.open(frame_folder.path_join("encoder.log"),FileAccess.WRITE).store_string(str(log))
	return result==0 and FileAccess.file_exists(output)
