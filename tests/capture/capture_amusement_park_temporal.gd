extends SceneTree
## Two continuous rendered night sequences in Main/.NET. Readback, JPEG encoding
## and the temporary 30 FPS recording cap make this visual evidence, not a benchmark.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const COSMETICS := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
var world
var folder := ""
var fingerprint: Dictionary = {}
var sequences: Array[Dictionary] = []
var depth_captures: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0
var _finished := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("PARK_TEMPORAL ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Rendered Godot .NET and --no-save required"); quit(2); return
	create_timer(260).timeout.connect(func(): check(false,"finite capture deadline"); finish(3))
	seed(100726)
	root.size = Vector2i(1280,720)
	folder = FIXTURE.output_dir("amusement-park-temporal")
	if not check(not folder.is_empty(),"unique evidence directory"): finish(); return
	fingerprint = _source_fingerprint()
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	snapshot.world.time = .90
	snapshot.world.weather = 0
	var path := FIXTURE.write_fixture(folder,"save.json",snapshot)
	if not check(not path.is_empty(),"isolated valid checkpoint"): finish(); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	if not check(world.production.store.path==path and not world.production.save_invalid,"Main uses only the isolated checkpoint"): finish(); return
	if world.session.modal: world.session.close_menu()
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if not check(world.dispatch.router._native!=null,"compiled C# routing remains active"): finish(); return
	world.session.weather.time_of_day = .90
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather._update()
	var park = world.session.amusement_park
	var at := LAYOUT.ORIGIN+Vector3(20,.10,15)
	world.production.region.set_focus(at)
	world.production.region.prepare_collision_at(at)
	world.player.teleport(at)
	world.camera.initialized = false
	park._update_residency()
	await create_timer(3).timeout
	if not check(is_instance_valid(park.site),"park admitted into the night scene"): finish(); return
	await capture_coaster_descent()
	world.player.teleport(at)
	world.camera.initialized = false
	await create_timer(.5).timeout
	await record("park",false)
	# Walk the clear central aisle into the real compact transfer marker.
	if not check(await walk(LAYOUT.ORIGIN+Vector3(20,.08,15)),"walk back to house promenade"): finish(); return
	if not check(await walk(LAYOUT.HAUNTED_ENTRY),"walk up to Umbra"): finish(); return
	var accepted: bool = await world.session.interact()
	var transition_deadline := Time.get_ticks_msec()+15000
	while world.session.is_transition_blocked() and Time.get_ticks_msec()<transition_deadline: await physics_frame
	if not check(accepted and world.session.state.place_id==LAYOUT.HAUNTED_ID,"live interaction enters Umbra"): finish(); return
	await create_timer(1).timeout
	if not check(park.house_view and root.get_camera_3d()==park.view,"production first-person house view active"): finish(); return
	park.yaw = 0
	park.pitch = 0
	await create_timer(.15).timeout
	check(park.view.is_position_behind(world.session.room.exit_position) and not world.session.marker.visible,"house exit marker stays hidden behind first-person camera")
	park.yaw = PI
	park.pitch = -.35
	await create_timer(.15).timeout
	var expected_marker: Vector2 = park.view.unproject_position(world.session.room.exit_position+Vector3.UP*.06)
	check(not park.view.is_position_behind(world.session.room.exit_position) and world.session.marker.visible and world.session.marker.position.distance_to(expected_marker)<2.0,"looking at door projects marker through current first-person camera")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("house-exit-door.png"))==OK,"closed exit door and correctly projected marker captured")
	park.yaw = 0
	park.pitch = 0
	await create_timer(.15).timeout
	await record("house",true)
	await check_house_pause()
	await capture_house_depth()
	if not check(await walk(world.session.room.exit_position),"walk to same interior exit"): finish(); return
	check(await world.session.interact() and world.session.state.place_id.is_empty(),"exit restores fairground")
	await create_timer(.5).timeout
	check(root.get_camera_3d()==world.camera and world.player.visual.visible,"camera and visible actor restored after recording")
	await cosmetic_portrait()
	finish()

func capture_coaster_descent() -> void:
	var park = world.session.amusement_park
	var peak_distance := 0.0
	var peak_height := -INF
	var distance := 0.0
	while distance<park.site.coaster_length():
		var pose: Transform3D = park.site.sample_coaster(distance)
		if pose.origin.y>peak_height:
			peak_height = pose.origin.y
			peak_distance = distance
		distance += .5
	world.player.teleport(park.site.boarding_position())
	await physics_frame
	world.session.state.economy.grant_reward("park_capture_ticket",5)
	if not check(park.start_ride(),"production ride admitted for descent framing"): return
	while park.ride_phase == "boarding": await physics_frame
	park.ride_distance = peak_distance+5.0
	park.pitch = -.5
	park._tick_ride(0.0)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("coaster-descent.png"))==OK,"gameplay descent camera captures distant terrain and city")
	park.leave()
	check(not park.active and root.get_camera_3d()==world.camera,"directed ride photograph restores gameplay camera")

