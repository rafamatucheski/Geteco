extends SceneTree

## Rendered shadow A/B in the actual Main scene. Does not load or write a save.

var out_dir := ""
var world

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Rendered probe requires --no-save")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): out_dir = arg.trim_prefix("--out-dir=")
	if out_dir.is_empty() or not DirAccess.dir_exists_absolute(out_dir):
		push_error("Probe requires an existing --out-dir")
		quit(2)
	await _run_scene()

func _run_scene() -> void:
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	world.set_meta("skip_traffic_yield", true)
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 1200:
		await physics_frame
		if world.production != null and world.production.ready_for_play: break
	if world.production == null or not world.production.ready_for_play:
		push_error("Production world did not start")
		quit(1)
		return
	world.set_population(0)
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.diagnostic_label.hide()
	var focus := Vector3(1030.0 / 16.0, 0.08, 1200.0 / 16.0)
	world.production._update_physical_residency(focus)
	world.player.teleport(focus)
	world.camera.heading = 0
	world.camera.target_size = 26
	world.camera.focus = focus
	world.camera.initialized = true
	world.camera.locked = true
	world.camera.set_process(false)
	world.camera.global_position = focus + Vector3(0, 25.3, 25.3)
	world.camera.look_at(focus)
	world.camera.size = 26
	world.camera.make_current()
	world.hud.hide()
	for frame in 600:
		await process_frame
		if world.production.region.pending.is_empty(): break
	var weather = world.session.weather
	weather.time_of_day = 0.50
	weather.weather_state = 0
	weather._update()
	for frame in 12: await process_frame
	for frame in 30: await process_frame
	weather.set_process(false)
	var city_look: Node = world.get_node_or_null("CityLook")
	if city_look != null: city_look.set_process(false)
	var sun: DirectionalLight3D = world.production.sun
	var ground := []
	var road_count := 0
	var road_normals_ok := true
	for mesh in world.production.region.find_children("*", "MeshInstance3D", true, false):
		if not mesh.name.begins_with("HarborSurface_") and not mesh.name.begins_with("HarborRoad"): continue
		var mat := mesh.material_override as BaseMaterial3D
		if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			mat = mesh.mesh.surface_get_material(0) as BaseMaterial3D
		ground.append({"name":mesh.name,"layers":mesh.layers,"cull":mat.cull_mode if mat != null else -1,"unshaded":mat.shading_mode if mat != null else -1,"receive_disabled":mat.disable_receive_shadows if mat != null else false})
		if mesh.name.begins_with("HarborRoad"):
			road_count += 1
			var arrays: Array = mesh.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if normals.size() != vertices.size(): road_normals_ok = false
			else:
				for normal in normals:
					if normal.y < 0.99: road_normals_ok = false; break
	print("PRODUCTION_SHADOW_SETUP ", JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"sun_mask":sun.light_cull_mask,"sun_energy":sun.light_energy,"sun_rotation":sun.rotation_degrees,"sun_distance":sun.directional_shadow_max_distance,"camera":world.camera.global_position,"fog":world.production.environment.environment.fog_enabled,"ground":ground.slice(0,12)}))
	var on_image := await _shot("building-shadow-on")
	sun.shadow_enabled = false
	var off_image := await _shot("building-shadow-off")
	var sampled := 0
	var darkened := 0
	for y in range(350, 495, 2):
		for x in range(0, 880, 2):
			var on: Color = on_image.get_pixel(x, y)
			var off: Color = off_image.get_pixel(x, y)
			if (off.r + off.g + off.b - on.r - on.g - on.b) / 3.0 > 0.04: darkened += 1
			sampled += 1
	var coverage := float(darkened) / maxf(1.0, float(sampled))
	print("PRODUCTION_BUILDING_SHADOW_RESULT ", JSON.stringify({"road_meshes":road_count,"normals_up":road_normals_ok,"road_shadow_coverage":coverage,"samples":sampled}))
	if road_count == 0 or not road_normals_ok or coverage < 0.05:
		push_error("Building shadow does not cover the street in the production scene")
		quit(1)
		return
	quit(0)

func _shot(label: String) -> Image:
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(label + ".png")
	var picture := root.get_texture().get_image()
	var result := picture.save_png(path)
	print("PRODUCTION_SHADOW_SHOT ", label, " ", path, " ", result)
	return picture
