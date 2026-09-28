extends "res://tests/measure/measure.gd"
var racing := false
var wet := false
var night := false
var expert := false
var presentation := false
var model := 0
var full_moon := false
var paddock_focus := false
var jump_photo := false
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	label = "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg == "--race": racing = true
		if arg == "--wet": wet = true
		if arg == "--night": night = true
		if arg == "--expert": expert = true
		if arg == "--presentation": presentation = true
		if arg == "--full-moon": full_moon = true
		if arg == "--paddock": paddock_focus = true
		if arg == "--jump-photo": jump_photo = true
		if arg.begins_with("--model="): model = clampi(arg.trim_prefix("--model=").to_int(),0,2)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
		if i>0 and i%600==0:
			var curtain = world.get_node_or_null("LoadingCurtain")
			print("MOTOCROSS_LOADING frames=",i," stage=",curtain._stage.text if curtain!=null and curtain._stage!=null else "no curtain"," session=",world.session!=null)
	if world.session == null or not world.session.ready_for_play:
		push_error("Motocross benchmark cannot begin: Main startup incomplete after 2400 physics frames")
		quit(1); return
	world.player.teleport(Vector3(-215,.2,-57))
	if paddock_focus: world.player.teleport(Vector3(-226,.2,-30))
	world.production.region.set_focus(world.player.position)
	world.player.controlled_automatically = true
	world.player.speed = 0
	world.camera.initialized = false
	world.camera.target_size = 36
	world.session.weather.time_of_day = .02 if night else .45
	if full_moon: world.session.state.world_state.moon_day = 4
	world.session.weather.weather_state = 2 if wet else 0
	world.session.motocross.wetness = 1.0 if wet else 0.0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	route = PackedVector3Array([Vector3(-215,.2,-57)])
	if paddock_focus: route = PackedVector3Array([Vector3(-226,.2,-30)])
	for i in 300: await physics_frame
	if racing:
		world.session.state.intro.stage = "complete"
		world.session.state.economy.grant_reward("mx_benchmark",1000)
		if expert:
			for level in 3:
				world.session.motocross.progress.begin(world.session.state.economy,level)
				world.session.motocross.progress.settle(world.session.state.economy,true)
		world.player.teleport(Vector3(-224,.15,-37))
		world.session.motocross.selected_model = model
		if presentation:
			world.session.motocross._bike_menu(3 if expert else 0)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-selection.png")
			world.session.close_menu()
		if not world.session.motocross.start_race(3 if expert else 0):
			push_error("Motocross did not start"); quit(1); return
		world.session.motocross.autopilot = true
		if presentation:
			for i in 35: await physics_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-mounting.png")
	started = Time.get_ticks_usec()
	previous = started
func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://evidence/motocross")
	var report := {"label":label,"scene":"Main.tscn / Vertice motocross","gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"population":world.people.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"intervals_ms":samples,"warmup_ms":cold,"note":"Other user Godot processes present: diagnostic comparison only."}
	report["rain"] = wet
	report["night"] = night
	report["moon_illumination"] = world.session.weather.moon_illumination()
	report["racers"] = world.session.motocross.racers.size()
	report["pilots"] = []
	for row in world.session.motocross.racers:
		var pilot: Dictionary = row.get("pilot_state",{})
		report.pilots.append({"name":row.bike.rider_name,"crashes":row.bike.crash_count,"passes":pilot.get("overtake_attempts",0),"braking":pilot.get("brake_frames",0),"accelerating":pilot.get("accelerate_frames",0),"lane_min":pilot.get("lane_min",0),"lane_max":pilot.get("lane_max",0)})
	if world.session.motocross.get("ambient") != null: report["ambient_riders"] = world.session.motocross.ambient.rows.size()
	report["model"] = model
	report["marks"] = world.session.motocross.surface_effects.mark_count
	report["cpu_process"] = stats(cpu)
	report["physics"] = stats(physics)
	report["draw_calls_last_frame"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	report["shadow_floodlights"] = 4 if night else 0
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/"+label+".png")
	FileAccess.open("res://evidence/motocross/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOTOCROSS_BENCHMARK ",JSON.stringify(report.summary))
	if racing and jump_photo:
		# Capture a natural launch after the measurement window, never pause or
		# read back GPU images during performance sampling.
		for i in 1800:
			await physics_frame
			var jumping = world.session.motocross.player_bike
			if not is_instance_valid(jumping): break
			if jumping._air_time>.16 and jumping.velocity.y>.25:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-jump.png")
				break
	paused = true
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 125
	camera.far = 500
	world.add_child(camera)
	if racing and is_instance_valid(world.session.motocross.player_bike):
		var bike = world.session.motocross.player_bike
		camera.size = 4.8
		camera.global_position = bike.global_position+bike.global_basis*Vector3(-4,2.7,-3.6)
		camera.look_at(bike.global_position+Vector3.UP*.95)
		camera.make_current()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-rider-detail.png")
	camera.size = 125
	camera.global_position = Vector3(-175,135,20)
	camera.look_at(Vector3(-175,5,-94))
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-overview.png")
	camera.size = 32
	camera.global_position = Vector3(-208,22,-34)
	camera.look_at(Vector3(-218,2,-57))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-start.png")
	camera.size = 26
	camera.global_position = Vector3(-209,20,-17)
	camera.look_at(Vector3(-229,1,-33))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-paddock.png")
	camera.size = 65
	camera.global_position = Vector3(-35,45,-45)
	camera.look_at(Vector3(-88,2,-93))
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/motocross/"+label+"-boats.png")
	quit()
