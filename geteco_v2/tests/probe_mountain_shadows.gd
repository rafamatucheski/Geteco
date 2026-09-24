extends SceneTree

## Real Main scene, no save. Captures a fixed mountain village view with the
## directional shadow enabled and disabled. --benchmark also measures 30 s.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var out_dir := ""
var world

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Mountain shadow probe requires rendered --no-save")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		push_error("Mountain shadow probe requires an existing --out-dir")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
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
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	var site := "village"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--site="): site = arg.trim_prefix("--site=")
	var source_point := Vector2(7625, -1555)
	if site == "sawmill": source_point = Vector2(6350, 560)
	elif site == "lodge": source_point = Vector2(7140, -2760)
	var focus: Vector3 = CATALOG._at(source_point, "mountain")
	world.production.set_process(false)
	world.production._update_physical_residency(focus)
	world.player.set_physics_process(false)
	world.player.teleport(focus + Vector3.UP * 0.8)
	world.production._update_logical_region(focus)
	world.production.region.set_focus(focus)
	print("MOUNTAIN_FOCUS_INITIAL ", world.production.region.region_id, " cell=", world.production.region.current_cell, " physical=", world.production._physical_focus(), " driving=", world.driving.occupied)
	world.camera.heading = 0
	world.camera.target_size = 30
	world.camera.focus = focus
	world.camera.initialized = true
	world.camera.locked = true
	world.camera.set_process(false)
	world.camera.global_position = focus + Vector3(0, 29, 19)
	world.camera.look_at(focus)
	world.camera.size = 30
	world.camera.make_current()
	world.hud.hide()
	for frame in 600:
		await process_frame
		if world.production.region.pending.is_empty(): break
	var weather = world.session.weather
	weather.time_of_day = 0.50
	weather.weather_state = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="): weather.time_of_day = float(arg.trim_prefix("--time="))
	weather._update()
	var atmosphere: Environment = world.production.environment.environment
	print("MOUNTAIN_FOG ", atmosphere.fog_enabled, " density=", atmosphere.fog_density, " begin=", atmosphere.fog_depth_begin, " end=", atmosphere.fog_depth_end)
	if "--no-fog" in OS.get_cmdline_user_args(): atmosphere.fog_enabled = false
	for frame in 45: await process_frame
	print("MOUNTAIN_PLAYER ", world.player.global_position, " health=", world.gameplay.health, " chunks=", world.production.region.chunks.size(), " villages=", world.production.region.find_children("MountainVillage3D", "Node3D", true, false).size())
	var region = world.production.region
	print("MOUNTAIN_CELL ", region.current_cell, " records=", region.records.get(region.current_cell, []).map(func(item): return item.kind))
	if is_instance_valid(world.session.death_presentation): world.session.death_presentation.hide()
	weather.set_process(false)
	var city_look: Node = world.get_node_or_null("CityLook")
	if city_look != null: city_look.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sun-x="): world.production.sun.rotation_degrees.x = float(arg.trim_prefix("--sun-x="))
		if arg.begins_with("--sun-y="): world.production.sun.rotation_degrees.y = float(arg.trim_prefix("--sun-y="))
	var contacts: Array[Node] = world.production.region.find_children("Mountain*Contact*", "MeshInstance3D", true, false)
	print("MOUNTAIN_CONTACTS ", contacts.size())
	if "--hide-contact" in OS.get_cmdline_user_args():
		for contact in contacts: contact.hide()
	var sun: DirectionalLight3D = world.production.sun
	var terrain_count := 0
	for child in world.production.region.find_children("*", "MeshInstance3D", true, false):
		if child.name == "MountainTerrain": terrain_count += 1
	print("MOUNTAIN_SHADOW_SETUP ", JSON.stringify({"region":world.session.state.region_id,"focus":focus,"sun_rotation":sun.rotation_degrees,"sun_mask":sun.light_cull_mask,"terrain_meshes":terrain_count,"contact_meshes":contacts.size(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":root.size}))
	var on_image := await _shot("mountain-shadow-on")
	sun.shadow_enabled = false
	var off_image := await _shot("mountain-shadow-off")
	var samples := 0
	var darkened := 0
	for y in range(280, 580, 2):
		for x in range(160, 1120, 2):
			var on: Color = on_image.get_pixel(x, y)
			var off: Color = off_image.get_pixel(x, y)
			if (off.r + off.g + off.b - on.r - on.g - on.b) / 3.0 > 0.04: darkened += 1
			samples += 1
	var coverage := float(darkened) / float(samples)
	print("MOUNTAIN_SHADOW_COVERAGE ", JSON.stringify({"darkened_ratio":coverage,"samples":samples}))
	if "--assert-shadows" in OS.get_cmdline_user_args() and (world.session.state.region_id != "mountain" or terrain_count < 9 or contacts.size() < 18 or coverage < 0.15 or absf(sun.rotation_degrees.x + 42.0) > 0.5 or absf(sun.rotation_degrees.y + 135.0) > 0.5):
		push_error("Mountain buildings do not cast the intended visible shadows")
		quit(1)
		return
	quit(0)

func _shot(label: String) -> Image:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image_value := root.get_texture().get_image()
	var path := out_dir.path_join(label + ".png")
	var result := image_value.save_png(path)
	print("MOUNTAIN_SHADOW_SHOT ", label, " ", path, " ", result)
	return image_value
