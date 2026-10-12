extends SceneTree
## Rendered production driving, isolated save, separate engine/tire recordings.
## --no-save --tag=before|after; 30 seconds per surface after warm-up.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var world
var car
var output := ""
var phase := ""
var samples: Array[Dictionary] = []
var failures: Array[String] = []
var previous := 0
var engine_bus := -1
var tire_bus := -1
var recorders: Array[AudioEffectRecord] = []

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("COUPE timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("COUPE ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func bus(label: String) -> int:
	AudioServer.add_bus()
	var index := AudioServer.bus_count-1
	AudioServer.set_bus_name(index,label)
	AudioServer.set_bus_send(index,"SFX")
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(index,recorder)
	recorders.append(recorder)
	recorder.set_recording_active(true)
	return index

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var tag := "review"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	output = FIXTURE.output_dir("coupe-"+tag)
	root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	seed(20261012)
	var at := Vector3(-880,.1,-1320)
	var spawn := at+Vector3(0,0,5)
	var snapshot := FIXTURE.full_snapshot(spawn,true)
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert","position":[spawn.x,spawn.y,spawn.z]}
	snapshot.world.time = .45
	var save_path := FIXTURE.write_fixture(output,"checkpoint.json",snapshot)
	check(not save_path.is_empty(),"isolated checkpoint")
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",save_path)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	check(world.session != null and world.session.ready_for_play,"production ready")
	check(world.production.store.path == save_path and world.session.controller.no_save,"personal saves protected")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"C# backend active")
	if world.session.modal: world.session.close_menu()
	await create_timer(3).timeout
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	engine_bus = bus("CoupeEngineCapture")
	tire_bus = bus("CoupeTireCapture")
	world.production.region.prepare_collision_at(at)
	await physics_frame
	car = world.production.spawn_vehicle("sport_coupe",at,-PI*.5)
	check(is_instance_valid(car),"coupe spawn")
	if not is_instance_valid(car): finish(); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.30+Vector3.UP*.08)
	await create_timer(.3).timeout
	check(world.driving.interact(),"ordinary boarding starts")
	for i in 600:
		await physics_frame
		if car.controlled and not world.driving.is_body_transition_active(): break
	check(car.controlled and world.player.seated,"boarding completes seated")
	if not failures.is_empty(): finish(); return
	var sound = world.production.world_audio
	for voice in sound.layers: voice.bus = "CoupeEngineCapture"
	await create_timer(2).timeout
	print("COUPE SPEC ",INTERIOR.spec(car)," HEAD ",head_height()," AUDIO ",sound.family," bands=",sound.layers.filter(func(p): return p.playing).size())
	RenderingServer.frame_post_draw.connect(sample)
	phase = "idle"
	await create_timer(3).timeout
	await screenshot("idle")
	for surface in ["asphalt","sand"]:
		phase = ""
		# Teleport only to the start of each measured straight; actual input drives the route.
		var point := at+Vector3(0,0,-25 if surface == "sand" else 0)
		world.production.region.prepare_collision_at(point)
		car.place(point,-PI*.5)
		car.handling.drive.reset()
		Input.action_press("accelerate",.32)
		await create_timer(3).timeout
		var mixer = car.effects.tire_effects.road_mixer
		check(is_instance_valid(mixer),surface+": tire mixer exists")
		if is_instance_valid(mixer):
			for voice in mixer.voices.values(): voice.bus = "CoupeTireCapture"
		previous = 0
		phase = surface
		await create_timer(30).timeout
		phase = ""
		Input.action_release("accelerate")
		await screenshot(surface)
		Input.action_press("handbrake")
		await create_timer(4).timeout
		Input.action_release("handbrake")
		print("COUPE SURFACE ",surface," position=",car.global_position," contacts=",car.effects.tire_effects.last_contacts)
	check(samples.any(func(s): return s.engine_db > -40),"engine reaches output bus")
	check(world.driving.leave(),"normal exit starts")
	for i in 600:
		await physics_frame
		if not world.driving.occupied and not world.driving.is_body_transition_active(): break
	check(not world.player.seated and world.player.is_physics_processing(),"walking control restored")
	finish()

func head_height() -> float:
	var actor = world.player
	return car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones.Head).origin)).y

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func sample() -> void:
	if phase.is_empty(): return
	if phase in ["asphalt","sand"]: Input.action_press("accelerate",.32)
	var now := Time.get_ticks_usec()
	var contacts: Array = car.effects.tire_effects.last_contacts
	samples.append({"phase":phase,"ms":0.0 if previous == 0 else (now-previous)/1000.0,"engine_db":AudioServer.get_bus_peak_volume_left_db(engine_bus,0),"tires_db":AudioServer.get_bus_peak_volume_left_db(tire_bus,0),"speed":car.speed,"rpm":car.handling.drive.rpm,"head_y":head_height(),"surface":contacts.map(func(c): return c.get("kind","air"))})
	previous = now

func finish() -> void:
	phase = ""
	for action in ["accelerate","brake","handbrake"]: Input.action_release(action)
	for i in recorders.size():
		recorders[i].set_recording_active(false)
		recorders[i].get_recording().save_to_wav(output.path_join("engine.wav" if i == 0 else "tires.wav"))
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":[root.size.x,root.size.y],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"failures":failures,"samples":samples}
	FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	print("COUPE output=",output," failures=",failures)
	quit(0 if failures.is_empty() else 1)
