extends "res://tests/measure/measure.gd"
## Compara a mudança do pátio de dia, quando a operação do cais não muda.
## A linha de base reconstrói só a transformação antiga do pátio neste processo.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	var variant := "before" if baseline else "after"
	var folder := "res://output/port-startup-fix-20261010/" + variant
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	seed(29092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.urban_operations.security.authorized_visit = true
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.player.teleport(Vector3(289,.1,232))
	world.production.region.set_focus(world.player.position)
	world.camera.heading = PI*.25
	world.camera.target_size = 30
	world.camera.initialized = false
	for i in 300: await process_frame
	if baseline:
		for apron in world.production.region.find_children("SouthPortConcrete","MeshInstance3D",true,false):
			apron.position.y = .007
			apron.mesh.size.y = .014
			apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var frames: Array[float] = []
	var warmup: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec()-start < 35000000:
		await process_frame
		var now := Time.get_ticks_usec()
		if now-start < 5000000: warmup.append((now-previous)/1000.0)
		else: frames.append((now-previous)/1000.0)
		previous = now
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(frames),"warmup":stats(warmup),"frames_ms":frames,"comparison":"daytime apron geometry only; night workload regression not measured"}
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("PORT_FIX_MEASURE ",variant," ",JSON.stringify(report.summary))
	# A evidência temporal é separada da cronometragem; pega todo quadro desenhado.
	Engine.max_fps = 30
	var rows: Array = []
	start = Time.get_ticks_usec()
	var index := 0
	while Time.get_ticks_usec()-start < 6000000:
		world.player.automatic_direction = Vector3.RIGHT if Time.get_ticks_usec()-start < 3000000 else Vector3.LEFT
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(folder+"/%05d.jpg"%index,.93)
		rows.append({"frame":index,"time_us":Time.get_ticks_usec()-start,"camera":str(world.camera.global_transform)})
		index += 1
		await process_frame
	FileAccess.open(folder+"/temporal.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
	world.queue_free()
	for i in 3: await process_frame
	quit()
