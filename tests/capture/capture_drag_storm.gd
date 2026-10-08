extends "res://tests/test_desert_drag_runtime.gd"
## Real Main with production rain, existing storm clock/audio and side-camera framing.
func begin_temporal(race) -> bool:
	var weather = world.session.weather
	_weather_was_processing=weather.is_processing()
	weather.weather_timer=10000
	weather.time_of_day=.50
	weather.weather_state=2
	weather._update()
	var previous := root.get_camera_3d()
	var preview := Camera3D.new()
	preview.fov=57
	preview.far=2200
	preview.set_meta("drag_precipitation",true)
	world.add_child(preview)
	var framing: Dictionary=race.camera_frame(race.grid(0).origin,race.grid(1).origin)
	preview.global_position=framing.position
	preview.look_at(framing.target,Vector3.UP)
	preview.make_current()
	await frames(90)
	temporal=load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(temporal)
	var requested := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--temporal-out="): requested=arg.trim_prefix("--temporal-out=")
	if not temporal.begin(world,race,requested): return false
	temporal._report.clock_control="Fixed storm at noon and night; one forced production strike per static segment plus natural cadence in physical race."
	temporal._report.coverage="Main .NET: clouds, diagonal rain, distant lightning and thunder lifecycle, physical race and cleanup."
	if "--weather-only" in OS.get_cmdline_user_args():
		temporal._report.clock_control="Fixed heavy storm, noon then night, shared production lightning timer with two directed triggers."
		temporal._report.coverage="Main .NET:34seconds stationary production side-camera framing, final cloud visibility and drop size; daylight/night lightning and camera restoration."
	temporal._report.not_covered=["other regions","human audio review","FPS comparison"]
	temporal.segment="storm_day"
	await temporal_hold(5.0,.5,.5)
	check(weather.storm.trigger_lightning(),"day storm admits distant discharge")
	temporal.segment="storm_day_strike"
	await temporal_hold(5.0,.5,.5)
	temporal.segment="storm_night"
	await temporal_hold(4.0,.9,.9)
	check(weather.storm.trigger_lightning(),"night storm admits distant discharge")
	temporal.segment="storm_night_strike"
	await temporal_hold(5.0,.9,.9)
	check(weather.storm.thunder_count>=2,"both visible discharges deliver delayed thunder")
	check(weather.precipitation.transform_align==GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY,"production side-camera rain follows wind")
	if "--weather-only" in OS.get_cmdline_user_args():
		temporal.segment="storm_night_continuous"
		await temporal_hold(15.0,.9,.9)
	preview.queue_free()
	if is_instance_valid(previous): previous.make_current()
	if "--weather-only" in OS.get_cmdline_user_args():
		await frames(3)
		return false
	temporal.segment="drag"
	return temporal.recording

func finish() -> void:
	if is_instance_valid(world) and world.session!=null:
		var weather=world.session.weather
		weather.weather_state=0
		weather._update()
		weather._process(0.0)
		check(is_zero_approx(float(weather.drag_sky.material.get_shader_parameter("lightning_strength"))),"clear weather removes sky discharge")
		check(weather.precipitation.transform_align==GPUParticles3D.TRANSFORM_ALIGN_DISABLED,"exiting race restores normal rain orientation")
	super.finish()
