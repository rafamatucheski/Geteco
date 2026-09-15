extends "res://tests/measure_game_frame_stability.gd"
## Production world, fixed clock and reproducible camera route. Not a driving test.
var _route_actor: Node2D
var _route_camera: Camera2D
var _route_curve: Curve2D
var _route_origin := Vector2.ZERO
var _route_start := 0.0
var _route_end := 0.0
var _route_elapsed := 0.0
var _moving := false

func _process(delta: float) -> bool:
	if _moving:
		_route_elapsed += delta
		var distance := lerpf(_route_start, _route_end, clampf(_route_elapsed / 30.0, 0, 1))
		_route_actor.global_position = _route_origin + _route_curve.sample_baked(distance, true)
		_route_actor.reset_physics_interpolation()
		_route_camera.global_position = _route_actor.global_position
	return false

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var output := "D:/geteco/artifacts/regional-atmosphere/after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out_dir="): output = arg.trim_prefix("out_dir=")
	DirAccess.make_dir_recursive_absolute(output.path_join("saves"))
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", output.path_join("saves") + "/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	seed(14092026)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	if not OS.get_cmdline_user_args().has("--normal-cap"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	for flag in ["harbor_arrival_seen", "harbor_arrival_call_complete", "harbor_maciota_met", "harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag), true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while (not world.gameplay_ready or not world.world_build_ready) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not world.gameplay_ready or not world.world_build_ready or paused:
		push_error("Atmosphere benchmark: gameplay did not become ready")
		quit(1)
		return
	_scenario_world = world
	_scenario_hour = 0.50
	world.weather.weather_timer = 1000000.0
	world.weather.set_weather(0)
	_hold_scenario_clock()
	_route_actor = world.get_node("Player")
	_route_actor.set_physics_process(false)
	_route_actor.set_process(false)
	_route_camera = Camera2D.new()
	_route_camera.zoom = Vector2.ONE * 1.8
	_route_camera.set_meta("mountain_fixed_framing", true)
	world.add_child(_route_camera)
	_route_camera.make_current()
	_place(Vector2(3100, 1750))
	await _sample(output, "harbor-warmup", 10.0, _route_actor)
	await _sample(output, "harbor-day", 30.0, _route_actor)
	await _capture(output, "harbor-day")
	var stream: Node = world.get_node("ContinuousWorld")
	stream.ensure_mountain()
	deadline = Time.get_ticks_msec() + 120000
	while not stream.ready_for_crossing and Time.get_ticks_msec() < deadline: await process_frame
	if not stream.ready_for_crossing:
		push_error("Atmosphere benchmark: mountain did not become ready")
		quit(1)
		return
	stream.mountain.storm_manager.dynamic_weather = false
	stream.mountain.storm_manager.weather_clock = 0
	stream.mountain.storm_manager.advance_weather(0)
	_route_curve = Curve2D.new()
	_route_curve.add_point(Vector2(6800, -4560))
	_route_curve.add_point(Vector2(9100, -4560))
	_route_start = 0
	_route_end = _route_curve.get_baked_length()
	_place(_route_curve.sample_baked(0))
	await _sample(output, "bridge-warmup", 10.0, _route_actor)
	_route_elapsed = 0
	_moving = true
	await _sample(output, "bridge-first-crossing", 30.0, _route_actor)
	_moving = false
	await _capture(output, "mountain-day")
	_place(_route_curve.sample_baked(0))
	await _sample(output, "bridge-return-warmup", 5.0, _route_actor)
	_route_elapsed = 0
	_moving = true
	await _sample(output, "bridge-repeat", 30.0, _route_actor)
	_moving = false
	_scenario_hour = 0.90
	_hold_scenario_clock()
	stream.mountain.storm_manager.weather_clock = 120
	stream.mountain.storm_manager.advance_weather(0)
	_place(stream.mountain.to_global(Vector2(6650, 150)))
	await _sample(output, "snow-night-warmup", 10.0, _route_actor)
	await _sample(output, "snow-night", 30.0, _route_actor)
	await _capture(output, "snow-night")
	quit(0)

func _place(point: Vector2) -> void:
	_route_actor.global_position = point
	_route_actor.reset_physics_interpolation()
	_route_camera.global_position = point
	_route_camera.reset_smoothing()

func _capture(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
