extends "res://tests/measure/measure.gd"
## Same integrated new-game world, 5 s warm-up + 30 s film, then actual disembarkation.
var film_slow_frames: Array = []
var focus_events: Array = []
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	label = "opening-before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.get_node("V2Launch").selected_path = "user://opening-review-isolated.json"
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	if "--trace-handoff" in OS.get_cmdline_user_args(): current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	assert(world.session != null and world.session.ready_for_play)
	var arrival = world.session.arrival
	if not is_instance_valid(arrival.presentation):
		arrival.phase = "new"
		arrival.opening_completed = false
		arrival.active = true
		arrival.start_or_resume(false)
	assert(is_instance_valid(arrival.presentation))
	if "--require-render-gate" in OS.get_cmdline_user_args(): assert(root.disable_3d)
	# Mantém a comparação independente de mudanças posteriores nas configurações locais do usuário.
	Engine.max_fps = 60 if "--normal-fps" in OS.get_cmdline_user_args() else 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920,1080)
	if "--diagnose-film" in OS.get_cmdline_user_args():
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		root.focus_entered.connect(func(): focus_events.append({"usec":Time.get_ticks_usec(),"focused":true}))
		root.focus_exited.connect(func(): focus_events.append({"usec":Time.get_ticks_usec(),"focused":false}))
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0: return false
	var now := Time.get_ticks_usec()
	var ms := float(now - previous) / 1000.0
	previous = now
	if not measuring:
		cold.append(ms)
		if now - started >= 5000000:
			measuring = true
			measured_started = now
		return false
	samples.append(ms)
	if ms > 33.3 and "--diagnose-film" in OS.get_cmdline_user_args():
		film_slow_frames.append({"ms":ms,"since_start":float(now-started)/1000000.0,"focused":root.has_focus(),"movie_time":world.session.arrival.presentation.film.video.stream_position,"cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())})
	if now - measured_started >= 30000000:
		started = 0
		finish.call_deferred()
	return false

func finish() -> void:
	var report := {"label":label, "summary":stats(samples), "warmup":stats(cold),
		"frame_intervals_ms":samples, "warmup_intervals_ms":cold,
		"engine":Engine.get_version_info().string, "gpu":RenderingServer.get_video_adapter_name(),
		"renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size),
		"vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps,
		"population":world.people.size(), "cars":world.production.vehicles.size()}
	var arrival = world.session.arrival
	report.film_slow_frames = film_slow_frames
	report.focus_events = focus_events
	assert(is_instance_valid(arrival.presentation))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/" + label + "-film.png")
	if not "--natural-end" in OS.get_cmdline_user_args(): arrival.presentation.film.skip()
	var deadline := Time.get_ticks_msec()+55000
	var handoff_previous := Time.get_ticks_usec()
	var handoff_max_ms := 0.0
	var handoff_slow: Array = []
	var closing_samples: Array[float] = []
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var tick := Time.get_ticks_usec()
		var handoff_ms := float(tick-handoff_previous)/1000.0
		handoff_previous = tick
		if is_instance_valid(arrival.presentation) and arrival.presentation.film.video.stream_position >= 42.0:
			closing_samples.append(handoff_ms)
		handoff_max_ms = maxf(handoff_max_ms,handoff_ms)
		if handoff_ms > 33.3:
			handoff_slow.append({"ms":handoff_ms,"phase":arrival.phase,"paused":paused,"disabled_3d":root.disable_3d})
		if arrival.phase == "terminal_meeting": break
	report.handoff_max_ms = handoff_max_ms
	report.handoff_slow_frames = handoff_slow
	if not closing_samples.is_empty(): report.closing_summary = stats(closing_samples)
	report.closing_frame_intervals_ms = closing_samples
	report.disembarked = arrival.phase == "terminal_meeting" and arrival.flags.get("harbor_arrival_seen",false)
	report.controls_restored = not world.player.input_locked and world.player.visible and not paused
	report.rendering_restored = not root.disable_3d
	report.quay_time = world.session.weather.time_of_day
	report.quay_weather = world.session.weather.weather_state
	report.climate_continuity = report.quay_time > .9 and report.quay_weather == 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/" + label + "-quay.png")
	var file := FileAccess.open("res://evidence/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("OPENING_BENCHMARK ", label, " ", JSON.stringify(report.summary), " disembarked=", report.disembarked)
	world.queue_free()
	await process_frame
	quit(0 if report.disembarked and report.controls_restored and report.rendering_restored and report.climate_continuity else 1)
