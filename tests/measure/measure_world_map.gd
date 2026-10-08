extends SceneTree
## Real Main, isolated save, 30-second rendered windows. No user save writes.
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var world
var output := ""
var samples: Array[float] = []
var recording := false
var stamp := 0
var results := {}

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("WORLD_MAP timeout"); quit(3))
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if recording and stamp > 0: samples.append(float(now-stamp)/1000.0)
	stamp=now
	return false

func sample(label: String, map, moving := false) -> void:
	samples.clear(); stamp=Time.get_ticks_usec(); recording=true
	var start := Time.get_ticks_msec()
	var origin: Vector2=map.target_center
	while Time.get_ticks_msec()-start < 30000:
		if moving:
			var t := float(Time.get_ticks_msec()-start)/1000.0
			map.target_center=origin+Vector2(sin(t*.5)*80,cos(t*.5)*40)
		await process_frame
	recording=false
	var sorted := samples.duplicate(); sorted.sort()
	var total := 0.0; var over33 := 0; var over66 := 0
	for value in samples:
		total+=value
		if value>33.3: over33+=1
		if value>66.7: over66+=1
	results[label]={"frames":samples.size(),"seconds":total/1000,"fps":samples.size()*1000/total,"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over33":over33,"over66":over66,"raw_ms":samples.duplicate()}
	print("WORLD_MAP ",label," fps=",results[label].fps," p95=",results[label].p95," p99=",results[label].p99)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output=FIXTURE.output_dir("world-map")
	var at := Vector3(80,.12,80)
	var data := FIXTURE.full_snapshot(at,true)
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true); world.set_meta("menu_save_path",path)
	root.add_child(world); current_scene=world
	for i in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	if world.dispatch.router._native==null: push_error("C# path unavailable"); quit(1); return
	world.gameplay.god_mode=true
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1280,720)
	world.session.weather.set_process(false); world.session.weather.time_of_day=.45; world.session.weather._update()
	Engine.max_fps=0; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	results.environment={"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[1280,720],"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"scene":"Main.tscn","native":true,"population":world.people.size()}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--baseline-map="): continue
		var baseline := GDScript.new()
		baseline.source_code=FileAccess.get_file_as_string(argument.trim_prefix("--baseline-map="))
		assert(baseline.reload()==OK)
		world.session._menu("Mapa")
		var old_map=baseline.new(); old_map.controller=world.session.controller
		world.hud.add_child(old_map); world.session.panel.hide(); world.session.menu_closed=old_map.queue_free
		old_map.center=Vector2(80,80); old_map.target_center=old_map.center
		old_map.zoom=.8/old_map._base_zoom; old_map.target_zoom=old_map.zoom
		await create_timer(3).timeout
		await capture("baseline")
		await sample("baseline_stationary",old_map)
		await sample("baseline_pan",old_map,true)
		world.session.close_menu(); await process_frame
	var began := Time.get_ticks_usec()
	world.session.show_map()
	results.open_ms=float(Time.get_ticks_usec()-began)/1000.0
	var map=world.hud.get_node("MapUI")
	if "--compare" in OS.get_cmdline_user_args():
		map.focus_region("harbor"); map.center=Vector2(80,80); map.target_center=map.center
		map.zoom=.8/map._base_zoom; map.target_zoom=map.zoom
	await create_timer(3).timeout
	await capture("map-open")
	print("WORLD_MAP_READY ",output)
	var capture_only := "--capture-only" in OS.get_cmdline_user_args()
	if not capture_only:
		await sample("stationary",map)
		await sample("pan",map,true)
	if map.has_method("focus_region"):
		map.focus_region("world"); await create_timer(1).timeout; await capture("world")
		map.focus_region("mountain"); await create_timer(1).timeout; await capture("mountain")
		map.focus_region("desert"); await create_timer(1).timeout; await capture("desert")
		if not capture_only: await sample("desert_pan",map,true)
		if not capture_only:
			Engine.max_fps=60; DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			await create_timer(2).timeout
			await sample("normal_60fps",map)
		map.focus_region("harbor"); await create_timer(1).timeout; await capture("city")
		var marker := -1
		for i in map._markers.size():
			if map._markers[i].title=="Digo": marker=i; break
		assert(marker>=0,"actual desert mechanic is discoverable from city")
		map.select_marker(marker); map._locate_selected(); await create_timer(1).timeout
		assert(map.sidebar.visible and map.marker_title.text=="Digo")
		map._mark_selected()
		assert(map._waypoint==map._markers[marker].point,"destination uses actual entry position")
		await capture("selected-digo")
		map._set_filter("hospital"); map.focus_region("harbor"); await create_timer(.7).timeout
		assert(map._drawn_markers.all(func(i): return map._markers[i].kind=="hospital" or map._markers[i].objective))
		map._set_filter("hospital"); map.focus_region("mountain"); await create_timer(.7).timeout
		var old_zoom: float=map.target_zoom
		var wheel := InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true
		map.map_input(wheel); assert(map.target_zoom>old_zoom)
		var wanted: Vector2=map.project(map._actor_point())
		assert(map.unproject(wanted).distance_to(map._actor_point())<.001,"projection and picking agree")
		root.content_scale_size=Vector2i(800,600); root.size=Vector2i(800,600)
		await create_timer(.7).timeout; await capture("compact")
		root.content_scale_size=Vector2i(1280,720); root.size=Vector2i(1280,720)
	world.session.close_menu(); await process_frame
	assert(not world.session.modal and not world.player.input_locked)
	world.session.show_map(); await create_timer(.5).timeout
	var reopened=world.hud.get_node("MapUI")
	if reopened.has_method("focus_region"):
		assert(reopened._waypoint.is_finite(),"destination survives closing and reopening map")
		reopened._clear_waypoint(); assert(not world.has_meta("map_waypoint"))
	world.session.close_menu(); await process_frame
	var file := FileAccess.open(output.path_join("metrics.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")); file.close()
	print("WORLD_MAP_DONE ",output)
	world.free(); quit()
