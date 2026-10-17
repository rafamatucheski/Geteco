extends "res://tests/measure/measure_fishing_life.gd"
## Same live production scene, isolated save, finite day/night fishing windows.
var screenshots := false
var views := {}
var confirm_run := false
var focus_counts := {}

func _process(delta: float) -> bool:
	super._process(delta)
	if tracing:
		if not focus_counts.has(phase): focus_counts[phase] = {"focused":0,"unfocused":0}
		var key := "focused" if DisplayServer.window_is_focused() else "unfocused"
		focus_counts[phase][key] += 1
	return false

func wait_exclusive() -> bool:
	# A separate session can launch another engine while this scene is loading.
	# Check before warm-up, never during a measured frame window.
	if OS.get_name() != "Windows": return true
	for attempt in 30:
		var output := []
		var command := "@(Get-Process -Name 'Godot_v4.7.2-stable_mono_win64' -ErrorAction SilentlyContinue | Where-Object Id -ne %d).Count" % OS.get_process_id()
		OS.execute("powershell.exe", PackedStringArray(["-NoProfile","-Command",command]), output, false, false)
		if not output.is_empty() and str(output[0]).strip_edges() == "0":
			print("FISHING_MEASURE_EXCLUSIVE pid=",OS.get_process_id())
			return true
		await create_timer(2).timeout
	print("FISHING_MEASUREMENT_SKIPPED another game process is still active")
	return false

func fingerprint() -> Dictionary:
	var result := super.fingerprint()
	result["res://world/places/fishing/fishing_ground_surface.gdshaderinc"] = FileAccess.get_sha256("res://world/places/fishing/fishing_ground_surface.gdshaderinc")
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	create_timer(420).timeout.connect(func(): push_error("Fishing redesign measurement timeout"); quit(3))
	seed(71026)
	label = "before" if "--before" in OS.get_cmdline_user_args() else "after"
	confirm_run = "--confirm" in OS.get_cmdline_user_args()
	folder = FIXTURE.output_dir("fishing-redesign-" + label + ("-confirmation" if confirm_run else ""))
	var before := fingerprint()
	var snapshot := FIXTURE.full_snapshot(ENTRY, false)
	snapshot.campaign.active_id = ""
	snapshot.campaign.step = 0
	snapshot.economy.balance = 500
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", FIXTURE.write_fixture(folder, "isolated-save.json", snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	if world.dispatch.router._native == null: push_error("C# routing required"); quit(5); return
	world.session.weather.set_process(false)
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 9999
	world.session.weather._update()
	world.production.region.set_focus(ENTRY)
	world.production.region.prepare_collision_at(ENTRY)
	world.player.teleport(ENTRY)
	world.session.fishing_runtime.refresh()
	world.camera.initialized = false
	await sample("first_visit", 8)
	var site = world.session.fishing_runtime.site
	if not is_instance_valid(site): push_error("Fishing venue missing"); quit(6); return
	world.player.teleport(site.fishing_spots()[0].position + Vector3.UP * .03)
	world.camera.initialized = false
	await create_timer(1).timeout
	print("FISHING_REDESIGN_BASELINE_LOADED ", folder)
	for hour in [.45, .02]:
		var regime := "day" if hour > .1 else "night"
		world.session.weather.time_of_day = hour
		world.session.weather._update()
		fishing_driver = world.session.fishing
		fishing_driver._rng.seed = 71026
		if not fishing_driver.start(-1): push_error("Cannot start fishing"); quit(6); return
		if label == "after":
			# The controlled A/B view preserves the original gameplay framing.
			# The new closer camera is measured separately below.
			await create_timer(.25).timeout
			world.camera.locked = false
			world.camera.initialized = false
			world.camera.make_current()
		if not (await wait_exclusive()):
			FileAccess.open(folder.path_join("measurement-skipped.json"),FileAccess.WRITE).store_string(JSON.stringify({"reason":"another game process still active","performance_approved":false}))
			world.queue_free()
			for frame in 8: await process_frame
			quit(7)
			return
		if confirm_run: DisplayServer.window_move_to_foreground()
		await sample(regime + "_warmup", 5)
		print("FISHING_WINDOW_START ",regime,"_fishing ",Time.get_datetime_string_from_system())
		await sample(regime + "_fishing", 30)
		print("FISHING_WINDOW_END ",regime,"_fishing ",Time.get_datetime_string_from_system())
		views[regime] = {"transform":str(root.get_camera_3d().global_transform),"size":root.get_camera_3d().size}
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(regime + ".png"))
		fishing_driver.cancel_attempt()
		fishing_driver = null
		await create_timer(.5).timeout
		if label == "after" and not confirm_run:
			fishing_driver = world.session.fishing
			fishing_driver._rng.seed = 71026
			if not fishing_driver.start(-1): quit(6); return
			await sample(regime + "_close_warmup", 5)
			await sample(regime + "_close_fishing", 30)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(regime + "-close.png"))
			views[regime + "_close"] = {"transform":str(root.get_camera_3d().global_transform),"size":root.get_camera_3d().size}
			fishing_driver.cancel_attempt()
			fishing_driver = null
			await create_timer(.5).timeout
	var summary := {}
	for key in intervals:
		var values: Array[float] = []
		values.assign(intervals[key])
		if not values.is_empty(): summary[key] = stats(values)
	var report := {"label":label, "summary":summary, "frames_ms":intervals, "views":views, "gpu":RenderingServer.get_video_adapter_name(), "engine":Engine.get_version_info(), "renderer":RenderingServer.get_current_rendering_method(), "resolution":str(root.size), "vsync":DisplayServer.window_get_vsync_mode(), "max_fps":Engine.max_fps, "people":world.people.size(), "vehicles":world.production.vehicles.size(), "source_before":before, "source_after":fingerprint(), "position":str(world.player.global_position), "native_router":true, "notes":"Normal scene and fishing inputs; isolated save. A/B uses ordinary camera; close view separately measured. C# verified. 60 FPS provisional goal; >5% p95/p99 increase requires finite confirmation. No FPS certification from screenshots."}
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	FileAccess.open(folder.path_join("focus-counts.json"), FileAccess.WRITE).store_string(JSON.stringify(focus_counts,"\t"))
	print("FISHING_REDESIGN_REPORT ", folder, " ", JSON.stringify(summary))
	if label == "after": await capture_final()
	world.queue_free()
	for frame in 8: await process_frame
	quit()

