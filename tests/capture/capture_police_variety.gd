extends "res://tests/capture/video_review_interiors.gd"
## Ten production officers in Main. Staged poses, ambient city active; 30 s samples.
var output_dir := "res://evidence/police-variety-20261002/before"
var officers: Array = []

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(150.0).timeout.connect(func(): quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	seed(7193)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(2); return
	await wait_startup_curtain()
	world.gameplay.set_physics_process(false)
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	var center: Vector3 = world.player.global_position
	world.player.teleport(center + Vector3(0, 0, 5))
	preload("res://gameplay/PoliceAppearance.gd").next_model = 0
	for index in 10:
		var officer = preload("res://gameplay/PoliceAgent.gd").new()
		officer.position = center + Vector3((index % 5 - 2) * 1.15, .03, -float(index / 5) * 2.3)
		world.add_child(officer)
		officer.set_physics_process(false)
		officer.visual.rotation.y = PI - .3
		officers.append(officer)
	await frames(10)
	if "--fit-review" in OS.get_cmdline_user_args():
		for officer in officers: officer.hide()
		for index in [0, 2, 5]:
			var officer = officers[index]
			officer.global_position = center + Vector3(0, .03, 2.0)
			officer.visual.body.teleported()
			officer.reset_physics_interpolation()
			officer.show()
			for mode in ["rest", "aim"]:
				officer.visual.update_pose(1.0, mode == "aim", false, 0.0, 0.0)
				await frames(20)
				var focus: Vector3 = officer.visual.body.head_node.global_position + Vector3.UP * .13
				world.camera.global_position = focus + Vector3(.6, .5, 1.2)
				world.camera.look_at(focus)
				world.camera.size = .7
				await photo("head-%d-%s" % [index, mode])
				focus = officer.visual.weapon.to_global(preload("res://gameplay/WeaponPoseData.gd").GRIPS.pistol)
				world.camera.global_position = focus + Vector3(-.5, .3, .8)
				world.camera.look_at(focus)
				world.camera.size = .65
				await photo("hand-%d-%s" % [index, mode])
				print("FIT ", index, " ", mode, " error=", focus.distance_to(officer.visual.body.forearms[0].to_global(Vector3(0, -.31, 0))))
				for step in 45:
					await physics_frame
					officer.position.x += .018
					officer.visual.update_pose(1.0 / 60.0, mode == "aim", false, 0.0, 0.0)
					if step in [10, 25, 40]:
						focus = officer.visual.weapon.to_global(preload("res://gameplay/WeaponPoseData.gd").GRIPS.pistol)
						world.camera.global_position = focus + Vector3(-.5, .3, .8)
						world.camera.look_at(focus)
						await photo("moving-%d-%s-%d" % [index, mode, step])
			officer.hide()
		quit(0)
		return
	world.camera.global_position = center + Vector3(0, 8, 12)
	world.camera.look_at(center + Vector3(0, .7, -1))
	world.camera.size = 8.7
	await photo("lineup")
	for index in [0, 2, 5, 6]:
		var focus: Vector3 = officers[index].global_position + Vector3.UP * .9
		world.camera.global_position = focus + Vector3(2.4, 1.1, 4.5)
		world.camera.look_at(focus)
		world.camera.size = 2.4
		await photo("profile-%d" % index)
	world.camera.global_position = center + Vector3(0, 8, 12)
	world.camera.look_at(center + Vector3(0, .7, -1))
	world.camera.size = 8.7
	for officer in officers: officer.visual.update_pose(1.0, true, false, 0.0, 0.0)
	await frames(5)
	await photo("aiming")
	await create_timer(5.0).timeout
	var samples: Array[float] = []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec() - began < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var slow := 0
	var very_slow := 0
	for value in samples:
		total += value
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	var report := {"frames": samples.size(), "seconds": total / 1000.0, "fps": samples.size() * 1000.0 / total, "p50": sorted[int(sorted.size() * .50)], "p95": sorted[int(sorted.size() * .95)], "p99": sorted[int(sorted.size() * .99)], "max": sorted[-1], "over_33": slow, "over_66": very_slow, "samples": samples, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "resolution": str(root.size), "fps_limit": Engine.max_fps, "vsync": DisplayServer.window_get_vsync_mode(), "failures": failures}
	FileAccess.open(output_dir + "/metrics.json", FileAccess.WRITE).store_string(JSON.stringify(report))
	report.erase("samples")
	print("POLICE_VARIETY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func photo(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output_dir + "/" + label + ".png") != OK: failures.append(label)
