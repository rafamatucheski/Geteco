extends "res://tests/measure/measure.gd"
## Paired rendered comparison of current materials and local geometry reflections.
const TRIAL := preload("res://tests/capture/CoastalReflectionProbeTrial.gd")
const FACADE := preload("res://tests/capture/CoastalFacadeTrial.gd")
const FOLDER := "res://evidence/coastal-weather-20261013/reflection-measure"

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	seed(13102026)
	root.size = Vector2i(1280,720)
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
	for i in 180: await process_frame
	world.camera.target_size = 48
	var weather = world.session.weather
	weather.weather_timer = 100000
	weather.rain_intensity = .25
	var probe := TRIAL.install(world)
	var report := {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"cases":[]}
	for entry in [["c-rain",.45,1],["night-rain",.93,1]]:
		TRIAL.set_experimental_wet_road(world,false)
		probe.visible = false
		for node in world.find_children("CoastalFacadeTrial","Node3D",true,false): node.queue_free()
		weather.time_of_day = entry[1]
		weather.weather_state = entry[2]
		weather.coastal_wetness = 1.0
		for i in 200: weather._update()
		for mode in ["current","geometry-reflections"]:
			var capture_report := {}
			if mode=="geometry-reflections":
				capture_report.facade = FACADE.apply(world)
				capture_report.road_materials = TRIAL.set_experimental_wet_road(world,true)
				capture_report.probe = await TRIAL.capture_static(world,probe)
			var warm: Array[float] = []
			var measured: Array[float] = []
			var begin := Time.get_ticks_usec()
			var last := begin
			while Time.get_ticks_usec()-begin<38000000:
				await process_frame
				var now := Time.get_ticks_usec()
				if now-begin<8000000: warm.append((now-last)/1000.0)
				else: measured.append((now-last)/1000.0)
				last = now
			var id: String = entry[0]+"-"+mode
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(FOLDER+"/"+id+".png")
			var result := {"id":id,"camera_size":world.camera.size,"camera_position":str(world.camera.global_position),"population":world.people.size(),"capture":capture_report,"summary":stats(measured),"warmup":stats(warm),"frames_ms":measured,"warmup_ms":warm}
			report.cases.append(result)
			FileAccess.open(FOLDER+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			print("COASTAL_REFLECTION_MEASURE ",id," ",JSON.stringify(result.summary))
	TRIAL.set_experimental_wet_road(world,false)
	world.queue_free()
	for i in 6: await process_frame
	quit()
