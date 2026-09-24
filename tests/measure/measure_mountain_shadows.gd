extends SceneTree

## Rendered 30-second production benchmark at the mountain village, without saves.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var out_dir := ""
var label := "mountain-shadow"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Rendered mountain benchmark requires --no-save")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		push_error("Benchmark requires an existing --out-dir")
		quit(2)
		return
	if "--uncapped" in OS.get_cmdline_user_args():
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	for frame in 4800:
		await physics_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if world.production == null or not world.production.ready_for_play or not world.session.ready_for_play:
		push_error("Production session did not start")
		quit(1)
		return
	var focus: Vector3 = CATALOG._at(Vector2(7630, -1590), "mountain")
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.production._update_physical_residency(focus)
	world.player.teleport(focus + Vector3.UP * 0.12)
	world.production._update_logical_region(focus)
	world.production.region.set_focus(focus)
	world.camera.heading = 0
	world.camera.target_size = 30
	for frame in 900:
		await process_frame
		if world.production.region.pending.is_empty(): break
	var weather = world.session.weather
	weather.time_of_day = 0.50
	weather.weather_state = 0
	weather._update()
	weather.set_process(false)
	var city_look: Node = world.get_node_or_null("CityLook")
	if city_look != null: city_look.set_process(false)
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	world.production.sun.rotation_degrees = Vector3(-70.0, -135.0, 0) if baseline else Vector3(-42.0, -135.0, 0)
	var contact_count := 0
	for contact in world.production.region.find_children("Mountain*Contact*", "MeshInstance3D", true, false):
		contact_count += 1
		if baseline: contact.hide()
	var warmup_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warmup_start < 5000000: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over_33 := 0
	var over_66 := 0
	for sample in samples:
		total += sample
		if sample > 33.3: over_33 += 1
		if sample > 66.7: over_66 += 1
	var summary := {"frames":samples.size(),"seconds":total/1000.0,"fps":samples.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*0.50)],"p95_ms":sorted[int((sorted.size()-1)*0.95)],"p99_ms":sorted[int((sorted.size()-1)*0.99)],"max_ms":sorted[-1],"over_33_3_ms":over_33,"over_66_7_ms":over_66}
	var report := {"label":label,"scene":"Main mountain village","baseline_ablation":baseline,"contact_meshes":contact_count,"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"population":world.people.size(),"cars":world.production.vehicles.size(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"region":world.session.state.region_id,"player":str(world.player.global_position),"health":world.gameplay.health,"sun_rotation":str(world.production.sun.rotation_degrees),"summary":summary}
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(label + ".png"))
	var output = FileAccess.open(out_dir.path_join(label + ".json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("MOUNTAIN_BENCHMARK ", JSON.stringify(report))
	quit(0 if report.region == "mountain" and report.health > 0 else 1)
