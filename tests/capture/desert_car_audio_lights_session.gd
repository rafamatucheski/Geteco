extends SceneTree
## Rendered Main, normal driving camera, real boarding and engine-bus recording.
## --no-save is mandatory. Frame capture is visual evidence, never a benchmark.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var car
var output := ""
var phase := ""
var samples: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0
var recording := false
var started := 0
var previous_frame := -1
var skipped := 0
var meter_bus := -1
var recorder: AudioEffectRecord
var audio_peak := -100.0

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("AV session timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DESERT_AV ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	output = FIXTURE.output_dir("desert-audio-lights")
	root.size = Vector2i(1280,720)
	Engine.max_fps = 30
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	for i in 3600:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main session ready")
	if not failures.is_empty(): finish(); return
	check(world.session.controller.no_save, "user saves protected")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null, "C# route backend active")
	var intro: Dictionary = world.session.state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.completed_missions = [preload("res://data/GarageSequence.gd").ID]
	check(world.session.state.intro.restore_snapshot(intro), "intro fixture")
	var fixture: Dictionary = FIXTURE.full_snapshot(world.player.global_position,true,true)
	check(world.session.state.campaign.restore_snapshot(fixture.campaign), "campaign unlock fixture")
	var at: Vector3 = preload("res://world/desert/DesertLayout.gd").drag_start_point() + Vector3(12,.1,0)
	# Keep Dante outside the spawn hull: production correctly rejects overlap.
	check(world.production.travel("desert",at+Vector3(0,0,8)), "travel to desert")
	for i in 900:
		await physics_frame
		if not world.production.travel_busy and world.session.ready_for_play: break
	await frames(120)
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 3600
	world.session.weather.time_of_day = .9
	world.session.weather._update()
	# Keep the normal world, population, weather and gameplay camera running.
	AudioServer.add_bus()
	meter_bus = AudioServer.bus_count-1
	AudioServer.set_bus_name(meter_bus,"DesertAVCapture")
	AudioServer.set_bus_send(meter_bus,"SFX")
	recorder = AudioEffectRecord.new()
	AudioServer.add_bus_effect(meter_bus,recorder)
	recorder.set_recording_active(true)
	RenderingServer.frame_post_draw.connect(capture)
	started = Time.get_ticks_usec()
	recording = true
	for id in ["desert_faisca", "desert_mirage_gt"]:
		phase = id+"_boarding"
		world.production.region.prepare_collision_at(at)
		await physics_frame
		car = world.production.spawn_vehicle(id,at,-PI*.5)
		check(is_instance_valid(car), id+": clear physical spawn")
		if not is_instance_valid(car): finish(); return
		world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
		await frames(4)
		check(world.driving.interact(), id+": ordinary boarding starts")
		for i in 600:
			await physics_frame
			if world.driving.occupied and world.driving.car == car and car.controlled and not car.input_locked and not world.driving.is_body_transition_active(): break
		check(car.controlled and not car.input_locked, id+": boarding completes")
		if not failures.is_empty(): finish(); return
		var sound: Node = car.get_node("DesertCarAudio")
		for voice in sound._layers: voice.bus = "DesertAVCapture"
		audio_peak = -100
		phase = id+"_idle_night"
		var equipment: Node = car.ensure_equipment(world)
		if not equipment.headlights_on: equipment.toggle_headlights()
		await create_timer(6).timeout
		check(audio_peak > -40, id+": engine reaches real audio bus (peak "+str(audio_peak)+" dB)")
		check(equipment.lamps.size() == 2 and equipment.lamps.all(func(e): return e.lamp.visible), id+": two actual headlights in Main")
		phase = id+"_drive_night"
		Input.action_press("accelerate",.5)
		await create_timer(4).timeout
		Input.action_release("accelerate")
		check(absf(car.speed) > 1, id+": real player drivetrain moves")
		phase = id+"_braking"
		Input.action_press("handbrake")
		await create_timer(4).timeout
		Input.action_release("handbrake")
		phase = id+"_lights_off"
		equipment.toggle_headlights()
		await create_timer(3).timeout
		phase = id+"_lights_on"
		equipment.toggle_headlights()
		await create_timer(5).timeout
		phase = id+"_exit"
		check(world.driving.interact(), id+": ordinary exit starts")
		for i in 600:
			await physics_frame
			if not world.driving.occupied and not world.driving.is_body_transition_active(): break
		await create_timer(4).timeout
		check(not world.driving.occupied and sound._layers.all(func(p): return not p.playing), id+": exit stops engine")
		car.queue_free()
		car = null
		await frames(2)
	finish()

func capture() -> void:
	if not recording: return
	if samples.size() >= 3200:
		recording = false
		check(false,"capture frame limit reached")
		finish.call_deferred()
		return
	var drawn := Engine.get_frames_drawn()
	if drawn == previous_frame: return
	if previous_frame >= 0: skipped += maxi(0,drawn-previous_frame-1)
	previous_frame = drawn
	var frame := root.get_texture().get_image()
	var file := "%05d.jpg" % samples.size()
	frame.save_jpg(output.path_join(file),.85)
	var peak := AudioServer.get_bus_peak_volume_left_db(meter_bus,0)
	audio_peak = maxf(audio_peak,peak)
	var beams := 0
	if is_instance_valid(car) and is_instance_valid(car.equipment):
		for mount in car.equipment.lamps:
			if mount.lamp.is_visible_in_tree(): beams += 1
	samples.append({"file":file,"seconds":(Time.get_ticks_usec()-started)/1000000.0,"phase":phase,"beams":beams,"engine_peak_db":peak,"speed":float(car.speed) if is_instance_valid(car) else 0.0})

func finish() -> void:
	recording = false
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	if recorder != null:
		recorder.set_recording_active(false)
		recorder.get_recording().save_to_wav(output.path_join("engine.wav"))
	if not output.is_empty():
		FileAccess.open(output.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"purpose":"functional and temporal evidence; not performance","skipped_rendered_frames":skipped,"samples":samples},"\t"))
	print("DESERT_AV output=",output," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