func check_house_pause() -> void:
	var park = world.session.amusement_park
	var old_clock: float = park.clock
	var old_ghost: Transform3D = world.session.room.model.puppet.transform
	var old_camera: Transform3D = park.view.global_transform
	var previous_pause := paused
	paused = true
	await create_timer(.3,true).timeout
	check(is_equal_approx(park.clock,old_clock),"real park runtime clock remains frozen during tree pause")
	check(world.session.room.model.puppet.transform==old_ghost,"mechanical ghost remains frozen during tree pause")
	check(park.view.global_transform==old_camera,"house camera remains frozen during tree pause")
	paused = previous_pause

func capture_house_depth() -> void:
	# Paired rendered controls use the real props and ordinary depth test. Hiding
	# only the target for the control proves whether its pixels reach the camera;
	# the authored wall/stage/furniture and all lights remain unchanged.
	var park = world.session.amusement_park
	var room = world.session.room
	var ghost: Node3D = room.model.puppet
	var secret: Node3D = park.rewards.pickups.get("ghost_mask")
	if not check(is_instance_valid(ghost) and is_instance_valid(secret),"real ghost and uncollected secret available for depth controls"): return
	var previous_pause := paused
	paused = true
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 72
	camera.near = .05
	camera.far = 45
	camera.environment = park.view.environment
	camera.make_current()
	await depth_pair(camera,ghost,"ghost-visible",room.to_global(Vector3(0,1.65,4.4)),ghost.global_position+Vector3.UP*.55,true)
	await depth_pair(camera,ghost,"ghost-behind-wall",room.to_global(Vector3(-6.4,1.65,-1.8)),ghost.global_position+Vector3.UP*.55,false)
	await depth_pair(camera,secret,"secret-visible",room.to_global(Vector3(-6.4,1.65,-3.2)),secret.global_position,true)
	await depth_pair(camera,secret,"secret-behind-wall",room.to_global(Vector3(0,1.65,5.4)),secret.global_position,false)
	park.view.make_current()
	camera.queue_free()
	paused = previous_pause

func depth_pair(camera: Camera3D, target: Node3D, id: String, origin: Vector3, look: Vector3, should_be_visible: bool) -> void:
	camera.global_position = origin
	camera.look_at(look)
	var was_visible := target.visible
	target.show()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var with_target := root.get_texture().get_image()
	check(with_target.save_png(folder.path_join("depth-"+id+".png"))==OK,id+" rendered scene saved")
	target.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var without_target := root.get_texture().get_image()
	check(without_target.save_png(folder.path_join("depth-"+id+"-control.png"))==OK,id+" hidden-target control saved")
	target.visible = was_visible
	var region := Rect2i(with_target.get_width()*2/5,with_target.get_height()*2/5,with_target.get_width()/5,with_target.get_height()/5)
	var changed := 0
	var maximum := 0.0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var a := with_target.get_pixel(x,y)
			var b := without_target.get_pixel(x,y)
			var difference := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			maximum = maxf(maximum,difference)
			if difference>8.0/255.0: changed += 1
	check(changed>=64 if should_be_visible else changed<=8,id+" target reaches pixels" if should_be_visible else id+" solid blocks target pixels")
	depth_captures.append({"id":id,"expected_visible":should_be_visible,"target":str(target.get_path()),"camera":var_to_str(origin),
		"look":var_to_str(look),"region":var_to_str(region),"changed_pixels_above_8_of_255":changed,"maximum_channel_difference":maximum,
		"scene":"depth-"+id+".png","target_hidden_control":"depth-"+id+"-control.png"})

func cosmetic_portrait() -> void:
	# The separate integrated journey proved real exploration and UI equipping.
	# These direct fixture grants isolate presentation and never touch a user save.
	for id in ["lume_jacket","star_glasses","fox_mask"]:
		if not COSMETICS.data(world.session.state.world_state).found.has(id):
			check(COSMETICS.collect(world.session.state.world_state,world.session.state.economy,id),"portrait fixture unlock "+id)
		check(COSMETICS.equip(world.session.state.world_state,world.session.state.economy,id),"portrait fixture equips "+id)
	world.session.apply_outfit()
	world.player.automatic_direction = Vector3.ZERO
	world.player.visual.rotation.y = 0
	var old_camera := root.get_camera_3d()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 48
	camera.near = .05
	camera.far = 150
	camera.global_position = world.player.global_position+Vector3(0,1.65,-3)
	camera.look_at(world.player.global_position+Vector3.UP*1.25)
	camera.make_current()
	await create_timer(.25).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join("cosmetics-front.png"))==OK,"front portrait captures equipped jacket glasses and mask")
	old_camera.make_current()
	camera.queue_free()

