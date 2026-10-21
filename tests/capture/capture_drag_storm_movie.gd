extends "res://tests/capture/capture_drag_start_camera.gd"
## Real gameplay/movie capture at --fixed-fps 30. Capture-only weather/startup
## overrides live in memory; no production source or save is edited.
var movie_start := 0
var movie_end := 0
var recording := false
var timeline: Array[Dictionary] = []
var movie_clock := 0.0
var next_probe := 0.0
var strike_marks: Array[Dictionary] = []
var requested_output := ""
var original_weather_hash := ""
var original_world_hash := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--storm-out="): requested_output = argument.trim_prefix("--storm-out=")
	# Load before Main creates Weather. Keep all production particles, audio,
	# flash envelopes and sky code; override only regional rain suppression.
	var weather_script := load("res://runtime/Weather.gd") as GDScript
	var original := weather_script.source_code
	original_weather_hash = original.sha256_text()
	if original.count("REGIONAL_ATMOSPHERE.desert_weight(focus)") != 2 or original.count("REGIONAL_ATMOSPHERE.desert_weight(point)") != 1:
		push_error("Storm preview: regional rain gate changed; inspect fixture")
		quit(2)
		return
	var coastal_call := "coastal_look.apply(controller.environment.environment,controller.sun,daylight,local_clouds,coastal_wetness,rain_exposure,inside,time_of_day)"
	if original.count(coastal_call) != 1: push_error("Inspect storm preview sky ownership"); quit(2); return
	# A coastal reflection sky must not take ownership from the native race sky
	# merely because this fixture bypasses the desert's rain suppression.
	weather_script.source_code = original.replace("REGIONAL_ATMOSPHERE.desert_weight(focus)","0.0").replace("REGIONAL_ATMOSPHERE.desert_weight(point)","0.0").replace(coastal_call,coastal_call.replace(",rain_exposure,",",0.0,"))
	if weather_script.reload() != OK:
		push_error("Storm preview: process-local weather compilation failed")
		quit(2)
		return
	# Preparing cached models for unvisited Harbor/Mountain took over five
	# minutes in MovieWriter. Their data and the entire active desert remain;
	# only offscreen model-cache warm-up is omitted in this isolated capture.
	var production_script := load("res://runtime/ProductionWorld.gd") as GDScript
	var production_source := production_script.source_code
	original_world_hash = production_source.sha256_text()
	for variable in ["neighbour","detached"]:
		var call := 'await preload("res://runtime/RetainedRegionPreparation.gd").run(%s)'%variable
		if production_source.count(call) != 1: push_error("Inspect offscreen capture warm-up fixture"); quit(2); return
		production_source = production_source.replace(call,"await get_tree().process_frame")
	production_script.source_code = production_source
	if production_script.reload() != OK: push_error("Capture startup compilation failed"); quit(2); return
	super._initialize()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output = FIXTURE.output_dir("drag-storm-checkpoint")
	root.content_scale_size = Vector2i(1920,1080)
	root.size = Vector2i(1920,1080)
	var at: Vector3 = LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary = FIXTURE.full_snapshot(at,true)
	data.region_id = "desert"
	data.world.pedestrian = {"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	var ready_deadline := Time.get_ticks_msec()+240000
	while Time.get_ticks_msec()<ready_deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: push_error("Capture session not ready"); quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: quit(1); return
	world.gameplay.god_mode = true
	var race = world.session.desert.drag
	race.open_meet.enabled = false
	var car = world.production.spawn_vehicle("desert_mirage",race.staging_point+Vector3(0,.1,-6),-PI*.5)
	if not is_instance_valid(car): quit(1); return
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for i in 4: await physics_frame
	if not world.driving.interact(): quit(1); return
	for i in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	await review(race)
	world.free()
	quit()

func _process(delta: float) -> bool:
	if not recording: return false
	movie_clock += delta
	if movie_clock < next_probe: return false
	next_probe += .1
	var race = world.session.desert.drag
	var region = world.production.regions.desert
	var camera := root.get_camera_3d()
	var weather = world.session.weather
	timeline.append({"seconds":movie_clock,"movie_frame":Engine.get_frames_drawn(),"phase":race.phase,"elapsed":race.elapsed,"camera":str(camera.global_position),"car":str(race.player_car.global_position),"chunks":region.chunks.size(),"pending_chunks":region.pending.size(),"pending_drag_view":region.drag_view_pending.size(),"build_jobs":region.build_jobs.size(),"rain":weather.rain_level,"flashes":weather.storm.flashes,"native_race_sky":weather.controller.environment.environment.sky==weather.drag_sky.sky})
	return false

func review(race) -> void:
	if not requested_output.is_empty(): output = requested_output
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK: push_error("Storm output unavailable"); quit(2); return
	root.mode = Window.MODE_WINDOWED
	root.content_scale_size = Vector2i(1920,1080)
	root.size = Vector2i(1920,1080)
	var settings := root.get_node("V2Settings")
	settings.mute_unfocused = false
	settings.show_fps = false
	settings.text_language = "pt_BR"
	if is_instance_valid(settings._fps_layer): settings._fps_layer.hide()
	AudioServer.set_bus_mute(0,false)
	var weather = world.session.weather
	weather.weather_state = 2
	weather.weather_locked = true
	weather.time_scale = 0.0
	weather.weather_timer = 10000.0
	weather.time_of_day = .78
	weather._update()
	weather.set_process(true)
	Engine.max_fps = 0
	await create_timer(6.0).timeout
	if weather.rain_strength_at(race.start_point)<.95:
		push_error("Storm preview did not expose the real rain emitter")
		quit(2)
		return
	if weather.controller.environment.environment.sky != weather.drag_sky.sky:
		push_error("Storm preview sky is not the native race sky")
		quit(2)
		return
	weather.storm._rng.seed = 10202026
	weather.storm.lightning_timer = 1000.0
	movie_start = Engine.get_frames_drawn()
	movie_clock = 0.0
	recording = true
	print("DRAG_STORM_MOVIE_START first_frame=",movie_start)
	if not race.perform("start"): push_error(race.start_block_reason()); quit(1); return
	var next_strike := 0
	var strike_times := [5.5,12.0,20.0]
	while movie_clock < 32.0:
		if race.active:
			race._throttle_override = .54 if race.phase=="staging" else 1.0
			if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		if next_strike<strike_times.size() and movie_clock>=float(strike_times[next_strike]):
			if weather.storm.trigger_lightning():
				strike_marks.append({"seconds":movie_clock,"movie_frame":Engine.get_frames_drawn(),"thunder_delay":weather.storm.thunder_delay})
				next_strike += 1
		await process_frame
	recording = false
	movie_end = Engine.get_frames_drawn()
	var report := {"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(root.get_texture().get_size()),"movie_fps":30,"first_frame":movie_start,"last_frame":movie_end,"seconds":movie_clock,"strikes":strike_marks,"thunder_count":weather.storm.thunder_count,"weather_source_hash":original_weather_hash,"world_source_hash":original_world_hash,"fixture":"Process-local desert rain gate bypass; existing production storm, particles and audio. Clock .78. Normal desert streaming retained; no route preloading. Offscreen model-cache warm-up for unvisited regions omitted during capture startup.","performance":"Offline fixed-step movie with render readback; not a real-time FPS measurement or approval.","result":race.last_result,"timeline":timeline}
	FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DRAG_STORM_MOVIE ",ProjectSettings.globalize_path(output)," first_frame=",movie_start," last_frame=",movie_end," strikes=",strike_marks.size())
	if race.active: race.cancel_attempt()
