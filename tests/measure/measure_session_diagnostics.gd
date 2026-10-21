extends "res://tests/measure/measure.gd"
## Stationary real Main scene: 10s warmup, 30s measured, normal population/density.
## Compare detailed vs essential logging serially; no saves or input-driven movement.
var unfocused_frames := 0
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	create_timer(180).timeout.connect(func(): quit(3))
	seed(12345)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 100000
	while (world.session == null or not world.session.ready_for_play or world.production == null or not world.production.ready_for_play) and Time.get_ticks_msec() < deadline:
		await process_frame
	if world.session == null or not world.session.ready_for_play:
		quit(4)
		return
	world.session.state.intro.stage = "complete"
	world.player.teleport(Vector3(107,.1,23))
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.set_process_input(false)
	world.session.set_process_unhandled_input(false)
	await create_timer(20).timeout
	started = Time.get_ticks_usec()
	previous = started

func _process(_delta: float) -> bool:
	if started == 0: return false
	world.player.automatic_direction = Vector3.ZERO
	var now := Time.get_ticks_usec()
	var frame_ms := float(now-previous)/1000.0
	previous = now
	if not measuring:
		cold.append(frame_ms)
		if now-started >= 10000000:
			measuring = true
			measured_started = now
		return false
	samples.append(frame_ms)
	if not DisplayServer.window_is_focused(): unfocused_frames += 1
	cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
	if now-measured_started >= 30000000:
		started = 0
		finish.call_deferred()
	return false

func finish() -> void:
	var report := {"summary":stats(samples),"warmup":stats(cold),"frame_intervals_ms":samples,
		"cpu":stats(cpu),"physics":stats(physics),"engine":Engine.get_version_info().string,
		"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,
		"population":world.people.size(),"cars":world.production.vehicles.size(),
		"session_log":OS.get_environment("HARBOR_SESSION_LOG"),"session_profile":OS.get_environment("HARBOR_SESSION_PROFILE"),
		"stall_log":OS.get_environment("HARBOR_STALL_LOG"),"unfocused_frames":unfocused_frames,
		"msaa":root.msaa_3d,"render_scale":root.scaling_3d_scale,"position":str(world.player.position),
		"scene":"Main.tscn stationary harbor spawn; 20s settlement + 10s warmup + 30s sample"}
	var file := FileAccess.open("res://evidence/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BENCHMARK ", label, " ", JSON.stringify(report.summary))
	world.queue_free()
	await process_frame
	quit()
