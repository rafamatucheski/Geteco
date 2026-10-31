extends "res://tests/measure/measure.gd"
## Mesmas duas vans de entrega, cidade, semente e câmera antes/depois; sem save do usuário.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	seed(23107)
	load("res://gameplay/icecream/IceCreamVan.gd").enabled = "--without-icecream" not in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play: await process_frame
	if world.dispatch.router._native_graph() == null: quit(2); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.teleport(Vector3(66,.15,129))
	world.production.region.set_focus(world.player.global_position)
	world.camera.target_size = 25
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .4
	world.session.weather.weather_state = 0
	world.session.weather._update()
	await create_timer(12).timeout
	var vans: Array = []
	for i in 2:
		var car = load("res://scripts/Vehicle.gd").new()
		car.archetype = "courier_van"
		car.vehicle_id = "street_icecream_fixture_%d" % i
		car.paint_color = Color("fff0dd")
		car.position = Vector3(64+i*5,.2,125)
		world.add_child(car)
		car.traffic = true
		vans.append(car)
	await create_timer(10).timeout
	var frames: Array[float] = []
	var ambient_start := {}
	var ambient_max := 0
	var ambient_moved := false
	var begin := Time.get_ticks_usec()
	var last := begin
	while Time.get_ticks_usec()-begin < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last = now
		var ambient_count := 0
		for car in world.production.vehicles:
			if not is_instance_valid(car) or not car.traffic or not str(car.vehicle_id).begins_with("street_icecream_"): continue
			ambient_count += 1
			if not ambient_start.has(car.vehicle_id): ambient_start[car.vehicle_id] = car.distance_travelled
			if car.distance_travelled-float(ambient_start[car.vehicle_id]) > 2: ambient_moved = true
		ambient_max = maxi(ambient_max,ambient_count)
	var folder := "res://evidence/icecream/"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report := {"summary":stats(frames),"frames_ms":frames,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"vehicles":world.production.vehicles.size(),"people":world.people.size(),"native_router":true,"seed":23107,"ambient_icecream_seen":ambient_start.size(),"ambient_icecream_max":ambient_max,"ambient_icecream_moved":ambient_moved}
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	print("ICECREAM_BENCH ",JSON.stringify(report.summary))
	print("ICECREAM_LIVE seen=",ambient_start.size()," max=",ambient_max," moved=",ambient_moved)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/gameplay.png")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = vans[0].global_position+Vector3(6,3.5,-6)
	camera.look_at(vans[0].global_position+Vector3.UP*1.4)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/van.png")
	world.free()
	await process_frame
	quit(0 if "--validate-traffic" not in OS.get_cmdline_user_args() or (ambient_start.size()>0 and ambient_max<=2 and ambient_moved) else 1)
