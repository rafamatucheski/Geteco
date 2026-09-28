extends "res://tests/measure/measure.gd"
## Rendered Main comparison. Fixed seed/settings, no personal save, real traffic.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	seed(25092026)
	var data = preload("res://world/editing/WorldEditData.gd")
	var edits := data.empty_document()
	if "--with-ground" in OS.get_cmdline_user_args():
		for index in 7:
			for site in [Vector2(-46,49),Vector2(481,117),Vector2(850,-450)]:
				var row := {"id":"new/ground_bench_"+str(index)+str(site.x),"type":"ground","position":[site.x+float(index%3)*9-9,site.y+float(index/3)*9-9],"rotation":float(index)*13.0,"size":[8.0,8.0],"surface":["grass","earth","sand","gravel","concrete","asphalt","pavers"][index]}
				edits.regions["mountain" if site.y < -125 else "harbor"][row.id] = row
	Engine.set_meta("geteco_world_edit_document",edits)
	# Physical keyboard/mouse events must never alter a measurement. Action
	# injection below still exercises real aiming; this never saves bindings.
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var variant := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
	var folder := "res://evidence/world-editor-20260925/" + variant
	DirAccess.make_dir_recursive_absolute(folder)
	var settings := root.get_node("V2Settings")
	settings.window_mode = 0
	settings.resolution = 0
	settings.vsync = true
	settings.fps_limit = 1
	settings.apply_settings()
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		push_error("HUD benchmark: production session unavailable")
		quit(1)
		return
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	world.session.weather.weather_timer = 99999
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.set_process(false)
	world.session.weather._update()
	world.session.state.grant_weapon("pistol")
	world.session.state.add_ammo("pistol", 200)
	world.session.state.equip_weapon("pistol")
	world.gameplay.armor = 60
	var report := {"gpu": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "seed": 25092026, "cases": []}
	var cases := ["neko", "cobra"]
	if "--all-areas" in OS.get_cmdline_user_args(): cases = ["neko","cobra","mountain"]
	if "--mountain-only" in OS.get_cmdline_user_args(): cases = ["mountain"]
	if "--preview" in OS.get_cmdline_user_args(): cases = ["preview"]
	for scenario in cases:
		var destination := Vector3(-46,0.08,49) if scenario == "neko" else Vector3(481,0.08,117)
		if scenario == "mountain":
			destination = Vector3(850,0,-450)
			world.production._mount_region("mountain",destination)
			world.production._commit_logical_region("mountain")
			destination.y = world.production.region.terrain.surface_height_at(Vector2(850,-450))+.12
		world.production.region.set_focus(destination)
		world.player.teleport(destination)
		world.camera.initialized = false
		for i in 8: await physics_frame
		if scenario == "preview":
			world.camera.set_preview_view(true)
		if scenario == "drive-night":
			var car = world.driving.car
			world.player.teleport(car.driver_door_anchor(-1) - car.global_basis.x * .35)
			for i in 4: await physics_frame
			if not world.driving.interact(true):
				push_error("HUD benchmark could not enter real car")
				quit(1)
				return
			car.external_input = true
			world.session.weather.time_of_day = .85
			world.session.weather.weather_state = 1
			world.session.weather._update()
		var origin: Vector3 = world.player.position
		var warm: Array[float] = []
		var measured: Array[float] = []
		var last := Time.get_ticks_usec()
		var begin := last
		var measured_ms := 0.0
		while Time.get_ticks_usec() - begin < 8000000 or measured_ms < 30000.0:
			var elapsed := float(Time.get_ticks_usec() - begin) / 1000000.0
			if scenario != "drive-night":
				var goal := origin + Vector3(2 if int(elapsed / 3.0) % 2 == 0 else -2, 0, 0)
				world.player.automatic_direction = (goal - world.player.position).normalized() * Vector3(1, 0, 1)
				# Exercise real aim/reload HUD state without manufacturing police.
				if int(elapsed / 6.0) % 2 == 0: Input.action_press("aim")
				else: Input.action_release("aim")
			else:
				var car = world.driving.car
				if not world.driving.occupied:
					push_error("Invalid driving benchmark: player left the vehicle")
					quit(1)
					return
				car.throttle_input = .2 if elapsed < 12 else 0.0
				car.brake_input = elapsed >= 12
			await process_frame
			var now := Time.get_ticks_usec()
			if elapsed < 8.0: warm.append((now-last)/1000.0)
			else:
				measured.append((now-last)/1000.0)
				measured_ms += (now-last)/1000.0
			last = now
		Input.action_release("aim")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(scenario + ".png"))
		var result := {"scenario": scenario, "summary": stats(measured), "warmup": stats(warm), "frames_ms": measured, "warmup_ms": warm, "population": world.people.size(), "vehicles": world.production.vehicles.size(), "position": str(world.player.position), "camera_size": world.camera.size, "occupied": world.driving.occupied, "wanted": world.gameplay.stars, "external_input_disabled": true}
		report.cases.append(result)
		print("WORLD_EDITOR_BENCH ", scenario, " ", JSON.stringify(result.summary))
		var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	world.free()
	await process_frame
	quit()
