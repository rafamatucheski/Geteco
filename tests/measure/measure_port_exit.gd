extends "res://tests/measure/measure.gd"
## A/B at the exit; baseline restores only the previous flat-paving shadow flag.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	seed(29092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.camera.set_process_unhandled_input(false)
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.player.teleport(Vector3(203,.1,151))
	world.production.region.set_focus(world.player.position)
	world.camera.heading = PI*.25
	world.camera.target_size = 46
	world.camera.initialized = false
	var shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if baseline else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 300:
		await process_frame
	for mesh in world.find_children("*","MeshInstance3D",true,false):
		if str(mesh.name).begins_with("HarborRoad_") or str(mesh.name).begins_with("HarborSurface_") or str(mesh.name) in ["HarborCrosswalk","HarborTactile","HarborStopLine","HarborEarthRoad"]:
			mesh.cast_shadow = shadow_mode
	var warm: Array[float] = []
	var frames: Array[float] = []
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec()-begin < 38000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-begin < 8000000: warm.append((now-last)/1000.0)
		else: frames.append((now-last)/1000.0)
		last = now
	var folder := "res://evidence/port-exit-20261003"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"baseline":baseline,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warm),"frames_ms":frames}
	var suffix := "-confirm" if "--confirm" in OS.get_cmdline_user_args() else ""
	FileAccess.open(folder+("/performance-before" if baseline else "/performance-after")+suffix+".json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("PORT_EXIT_MEASURE ",JSON.stringify(report.summary))
	quit()
