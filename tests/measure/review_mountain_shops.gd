extends SceneTree
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const IDS := ["mountain_boutique", "mountain_village_outfitters", "mountain_outfitters"]
var world
var folder := "res://evidence/mountain-shops-20261002/before"
var rows: Array = []
var checks: Array = []
func _initialize() -> void: run.call_deferred()
func frames(n: int) -> void:
	for i in n: await process_frame
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
func walk_to(target: Vector3) -> bool:
	for i in 600:
		var offset: Vector3 = target-world.player.global_position
		offset.y = 0
		if offset.length() < .13:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false
func exercise(id: String) -> void:
	var room = world.session.room
	var service: Vector3 = room.interaction_points.service
	var aisle: Vector3 = room.to_global(Vector3(0,0,room.model.counter.y+1.15))
	var reached := await walk_to(aisle)
	reached = await walk_to(service) and reached
	await frames(30)
	await shot(id+"-counter")
	var staffed: bool = world.session.room_npcs.size() == 1
	var opened: bool = world.session.interact() and world.session.modal
	await frames(8)
	await shot(id+"-service")
	world.session.close_menu()
	checks.append({"id":id,"walk_to_counter":reached,"staff_spawned":staffed,"service_opened":opened})
	await walk_to(aisle)
	await walk_to(room.spawn_position)
func measure(label: String) -> void:
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in samples:
		total += value
		if value > 33.3: over33 += 1
		if value > 66.7: over66 += 1
	rows.append({"scene":label,"frames":samples.size(),"duration_ms":total,"fps":samples.size()*1000.0/total,"p50":sorted[int((sorted.size()-1)*.5)],"p95":sorted[int((sorted.size()-1)*.95)],"p99":sorted[int((sorted.size()-1)*.99)],"max":sorted[-1],"over33":over33,"over66":over66,"samples_ms":samples})
	print("SHOP_MEASURE ",label," ",rows[-1].fps)
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): folder = "res://evidence/mountain-shops-20261002/"+arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	for i in 4800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("Shop review could not start Main")
		quit(1)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	for id in IDS:
		var definition: Dictionary = CATALOG.get_definition(id)
		world.player.teleport(definition.entry_position + Vector3(0,.08,2))
		world.production._update_physical_residency(definition.entry_position)
		world.production._update_logical_region(definition.entry_position)
		world.production.region.set_focus(definition.entry_position)
		await frames(240)
		await shot(id+"-outside")
		if "--visual-only" not in OS.get_cmdline_user_args(): await measure(id+"-outside")
		if not await world.session.enter_place(id,false,id): push_error("Shop admission failed: "+id); quit(1); return
		await frames(120)
		await shot(id+"-inside")
		if "--visual-only" not in OS.get_cmdline_user_args(): await measure(id+"-inside")
		if "--exercise" in OS.get_cmdline_user_args(): await exercise(id)
		if not await world.session.leave_place(): push_error("Shop exit failed: "+id); quit(1); return
		if "--exercise" in OS.get_cmdline_user_args():
			checks[-1]["staff_cleaned"] = world.session.room_npcs.is_empty()
			checks[-1]["reentered"] = await world.session.enter_place(id,false,id)
			checks[-1]["single_staff_on_return"] = world.session.room_npcs.size() == 1
			await world.session.leave_place()
		await frames(30)
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":str(root.size),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"rows":rows,"checks":checks,"scope":"Real Main, static gameplay at each entrance/interior; setup teleports and direct admission; no save writes."},"\t"))
	var failed := false
	for result in checks:
		for key in result:
			if key != "id" and result[key] == false:
				push_error(str(result.id)+": "+str(key))
				failed = true
	quit(1 if failed else 0)