func capture_final() -> void:
	# Measurements are complete and exported before any frame readback or resize.
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size = Vector2i(1280,720)
	world.session.weather.time_of_day = .45
	world.session.weather._update()
	fishing_driver = world.session.fishing
	if not fishing_driver.start(-1): return
	fishing_driver._rng.seed = 12345
	var old_cap := Engine.max_fps
	Engine.max_fps = 30
	var path := folder.path_join("sequence")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var frames: Array[Dictionary] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var photographed := {}
	while not confirm_run and previous-started < 32000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var phase_name: String = fishing_driver.phase
		var frame_image := root.get_texture().get_image()
		frame_image.save_jpg(path.path_join("frame-%05d.jpg" % frames.size()),.86)
		if phase_name in ["reeling","landing","caught"] and fishing_driver._phase_time > .9 and not photographed.has(phase_name):
			frame_image.save_png(folder.path_join("final-"+phase_name+".png"))
			photographed[phase_name] = true
		frames.append({"frame":frames.size(),"ms":float(now-started)/1000.0,"interval_ms":float(now-previous)/1000.0,"phase":phase_name,"fish":str(fishing_driver._rod._fish.global_position),"tension":fishing_driver.fight.tension})
		previous = now
	if not frames.is_empty(): FileAccess.open(folder.path_join("sequence.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":frames,"every_rendered_frame":true,"fps_cap_for_capture":30,"performance_evidence":false},"\t"))
	fishing_driver.cancel_attempt()
	await create_timer(.25).timeout
	# Explicit visual edge fixture, not a natural-roll claim or performance sample.
	fishing_driver.start(-1)
	fishing_driver._rng.seed = 12345
	var selected := false
	var caught_at := 0
	var deadline := Time.get_ticks_msec()+25000
	while fishing_driver.active and Time.get_ticks_msec()<deadline:
		if fishing_driver.phase == "casting" and not selected:
			fishing_driver.current_fish = {"id":"pirarara","grams":14000}
			selected = true
		if fishing_driver.phase == "reeling" and fishing_driver._phase_time > 1.0: fishing_driver.fight.progress = 1.01
		if fishing_driver.phase == "caught":
			if caught_at == 0: caught_at = Time.get_ticks_msec()
			if Time.get_ticks_msec()-caught_at > 800:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("final-pirarara-14kg-fixture.png"))
				break
		await process_frame
	fishing_driver.cancel_attempt()
	fishing_driver = null
	Engine.max_fps = old_cap
	print("FISHING_FINAL_SEQUENCE ",folder," frames=",frames.size())
