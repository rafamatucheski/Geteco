extends SceneTree
## Concept framing and continuous rendered weather transitions in actual Main.
var world
var folder := "res://evidence/coastal-weather-20261013/visual-final"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var temporal := "--temporal" in OS.get_cmdline_user_args()
	var motion_after := "--motion-after" in OS.get_cmdline_user_args()
	var reflection_trial := "--reflection-trial" in OS.get_cmdline_user_args()
	var measure_first := "--measure-first" in OS.get_cmdline_user_args()
	var external_video := "--external-video" in OS.get_cmdline_user_args()
	var only := ""
	var motion_cases := "c-rain,night-rain"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg.begins_with("--motion-cases="): motion_cases = arg.trim_prefix("--motion-cases=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(13102026)
	root.size = Vector2i(1920,1080)
	if temporal or motion_after: root.size = Vector2i(1280,720)
	if external_video:
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_title("Coastal Visual Validation")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.gameplay.health = 1000000
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.position)
	world.camera.set_process_unhandled_input(false)
	world.camera.heading = 0
	world.camera.initialized = false
	var weather = world.session.weather
	weather.weather_timer = 100000
	weather.rain_intensity = .25
	weather.coastal_wetness = 0
	weather.time_of_day = .72
	weather.weather_state = 0
	weather._visual_clouds = 0
	for i in 180: await process_frame
	world.camera.target_size = 48
	for i in 60: await process_frame
	if external_video:
		await record_motion(world.session.weather)
		await verify_reflection_transitions()
		world.queue_free()
		for i in 6: await process_frame
		quit()
		return
	var reflection
	var reflection_helper
	if reflection_trial:
		print("COASTAL_FACADE_TRIAL ",load("res://tests/capture/CoastalFacadeTrial.gd").apply(world))
		reflection_helper = load("res://tests/capture/CoastalReflectionProbeTrial.gd")
		reflection = reflection_helper.install(world)
	var cases := [["a-dry",.72,0],["b-marine",.72,3],["c-rain",.45,1],["c-storm",.45,2],["night-rain",.93,1],["drying",.72,0]]
	var report := {"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cases":[],"note":"Rendered Main, normal population/traffic. Weather states injected to examine authored transitions. Frame readback/JPEG overhead and temporary30FPS cap mean this is NOT performance evidence."}
	var original_fps_limit := Engine.max_fps
	for entry in cases:
		if not only.is_empty() and entry[0] not in only.split(","): continue
		if reflection_trial: reflection_helper.set_experimental_wet_road(world,false)
		weather.time_of_day = entry[1]
		weather.weather_state = entry[2]
		if measure_first:
			weather.coastal_wetness = 1.0 if entry[2] in [1,2] else 0.0
			for i in 200: weather._update()
			var warm_ms: Array[float] = []
			var measured_ms: Array[float] = []
			var begin := Time.get_ticks_usec()
			var last := begin
			while Time.get_ticks_usec()-begin<38000000:
				await process_frame
				var now := Time.get_ticks_usec()
				if now-begin<8000000: warm_ms.append((now-last)/1000.0)
				else: measured_ms.append((now-last)/1000.0)
				last = now
			FileAccess.open(folder+"/frame-times.json",FileAccess.WRITE).store_string(JSON.stringify({"case":entry[0],"resolution":str(root.size),"max_fps":original_fps_limit,"vsync":DisplayServer.window_get_vsync_mode(),"camera_size":world.camera.size,"warmup_ms":warm_ms,"frames_ms":measured_ms},"\t"))
			print("COASTAL_FRAME_MEASURE ",entry[0]," frames=",measured_ms.size())
			measure_first = false
		if temporal: Engine.max_fps = 30
		if not temporal:
			weather.coastal_wetness = .7 if entry[0]=="drying" else 1.0 if entry[2] in [1,2] else 0.0
			for i in 200: weather._update()
			for i in 150: await process_frame
			if reflection_trial:
				reflection_helper.set_experimental_wet_road(world,entry[2] in [1,2])
				print("COASTAL_PROBE_TRIAL ",await reflection_helper.capture_static(world,reflection))
				for i in 60: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png")
			var planar: Node = world.get_node_or_null("CityLook/CoastalPlanarReflections")
			if planar != null:
				for kind in ["ground", "facade"]:
					var view: SubViewport = planar.get(kind+"_view")
					var capture := view.get_texture().get_image()
					capture.convert(Image.FORMAT_RGBA8)
					capture.save_png(folder+"/"+entry[0]+"-"+kind+".png")
				print("COASTAL_PLANAR registered=",planar._registered.size()," dynamic=",planar._dynamic.size()," ground=",planar._ground_active," facade=",is_instance_valid(planar._facade))
			print("COASTAL_CAPTURE ",entry[0])
			print("COASTAL_SHADOW ",entry[0]," blur=",world.production.sun.shadow_blur," opacity=",world.production.sun.shadow_opacity," quality=",root.get_node("V2Settings").shadow_quality)
			if not motion_after or entry[0] not in motion_cases.split(","): continue
		var frames_dir: String = folder+"/"+entry[0]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_dir))
		var timestamps: Array = []
		var previous_frame := -1
		var missed := 0
		var writes_ok := true
		var began := Time.get_ticks_usec()
		while Time.get_ticks_usec()-began<30000000:
			var seconds := (Time.get_ticks_usec()-began)/1000000.0
			# Static10s, slow camera orbit10s, return10s. Traffic remains live.
			world.camera.heading = 0.0 if seconds<10 else minf(seconds-10,30-seconds)*.025
			await RenderingServer.frame_post_draw
			var drawn := Engine.get_frames_drawn()
			if previous_frame>=0: missed += maxi(0,drawn-previous_frame-1)
			previous_frame = drawn
			var frame := root.get_texture().get_image()
			frame.resize(960,540,Image.INTERPOLATE_BILINEAR)
			writes_ok = frame.save_jpg(frames_dir+"/%05d.jpg"%timestamps.size(),.88)==OK and writes_ok
			timestamps.append({"seconds":(Time.get_ticks_usec()-began)/1000000.0,"frame":drawn,"clouds":weather._visual_clouds,"wetness":weather.coastal_wetness,"sun_angle":world.production.sun.rotation_degrees.x})
		world.camera.heading = 0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png")
		report.cases.append({"id":entry[0],"missed_render_frames":missed,"writes_ok":writes_ok,"timestamps":timestamps})
		FileAccess.open(folder+"/temporal.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
		print("COASTAL_TEMPORAL ",entry[0]," frames=",timestamps.size()," missed=",missed)
	if reflection_trial:
		reflection_helper.set_experimental_wet_road(world,false)
		reflection.queue_free()
	if "--verify-transitions" in OS.get_cmdline_user_args(): await verify_reflection_transitions()
	world.queue_free()
	for i in 6: await process_frame
	quit()

func record_motion(weather) -> void:
	weather.time_of_day = .45
	weather.weather_state = 1
	weather.coastal_wetness = 1
	for i in 200: weather._update()
	for i in 90: await process_frame
	print("COASTAL_VIDEO_READY")
	# External window capture avoids synchronous GPU image readback per frame.
	await create_timer(5).timeout
	var begin := Time.get_ticks_usec()
	var changed := false
	while Time.get_ticks_usec()-begin < 60000000:
		var seconds := (Time.get_ticks_usec()-begin)/1000000.0
		world.camera.heading = sin(maxf(0, seconds-6)*.17)*.28 if seconds < 28 else sin(maxf(0, seconds-36)*.17)*.28
		if seconds >= 28 and not changed:
			changed = true
			weather.time_of_day = .93
			print("COASTAL_VIDEO night at ",seconds)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/motion-final.png")
	print("COASTAL_VIDEO_DONE")

func verify_reflection_transitions() -> void:
	var planar: Node = world.get_node("CityLook/CoastalPlanarReflections")
	var errors: Array[String] = []
	for camera in [planar.ground_camera, planar.facade_camera]:
		if camera.physics_interpolation_mode != Node.PHYSICS_INTERPOLATION_MODE_OFF:
			errors.append("Reflection camera must copy the displayed pose without physics interpolation")
	if not planar._ground_active: errors.append("Wet Harbor capture must be active")
	if not is_instance_valid(planar._facade): errors.append("Police facade must be selected")
	if planar._bits != Vector2i(1<<17,1<<16): errors.append("Reserved layers changed")
	var entered: bool = await world.session.enter_place("maciota",false)
	for i in 6: await process_frame
	if not entered or planar._active: errors.append("Garage must suspend coastal capture")
	if world.session.state.weapons_allowed(): errors.append("Garage weapon restriction changed")
	if entered: await world.session.leave_place()
	for i in 30: await process_frame
	if not planar._ground_active: errors.append("Exit must resume wet capture")
	world.session.weather.coastal_wetness = 0
	for i in 3: await process_frame
	if planar._ground_active: errors.append("Dry pavement must stop ground capture")
	FileAccess.open(folder+"/transitions.json",FileAccess.WRITE).store_string(JSON.stringify({"errors":errors,"registered":planar._registered.size(),"batches":planar._batches.size()},"\t"))
	print("COASTAL_PLANAR_TRANSITIONS errors=",errors)
