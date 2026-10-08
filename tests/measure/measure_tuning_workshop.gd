extends "res://tests/test_maciota_workshop_session.gd"
## Rendered Main + actual mechanic flow. Isolated checkpoint; 30s samples.
var results := {}
var sample_frames: Array[float] = []
var recording := false
var stamp := 0
var label := "before"

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0: sample_frames.append(float(now-stamp)/1000.0)
	stamp = now
	return false

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func sample(id: String) -> void:
	sample_frames.clear()
	stamp = Time.get_ticks_usec()
	recording = true
	await create_timer(30).timeout
	recording = false
	var sorted := sample_frames.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for v in sample_frames:
		total += v
		if v > 33.3: over33 += 1
		if v > 66.7: over66 += 1
	results[id] = {"frames":sorted.size(),"seconds":total/1000.0,"fps":sorted.size()*1000.0/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":sample_frames.duplicate()}
	results[id].config = {"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"msaa_3d":root.msaa_3d,"showroom_msaa_3d":world.session.maciota_workshop.panel._showroom._viewport.msaa_3d}
	print("WORKSHOP_MEASURE ",id," fps=",results[id].fps," p95=",results[id].p95," p99=",results[id].p99)

func _run() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): _finish(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	folder = FIXTURE.output_dir("tuning-workshop-"+label)
	path = FIXTURE.write_fixture(folder,"checkpoint.json",_seed())
	var launch := root.get_node_or_null("V2Launch")
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	world.dispatch.router.nearest_edge(Vector3(166,.08,111.8))
	if not _check(world.dispatch.router._native != null,"C# router active"): _finish(1); return
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	world.session.state.campaign.cancel("test_fixture")
	if not await world.session.enter_place("maciota",false): _finish(1); return
	await _frames(12)
	if not await _open_mechanic() or not await _press_menu("Preparar "): _finish(1); return
	var panel = world.session.maciota_workshop.panel
	var showroom = panel._showroom
	results.environment = {"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"scene":"Main.tscn","native":true,"people":world.people.size(),"budget_ms":16.67,"regression_review_percent":5}
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await create_timer(5).timeout
	await capture("mechanic")
	if not "--capture-only" in OS.get_cmdline_user_args(): await sample("mechanic_unlimited")
	panel.show_vehicle("desert_coyote",{"neon":"neon_cyan"},["neon_cyan"],4,12400,{"archetype":"desert_coyote","paint":Color("284d79")})
	panel._select_slot("neon")
	await create_timer(5).timeout
	showroom._yaw = .75
	await capture("coyote")
	if not "--capture-only" in OS.get_cmdline_user_args(): await sample("coyote_unlimited")
	panel.show_vehicle("porto_rosso",{},[],4,12400,{"archetype":"porto_rosso","paint":Color("e01824")})
	showroom._yaw = .75
	await _frames(3)
	await capture("porto-rosso")
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	if "--temporal" in OS.get_cmdline_user_args():
		panel.show_vehicle("desert_coyote",{"paint":"paint_ocean","finish":"finish_satin","wheels":"wheels_bronze","neon":"neon_cyan"},["paint_ocean","finish_satin","wheels_bronze","neon_cyan"],4,12400,{"archetype":"desert_coyote","paint":Color("284d79")})
		panel._select_slot("paint")
		await _frames(3)
		panel._preview({})
		showroom.reset_view()
		await capture("custom-painted")
		await sample("open_normal_60")
		var dir := folder.path_join("temporal")
		DirAccess.make_dir_recursive_absolute(dir)
		var began := Time.get_ticks_msec()
		var index := 0
		var timestamps := []
		var rendered_frames := []
		while Time.get_ticks_msec()-began < 30000:
			var seconds := float(Time.get_ticks_msec()-began)/1000.0
			showroom._zoom = 1.0+.12*sin(seconds*.35)
			await RenderingServer.frame_post_draw
			timestamps.append(Time.get_ticks_msec()-began)
			rendered_frames.append(Engine.get_frames_drawn())
			root.get_texture().get_image().save_jpg(dir.path_join("%05d.jpg" % index),.9)
			index += 1
		results.temporal = {"frames":index,"timestamps_ms":timestamps,"rendered_frames":rendered_frames}
	panel.close_panel()
	await _frames(3)
	_check(not showroom.has_model(),"close releases preview vehicle")
	_check(showroom._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,"close stops extra render")
	if not "--capture-only" in OS.get_cmdline_user_args(): await sample("closed_normal_60")
	results.failures = failures
	FileAccess.open(folder.path_join("metrics.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("WORKSHOP_OUTPUT ",folder)
	_finish(0 if failures.is_empty() else 1)
