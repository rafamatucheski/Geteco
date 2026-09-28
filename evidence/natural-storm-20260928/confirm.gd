extends "res://tests/measure/measure.gd"
## Same production scene and seeded conditions before/after. Never writes saves.
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	seed(22092026)
	var variant := "before"
	var only := ""
	var folder := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=").validate_filename()
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
	if folder.is_empty(): folder = ProjectSettings.globalize_path("res://evidence/atmosphere-"+variant)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("Cannot create atmosphere evidence directory: "+folder)
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session != null and world.session.weather != null: break
	if world.session == null or world.session.weather == null: quit(1); return
	# Keep the original source as evidence and swap only this process's instance.
	# This permits an A/B run on the same current city without rewriting runtime files.
	if "--original-weather" in OS.get_cmdline_user_args():
		var previous_weather = world.session.weather
		world.remove_child(previous_weather)
		previous_weather.free()
		var original = load("res://evidence/natural-storm-20260928/Weather.before.gd").new()
		original.controller = world.production
		world.session.weather = original
		world.add_child(original)
	world.player.controlled_automatically = true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	world.session.cold.set_process(false)
	var cases := [
		["port-day",Vector3(243.75,.08,237.5),.36,0,0.0],
		["port-sunset",Vector3(243.75,.08,237.5),.75,0,0.0],
		["street-night",Vector3(77.875,.08,96.2375),.84,0,0.0],
		["street-rain",Vector3(77.875,.08,96.2375),.36,1,0.0],
		["storm-day",Vector3(77.875,.08,96.2375),.50,2,0.0],
		["street-storm",Vector3(77.875,.08,96.2375),.90,2,0.0],
		["cemetery",Vector3(-40.625,.08,108.75),.36,0,0.0],
		["cemetery-night",Vector3(-40.625,.08,108.75),.90,0,0.0],
		["bridge",Vector3(452,.08,-285),.36,0,0.0],
		["forest",Vector3(640,.08,-267),.36,0,0.0],
		["resort-snow",Vector3(718,.08,-479),.36,0,120.0],
	]
	var report := {"gpu":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"seed":22092026,"cases":[]}
	if "--ab-weather" in OS.get_cmdline_user_args():
		var paired := []
		for entry in cases:
			if not only.is_empty() and entry[0] not in only.split(","): continue
			for phase in ["after","before"]:
				var pair: Array = entry.duplicate()
				pair[0] += "-"+phase
				pair.append(phase)
				paired.append(pair)
		cases = paired
		only = ""
	for entry in cases:
		if not only.is_empty() and entry[0] not in only.split(","): continue
		if entry.size()>5:
			var old = world.session.weather
			world.remove_child(old)
			old.free()
			var path := "res://evidence/natural-storm-20260928/Weather.before.gd" if entry[5]=="before" else "res://runtime/Weather.gd"
			var replacement = load(path).new()
			replacement.controller = world.production
			world.session.weather = replacement
			world.add_child(replacement)
		world.player.teleport(entry[1])
		world.production._update_physical_residency(entry[1])
		world.production._update_logical_region(entry[1])
		world.camera.target_size = 32
		world.camera.heading = 0
		world.camera.initialized = false
		world.session.weather.time_of_day = entry[2]
		world.session.weather.weather_state = entry[3]
		world.session.weather.weather_timer = 10000
		world.session.cold.model.weather_clock = entry[4]
		world.session.weather._update()
		if world.session.weather.get("storm")!=null:
			world.session.weather.storm.lightning_timer = 10.0
		var warm: Array[float] = []
		var measured: Array[float] = []
		var last := Time.get_ticks_usec()
		var begin := last
		while Time.get_ticks_usec()-begin < 8000000:
			await process_frame
			var now := Time.get_ticks_usec()
			warm.append((now-last)/1000.0)
			last = now
		begin = last
		while Time.get_ticks_usec()-begin < 30000000:
			await process_frame
			var now := Time.get_ticks_usec()
			measured.append((now-last)/1000.0)
			last = now
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(folder+"/"+entry[0]+".png") != OK:
			push_error("Cannot save atmosphere capture: "+folder)
			quit(2)
			return
		var result := {"id":entry[0],"position":str(world.player.position),"population":world.people.size(),"summary":stats(measured),"warmup":stats(warm),"frames_ms":measured,"warmup_ms":warm}
		report.cases.append(result)
		print("ATMOSPHERE ",entry[0]," ",JSON.stringify(result.summary))
		var file := FileAccess.open(folder+"/report.json",FileAccess.WRITE)
		if file == null:
			push_error("Cannot save atmosphere report: "+folder)
			quit(2)
			return
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	world.queue_free()
	await process_frame
	quit()


