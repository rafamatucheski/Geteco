extends "res://tests/measure/measure.gd"
## Comparative rendered Harbor fixture. Captures happen outside the sample.
var scenario := "exterior"
var output := "res://evidence"
var probe: Dictionary = {}
var neon_review := false
var neon_only := false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--evidence-dir="): output = arg.trim_prefix("--evidence-dir=")
		if arg=="--review-neon": neon_review = true
		if arg=="--neon-only": neon_only = true
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size() >= world.production.requested_population: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Story benchmark startup failed"); quit(1); return
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.speed = 1.5
	world.session.weather.time_of_day = .94
	world.session.weather.weather_state = 0
	world.session.weather.rain_intensity = 0.0
	world.session.weather._update()
	var point := Vector3(161.25,.08,76)
	if scenario == "workshop": point = Vector3(166,.08,111)
	if scenario == "jessica": point = Vector3(40.625,.08,18.5)
	world.production.region.set_focus(point)
	for i in 10: await physics_frame
	if not world.session.position_clear(point):
		push_error("Story benchmark walking origin blocked at %s" % point); quit(1); return
	world.player.teleport(point)
	world.camera.target = world.player
	if scenario == "jessica":
		# The same authored checkpoint is used in the populated after sample.
		# This measures the production character/car, not bank gameplay coverage.
		var catalog = preload("res://data/campaign/HarborMissions.gd")
		var checkpoint: Dictionary = world.session.state.campaign.snapshot()
		checkpoint.completed = ["primeiro_giro","cobra_contact","cobra_race"]
		checkpoint.claimed_rewards = checkpoint.completed.duplicate()
		for id in checkpoint.completed:
			for flag in catalog.MISSIONS[id].sets_flags: checkpoint.flags[flag] = true
			world.session.state.economy.grant_reward("campaign:"+id,int(catalog.MISSIONS[id].reward))
		if not world.session.state.campaign.restore_snapshot(checkpoint):
			push_error("Jessica benchmark checkpoint invalid"); quit(1); return
		for i in 180:
			await physics_frame
			if is_instance_valid(world.session.jessica.car) and is_instance_valid(world.session.jessica.actor): break
		if not is_instance_valid(world.session.jessica.car):
			push_error("Jessica benchmark did not instantiate the real car"); quit(1); return
		probe.jessica_active = true
	if neon_only:
		await review_neon()
		world.free()
		await process_frame
		quit()
		return
	route = PackedVector3Array([point,point+Vector3(3,0,0)])
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(18,3,13)
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY,world.maciota_place.exterior_origin+Vector3.UP*1.65)
	probe.workshop_overlap = world.get_world_3d().direct_space_state.intersect_shape(q,16).size()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+"-start.png"))
	started = Time.get_ticks_usec()
	previous = started

func finish() -> void:
	var report := {"label":label,"scenario":scenario,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"population":world.people.size(),"requested_population":world.production.requested_population,"cars":world.production.vehicles.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":stats(samples),"warmup":stats(cold),"cpu_process":stats(cpu),"physics":stats(physics),"frame_intervals_ms":samples,"player_distance":world.player.travelled,"probe":probe}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	var file := FileAccess.open(output.path_join(label+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("STORY_BENCHMARK ",JSON.stringify(report.summary)," ",JSON.stringify(probe))
	if neon_review and scenario=="jessica": await review_neon()
	world.free()
	await process_frame
	quit()

func review_neon() -> void:
	# This bounded temporal capture runs after the uncapped benchmark sample.
	# Its 60 FPS ceiling protects desktop use and is not a performance result.
	var previous_cap := Engine.max_fps
	Engine.max_fps = 60
	world.player.automatic_direction = Vector3.ZERO
	world.player.set_physics_process(false)
	if neon_only:
		# Review from an available orbit angle around the real parked car;
		# the south-facing benchmark view can be obscured by passing buses.
		world.camera.target = world.session.jessica.car
		world.camera.heading = PI*.5
		world.camera.target_size = 18.0
		world.camera.initialized = false
		world.camera._process(1.0)
	var effect = world.session.jessica._neon
	world.session.weather.time_of_day = .5
	world.session.weather._update()
	await create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("jessica-day.png"))
	var day := {"strength":effect.strength,"visible":effect.ground_light.visible,"energy":effect.ground_light.light_energy}
	world.session.weather.time_of_day = .94
	world.session.weather._update()
	await create_timer(3.0).timeout
	var sequence: Array[Dictionary] = []
	var frames_dir := output.path_join("jessica-neon-frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var began := Time.get_ticks_msec()
	var index := 0
	var next_full_capture := 0
	while Time.get_ticks_msec()-began < 30000:
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var reviewed_car: CharacterBody3D = world.session.jessica.car
		var camera_local: Vector3 = reviewed_car.to_local(world.camera.global_position)
		var ground: Vector3 = reviewed_car.to_global(Vector3((-1.0 if camera_local.x<0 else 1.0)*1.35,0,.25))
		var pixel: Vector2 = world.camera.unproject_position(ground)
		var logical_size: Vector2 = world.camera.get_viewport().get_visible_rect().size
		pixel *= Vector2(frame.get_width(),frame.get_height())/logical_size
		var roi := Rect2i(Vector2i(pixel)-Vector2i(64,48),Vector2i(128,96)).intersection(Rect2i(Vector2i.ZERO,frame.get_size()))
		if roi.has_area(): frame.get_region(roi).save_png(frames_dir.path_join("%05d.png"%index))
		var total := 0.0
		var count := 0
		for y in range(maxi(0,int(pixel.y)-6),mini(frame.get_height(),int(pixel.y)+6)):
			for x in range(maxi(0,int(pixel.x)-12),mini(frame.get_width(),int(pixel.x)+12)):
				var color := frame.get_pixel(x,y)
				total += color.r-(color.g+color.b)*.5
				count += 1
		sequence.append({"t_ms":Time.get_ticks_msec(),"strength":effect.strength,"visible":effect.ground_light.visible,
			"energy":effect.ground_light.light_energy,"red_ground":total/maxi(1,count),"sample_pixels":count,"ground_pixel":str(pixel)})
		if Time.get_ticks_msec()-began >= next_full_capture:
			frame.save_png(output.path_join("jessica-night-%05d.png"%index))
			next_full_capture += 7500
		index += 1
	FileAccess.open(output.path_join("jessica-neon-temporal.json"),FileAccess.WRITE).store_string(JSON.stringify({"day":day,"night":sequence,"rendered":true,"capture_fps_cap":60,"roi_frames":frames_dir,"duration_ms":Time.get_ticks_msec()-began,"camera_heading":world.camera.heading,"camera_size":world.camera.size,"car_position":str(world.session.jessica.car.global_position),"limits":"Continuous rendered ground ROI at stationary bank street; camera-distance and pursuit lighting are not certified by this capture. Inspect actual timestamp gaps and visual occlusion before judging temporal coverage."},"\t"))
	Engine.max_fps = previous_cap
