extends "res://tests/test_fishing_relocation_session.gd"
## Acompanhamento visual/físico dirigido: a sessão existente já cobre o livro-razão
## e a UI da pesca. Esta jornada cobre as junções de grama/solo alteradas e o perímetro.

func fingerprint() -> Dictionary:
	var result := super.fingerprint()
	var include_path := "res://world/places/fishing/fishing_ground_surface.gdshaderinc"
	result[include_path] = FileAccess.get_sha256(include_path)
	return result

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(250).timeout.connect(func(): check(false,"finite ground journey deadline"); finish(3))
	var previous_finish := "--before" in OS.get_cmdline_user_args()
	Engine.set_meta("recreation_ground_before",previous_finish)
	folder = FIXTURE.output_dir("fishing-ground-before" if previous_finish else "fishing-ground-after")
	if not check(not folder.is_empty(),"isolated ground-review evidence directory"): finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder.path_join("route")))
	source_before = fingerprint()
	var start := LOCATION.ANCHOR+Vector3(20,.12,43)
	var snapshot := FIXTURE.full_snapshot(start,false)
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	save_path = FIXTURE.write_fixture(folder,"isolated-save.json",snapshot)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = 3.5
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	world.production.region.set_focus(start)
	world.production.region.prepare_collision_at(start)
	var car = world.driving.car
	var direction: Vector3 = LOCATION.ENTRY-start
	car.place(start,atan2(-direction.x,-direction.z))
	car.input_locked = false
	car.remove_meta("awaiting_ground")
	car.set_physics_process(true)
	car.finish_doors()
	var approach: Vector3 = car.driver_door_anchor(1)+car.global_basis.x*.6+Vector3.UP*.1
	world.player.teleport(approach)
	world.camera.initialized = false
	await create_timer(1).timeout
	if not check(world.driving.interact(),"normal car boarding before changed road apron"): finish(); return
	while world.driving.is_body_transition_active(): await physics_frame
	if not check(world.driving.occupied,"player controls the real car"): finish(); return
	Engine.max_fps = 30
	RenderingServer.frame_post_draw.connect(record_frame)
	started = Time.get_ticks_usec()
	phase = "road-apron"
	recording = true
	await create_timer(1).timeout
	await photo("road-apron")
	var route := Curve3D.new()
	route.add_point(Vector3(start.x,0,start.z))
	route.add_point(LOCATION.ENTRY)
	route.add_point(LOCATION.ANCHOR+Vector3(-10,0,27))
	if not check(await drive(route),"real wheels cross the road soil and parking blend"): finish(); return
	await photo("parking")
	if not check(world.driving.leave(),"clear parking disembark"): finish(); return
	while world.driving.is_body_transition_active(): await physics_frame
	var site = world.session.fishing_runtime.site
	if not check(is_instance_valid(site) and site.anglers.size()==5,"real lake and five anglers resident"): finish(); return
	phase = "reception-bank"
	for point in [Vector3(-3,.08,28),Vector3(10,.08,24),Vector3(3,.08,24),Vector3(0,.08,21)]:
		if not check(await walk(site.to_global(point)),"walk authored entrance and counter "+str(point)): finish(); return
	await photo("south-bank")
	phase = "perimeter"
	for index in range(49):
		var angle := PI*.5+TAU*float(index)/48.0
		var point: Vector3 = site.to_global(site._shore(angle)+site._outward(angle)*2.65+Vector3.UP*.09)
		if not check(await walk(point),"physical dry-bank perimeter segment %d"%index): finish(); return
		if index%12==0: await photo("bank-%02d"%index)
	phase = "return-apron"
	for point in [Vector3(0,.08,21),Vector3(0,.08,27),Vector3(0,.08,31)]:
		if not check(await walk(site.to_global(point)),"walk bank to apron "+str(point)): finish(); return
	await create_timer(1).timeout
	recording = false
	Engine.max_fps = 144
	check(writes_ok and missed==0 and frames.size()>600,"continuous ground sequence has no missing rendered frames")
	await oblique_photo()
	await overview_photo()
	var return_point: Vector3 = world.player.global_position
	var away := LOCATION.LEGACY_ANCHOR+Vector3(0,.1,30)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	world.session.fishing_runtime.refresh()
	for frame in 8: await process_frame
	check(not is_instance_valid(world.session.fishing_runtime.site),"leaving unloads the venue presentation")
	world.production.region.set_focus(return_point)
	world.production.region.prepare_collision_at(return_point)
	world.player.teleport(return_point)
	world.session.fishing_runtime.refresh()
	for frame in 10: await process_frame
	check(world.session.position_clear(world.player.global_position) and get_nodes_in_group("fishing_angler").size()==5,"return has stable support and one angler population")
	await photo("stream-return")
	finish()

func oblique_photo() -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 59
	camera.near = .1
	camera.far = 240
	camera.global_position = LOCATION.ANCHOR+Vector3(32,9,43)
	camera.look_at(LOCATION.ANCHOR+Vector3(0,.05,20))
	camera.make_current()
	await RenderingServer.frame_post_draw
	await photo("apron-oblique")
	previous.make_current()
	camera.queue_free()

func overview_photo() -> void:
	var previous := root.get_camera_3d()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 65
	camera.far = 450
	camera.global_position = LOCATION.ANCHOR+Vector3(63,58,60)
	camera.look_at(LOCATION.ANCHOR+Vector3(0,0,-5))
	camera.environment = world.production.environment.environment.duplicate(true)
	camera.environment.fog_depth_begin = 110
	camera.environment.fog_depth_end = 330
	camera.make_current()
	await RenderingServer.frame_post_draw
	await photo("fishing_overview")
	previous.make_current()
	camera.queue_free()