func record(id: String, indoors: bool) -> void:
	var directory := folder.path_join(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var old_limit := Engine.max_fps
	var old_speed: float = world.player.speed
	Engine.max_fps = 30
	world.player.speed = .16 if indoors else 2.4
	var started := Time.get_ticks_usec()
	var previous_drawn := -1
	var missed := 0
	var writes_ok := true
	var frames: Array[Dictionary] = []
	var light_samples: Array[Dictionary] = []
	var sampled_second := -1
	var beginning: Vector3 = world.player.global_position
	while Time.get_ticks_usec()-started<30000000:
		var seconds := float(Time.get_ticks_usec()-started)/1000000.0
		var direction := Vector3.ZERO
		if indoors:
			if seconds>=10 and seconds<15: direction = Vector3.FORWARD
			elif seconds>=15 and seconds<20: direction = Vector3.BACK
		else:
			if seconds>=5 and seconds<15: direction = Vector3.LEFT
			elif seconds>=15 and seconds<25: direction = Vector3.RIGHT
		world.player.automatic_direction = direction
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var drawn := Engine.get_frames_drawn()
		if previous_drawn>=0: missed += maxi(0,drawn-previous_drawn-1)
		previous_drawn = drawn
		var frame := root.get_texture().get_image()
		if frames.is_empty(): writes_ok = frame.save_png(folder.path_join(id+"-start.png"))==OK and writes_ok
		frame.resize(480,270,Image.INTERPOLATE_LANCZOS)
		var filename := "%05d.jpg"%frames.size()
		var written := frame.save_jpg(directory.path_join(filename),.90)==OK
		writes_ok = writes_ok and written
		var camera := root.get_camera_3d()
		frames.append({"index":frames.size(),"render_frame":drawn,"elapsed_us":now-started,
			"file":filename,"saved":written,"camera_origin":var_to_str(camera.global_position),
			"camera_basis":var_to_str(camera.global_basis),"actor":var_to_str(world.player.global_position),"moving":direction!=Vector3.ZERO})
		if int(seconds)!=sampled_second:
			sampled_second = int(seconds)
			var owner: Node = world.session.room.model if indoors else world.session.amusement_park.site
			var lights := []
			for light in owner.find_children("*","Light3D",true,false):
				lights.append({"node":str(light.get_path()),"visible":light.is_visible_in_tree(),"energy":light.light_energy,"position":var_to_str(light.global_position)})
			light_samples.append({"second":seconds,"lights":lights})
	world.player.automatic_direction = Vector3.ZERO
	world.player.speed = old_speed
	Engine.max_fps = old_limit
	await RenderingServer.frame_post_draw
	writes_ok = root.get_texture().get_image().save_png(folder.path_join(id+"-end.png"))==OK and writes_ok
	var duration: float = float(frames[-1].elapsed_us)/1000000.0 if not frames.is_empty() else 0.0
	check(writes_ok,id+" every frame written")
	check(duration>=29.9 and frames.size()>100,id+" continuous thirty-second sequence")
	check(missed==0,id+" no gaps in rendered-frame counters")
	check(world.session.position_clear(world.player.global_position),id+" movement remains physically admitted")
	sequences.append({"id":id,"duration":duration,"frames":frames,"light_samples":light_samples,"missed_render_frames":missed,
		"writes_ok":writes_ok,"start_actor":var_to_str(beginning),"end_actor":var_to_str(world.player.global_position),
		"capture_size":"480x270","note":"Stationary/moving/stationary, every rendered frame. Encoding/readback cost is excluded from performance conclusions."})

func walk(point: Vector3) -> bool:
	world.player.speed = 2.4
	var deadline := Time.get_ticks_msec()+16000
	while Time.get_ticks_msec()<deadline:
		var offset: Vector3 = point-world.player.global_position
		offset.y = 0
		if offset.length()<.22: break
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var left: Vector3 = point-world.player.global_position
	left.y = 0
	return left.length()<.35

func _source_fingerprint() -> Dictionary:
	var result := FIXTURE.source_fingerprint()
	for directory in ["res://world/places/amusement_park","res://runtime/amusement_park","res://activities/amusement_park"]:
		for filename in DirAccess.get_files_at(directory):
			if filename.ends_with(".gd"):
				var path: String = directory.path_join(filename)
				result[path] = FileAccess.get_sha256(path)
	return result

func finish(code := -1) -> void:
	if _finished: return
	_finished = true
	var final_source := _source_fingerprint()
	var report := {"checks":checks,"failures":failures,"sequences":sequences,"depth_captures":depth_captures,"source_stable":fingerprint==final_source,
		"source_before":fingerprint,"source_after":final_source,"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),
		"notes":"Real Main, isolated checkpoint, dry night. No first-person actor occlusion claim: Dante is hidden intentionally and Umbra has no NPC residents. Review captured architecture and steady light sources separately from physical checks. This capture is not an FPS benchmark."}
	if not folder.is_empty():
		var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(report,"\t"))
	print("PARK_TEMPORAL_RESULT ",folder," checks=",checks," failures=",failures)
	quit(code if code>=0 else 0 if failures.is_empty() else 1)
