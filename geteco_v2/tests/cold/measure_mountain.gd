extends "res://tests/measure.gd"
var cold_enabled := false
var cold_adapter: Node
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	cold_enabled = "--cold" in OS.get_cmdline_user_args()
	label = "mountain-cold" if cold_enabled else "mountain-baseline"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_cold",true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.session.weather!=null: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	if not world.production.travel("mountain"): quit(1); return
	var origin := Vector3((5980.0+4300)/16,0,(790.0-4960)/16)
	world.player.set_physics_process(false)
	world.player.teleport(origin+Vector3.UP*.08)
	world.production.region.set_focus(origin)
	for i in 60: await physics_frame
	var found := false
	for offset in [0,4,8,12,16]:
		var candidate := origin+Vector3(0,.08,offset)
		var clear := true
		for step in 25:
			if not world.session.position_clear(candidate+Vector3(-3+step*.25,0,0)): clear=false; break
		if clear:
			origin = candidate
			found = true
			break
	if not found: push_error("No physically clear cold benchmark route"); quit(1); return
	world.player.teleport(origin)
	world.player.set_physics_process(true)
	world.camera.initialized = false
	world.player.controlled_automatically = true
	world.player.speed = 1.5
	world.session.set_process_input(false)
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.weather.time_of_day = .32
	world.session.weather.weather_state = 1
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	for i in 180: await physics_frame
	# Benchmark never writes user saves. Both variants share Main+population+snow.
	if cold_enabled:
		cold_adapter = load("res://runtime/ColdSurvival.gd").new()
		cold_adapter.configure(world.session)
		world.add_child(cold_adapter)
		world.session.cold = cold_adapter
		cold_adapter.model.weather_clock = 100
	route = PackedVector3Array([origin+Vector3(-3,0,0),origin+Vector3(3,0,0)])
	started = Time.get_ticks_usec()
	previous = started
func finish() -> void:
	var summary := stats(samples)
	var report := {"label":label,"scene":"Main.tscn / mountain","gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"population":world.people.size(),"requested_population":world.production.requested_population,"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"summary":summary,"warmup":stats(cold),"cpu":stats(cpu),"physics":stats(physics),"intervals_ms":samples,"warmup_ms":cold,"distance":world.player.travelled,"cold_enabled":cold_enabled,"route":str(route),"walk_pass":world.player.travelled>=40}
	if cold_enabled: report["thermal"] = cold_adapter.snapshot()
	DirAccess.make_dir_recursive_absolute("res://tests/cold/evidence")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/cold/evidence/"+label+".png")
	var file := FileAccess.open("res://tests/cold/evidence/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("COLD_BENCHMARK ",JSON.stringify(summary))
	world.queue_free()
	await process_frame
	quit(0 if report.walk_pass else 1)
