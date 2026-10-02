extends "res://tests/measure/review_mountain_shops.gd"
## Same real Main scene, fixed diagnostic views around each building.
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var tag := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	folder = "res://evidence/mountain-neighbors-20261002/"+tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	world.camera.locked = true
	for id in ["ski_lodge", "mountain_cabin_village_3", "mountain_boutique"]:
		var data: Dictionary = CATALOG.get_definition(id)
		world.player.teleport(data.entry_position+Vector3(0,.08,1))
		world.production._update_physical_residency(data.entry_position)
		world.production._update_logical_region(data.entry_position)
		world.production.region.set_focus(data.entry_position)
		await frames(240)
		var point: Vector3 = data.exterior_position+Vector3(0,1,0)
		world.camera.size = 23 if id == "ski_lodge" else 12
		for view in [Vector3(15,16,15),Vector3(-15,16,15),Vector3(15,16,-15),Vector3(-15,16,-15)]:
			world.camera.global_position = point+view
			world.camera.look_at(point)
			await frames(6)
			await shot(id+"-"+str(view.x)+"-"+str(view.z))
		if "--visual-only" not in OS.get_cmdline_user_args(): await measure(id)
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"rows":rows,"scope":"Real Main with diagnostic fixed camera, live world; 24 requested population; no saves."},"\t"))
	quit()
