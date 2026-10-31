extends "res://tests/test_desert_drag_runtime.gd"
## Revisão visual temporal no Main real, com o enquadramento de corrida da produção.
## A varredura do relógio da fixture é diagnóstico; a cadência de captura não é benchmark de FPS.
func begin_temporal(race) -> bool:
	var previous := root.get_camera_3d()
	var preview := Camera3D.new()
	preview.name="DragSkyReviewCamera"
	preview.fov=57
	preview.far=2200
	world.add_child(preview)
	var framing: Dictionary=race.camera_frame(race.grid(0).origin,race.grid(1).origin)
	preview.global_position=framing.position
	preview.look_at(framing.target,Vector3.UP)
	preview.make_current()
	temporal=load("res://tests/capture/DesertDragTemporalCapture.gd").new()
	root.add_child(temporal)
	_weather_was_processing=world.session.weather.is_processing()
	world.session.weather.set_process(false)
	world.session.weather.time_of_day=.5
	world.session.weather._update()
	await frames(15)
	var requested := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--temporal-out="): requested=arg.trim_prefix("--temporal-out=")
	if not temporal.begin(world,race,requested):
		preview.queue_free()
		if is_instance_valid(previous): previous.make_current()
		world.session.weather.set_process(_weather_was_processing)
		return false
	temporal._report.clock_control="Fixture fixes noon/night and sweeps 0.70–0.90 over18seconds through production Weather; original world time is never saved."
	temporal._report.coverage="Main .NET: production side-camera framing day/sunset/moonrise/night for30seconds, then physical two-car race and cleanup."
	temporal.segment="day_sky"
	await temporal_hold(6.0,.5,.5)
	temporal.segment="sunset_moonrise"
	await temporal_hold(18.0,.70,.90)
	temporal.segment="night_sky"
	await temporal_hold(6.0,.90,.90)
	preview.queue_free()
	if is_instance_valid(previous): previous.make_current()
	temporal.segment="drag"
	return temporal.recording
