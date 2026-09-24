extends SceneTree

## Rendered Main-scene inspection and comparable 30 s benchmark for mountain roads.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args:
		push_error("Mountain road probe needs rendered --no-save")
		quit(2)
		return
	var out_dir := ""
	var label := "mountain-roads"
	var site := "lake"
	for arg in args:
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--site="): site = arg.trim_prefix("--site=")
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		push_error("Mountain road probe needs existing --out-dir")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 1200:
		await physics_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if world.production == null or not world.production.ready_for_play or not world.session.ready_for_play:
		push_error("Production world did not start")
		quit(1)
		return
	var source_point := Vector2(7000, 0)
	if site == "east": source_point = Vector2(6250, 340)
	elif site == "ammu": source_point = Vector2(6950, -250)
	elif site == "cave": source_point = Vector2(6120, 320)
	elif site == "village": source_point = Vector2(7630, -1590)
	elif site == "secret": source_point = Vector2(5450, -1150)
	var focus: Vector3 = CATALOG._at(source_point, "mountain")
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	world.production.set_process(false)
	world.production._update_physical_residency(focus)
	world.player.set_physics_process(false)
	world.player.teleport(focus + Vector3.UP * 0.8)
	world.production._update_logical_region(focus)
	world.production.region.set_focus(focus)
	world.camera.heading = 0
	world.camera.target_size = 36
	world.camera.focus = focus
	world.camera.initialized = true
	world.camera.locked = true
	world.camera.set_process(false)
	world.camera.global_position = focus + Vector3(0, 34, 24)
	world.camera.look_at(focus)
	world.camera.size = 36
	world.camera.make_current()
	world.hud.hide()
	for frame in 900:
		await process_frame
		if world.production.region.pending.is_empty(): break
	var weather = world.session.weather
	weather.time_of_day = 0.50
	for arg in args:
		if arg.begins_with("--time="): weather.time_of_day = float(arg.trim_prefix("--time="))
	weather.weather_state = 0
	weather._update()
	weather.set_process(false)
	var city_look: Node = world.get_node_or_null("CityLook")
	if city_look != null: city_look.set_process(false)
	for frame in 60: await process_frame
	var samples: Array[float] = []
	if "--benchmark" in args:
		var warmup := Time.get_ticks_usec()
		while Time.get_ticks_usec() - warmup < 5000000: await process_frame
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append(float(now - previous) / 1000.0)
			previous = now
	await RenderingServer.frame_post_draw
	var image_path := out_dir.path_join(label + ".png")
	root.get_texture().get_image().save_png(image_path)
	var lit_lamps := 0
	for lamp in world.production.region.find_children("*","OmniLight3D",true,false):
		if lamp.is_in_group("mountain_night_light") and lamp.light_energy > .01: lit_lamps += 1
	var report := {"site":site,"time":weather.time_of_day,"lit_lamps":lit_lamps,"focus":str(focus),"region":world.session.state.region_id,"chunks":world.production.region.chunks.size(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"image":image_path}
	if not samples.is_empty():
		var sorted := samples.duplicate()
		sorted.sort()
		var total := 0.0
		var over_33 := 0
		var over_66 := 0
		for sample in samples:
			total += sample
			if sample > 33.3: over_33 += 1
			if sample > 66.7: over_66 += 1
		report["summary"] = {"frames":samples.size(),"fps":samples.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.50)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over_33_3_ms":over_33,"over_66_7_ms":over_66}
	var file := FileAccess.open(out_dir.path_join(label + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("MOUNTAIN_ROAD_PROBE ", JSON.stringify(report))
	quit(0 if report.region == "mountain" else 1)
