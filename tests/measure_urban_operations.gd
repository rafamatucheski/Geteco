extends "res://tests/measure.gd"
## Rendered, finite benchmark for the two Harbor locations changed by the
## V1 urban-operations migration. Functional validation lives in a separate
## headless test; this script measures the integrated Main scene only.

var site := "port"
var ablate_urban := false
const BENCHMARK_TIME := .32
const BENCHMARK_WEATHER := 0
const BENCHMARK_CAMERA_SIZE := 32.0

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
		elif arg.begins_with("--site="): site = arg.split("=")[1]
		elif arg == "--ablate-urban": ablate_urban = true
	if site not in ["port", "cemetery"]:
		push_error("Unknown urban benchmark site: " + site)
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for _frame in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.people.size() >= world.production.requested_population: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Native world failed to start")
		quit(1)
		return
	if not world.production.no_save:
		push_error("Urban benchmark requires --no-save")
		quit(2)
		return
	if world.people.size() != world.production.requested_population:
		push_error("Population did not settle: %d/%d" % [world.people.size(),world.production.requested_population])
		quit(1)
		return
	world.session.weather.time_of_day = BENCHMARK_TIME
	world.session.weather.weather_state = BENCHMARK_WEATHER
	world.session.state.world_state.time = BENCHMARK_TIME
	world.session.state.world_state.weather = BENCHMARK_WEATHER
	if ablate_urban:
		# Same integrated scene and population, with only this delivery disabled.
		# Used when an unrelated live Godot session makes an older wall-clock
		# baseline incomparable to the current measurement.
		world.session.urban_operations.port.process_mode = Node.PROCESS_MODE_DISABLED
		world.session.urban_operations.cemetery.process_mode = Node.PROCESS_MODE_DISABLED
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	for child in world.hud.get_children():
		if child.get_script() == preload("res://scripts/PauseInput.gd"): child.set_process_unhandled_input(false)
	world.player.controlled_automatically = true
	world.player.speed = 1.5
	world.camera.target_size = BENCHMARK_CAMERA_SIZE
	var center := Vector3(6380.0 / 16.0, .04, 3980.0 / 16.0) if site == "port" else Vector3(-650.0 / 16.0, .04, 1740.0 / 16.0)
	world.player.teleport(center + Vector3(-8, 0, -6))
	world.production.region.set_focus(center)
	route = PackedVector3Array([
		center + Vector3(-8, 0, -6), center + Vector3(8, 0, -6),
		center + Vector3(8, 0, 6), center + Vector3(-8, 0, 6),
	])
	started = Time.get_ticks_usec()
	previous = started

func finish() -> void:
	var summary := stats(samples)
	var report := {
		"label":label, "site":site, "scene":"Main.tscn / native Harbor",
		"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size), "population":world.people.size(),
		"requested_population":world.production.requested_population,
		"cars":world.production.vehicles.size(),
		"time_of_day_start":BENCHMARK_TIME, "weather_state":BENCHMARK_WEATHER,
		"camera_size":BENCHMARK_CAMERA_SIZE,
		"vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps,
		"msaa":root.msaa_3d, "summary":summary, "warmup":stats(cold),
		"cpu_process":stats(cpu), "physics":stats(physics),
		"frame_intervals_ms":samples, "warmup_intervals_ms":cold,
		"cpu_ms":cpu, "physics_ms":physics,
		"draw_calls_last_frame":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"player_distance":world.player.travelled,
		"urban_ablation":ablate_urban,
		"notes":"5 s warmup + 30 s rendered frame intervals at the affected Harbor site. --no-save required by launcher."
	}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/"+label+".png")
	var file := FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("URBAN_OPERATIONS_BENCHMARK ",label," ",JSON.stringify(summary))
	world.free()
	await process_frame
	quit(0)
