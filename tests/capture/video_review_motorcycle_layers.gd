extends "res://tests/capture/video_review_silhouette.gd"
## Isolate player and motorcycle overlays on the same rendered fixture.
var sampled_mount := false

func run() -> void:
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	capture_prefix = "layers-"
	report_filename = "layers-captures.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="): capture_prefix = arg.trim_prefix("--capture-prefix=")
		if arg.begins_with("--capture-report="): report_filename = arg.trim_prefix("--capture-report=")
	silhouette_ablation = true
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_dispatch", true)
	root.add_child(world)
	current_scene = world
	for frame in 4800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		failures.append("Main failed to start")
		await finish()
		return
	print("MOTORCYCLE_LAYERS Main loaded")
	await wait_startup_curtain()
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .45
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 99999.0
	world.camera.target_size = 8.0
	world.camera.size = 8.0
	await motorcycle_theft()
	await finish()

func wait_body_transition() -> bool:
	if sampled_mount or not world.driving.occupied: return await super.wait_body_transition()
	var city: Node = world.get_node("CityLook")
	var primed_hidden_bounds := false
	for frame in 240:
		await physics_frame
		if world.driving.is_body_transition_active():
			if not world.player.visible and not primed_hidden_bounds:
				city._refresh_silhouette()
				primed_hidden_bounds = true
				records.append({"refresh_phase_fixture": "refresh while boarding actor hidden", "player_visible": world.player.visible})
			# Deterministically cover a 4-Hz refresh immediately before boarding
			# finishes. Context refreshes still run normally in CityLook.
			if primed_hidden_bounds: city._clock = 0.0
			continue
		sampled_mount = true
		if not primed_hidden_bounds: failures.append("hidden boarding phase was not observed")
		city._clock = 0.0
		await capture_mount_first_frames()
		return true
	failures.append("body transition did not finish")
	return false

func capture_mount_first_frames() -> void:
	var start := Time.get_ticks_usec()
	var samples: Array[Dictionary] = []
	for target_seconds in [0.0, .1, .3]:
		while true:
			await process_frame
			await RenderingServer.frame_post_draw
			if float(Time.get_ticks_usec() - start) / 1000000.0 >= target_seconds: break
		var mesh: MeshInstance3D = world.player.visual.find_child("Mesh0", true, false)
		var material: ShaderMaterial = mesh.material_overlay
		var label := capture_prefix + "mounted-frame-%03d" % int(target_seconds * 1000)
		var box_min: Vector3 = material.get_shader_parameter("box_min")
		var box_max: Vector3 = material.get_shader_parameter("box_max")
		var inverse: Projection = material.get_shader_parameter("target_inverse")
		var position_in_box := (Transform3D(inverse) * mesh.global_transform) * mesh.get_aabb()
		var contains_mesh := AABB(box_min, box_max - box_min).encloses(position_in_box)
		if not contains_mesh: failures.append("stale mounted box: " + label)
		records.append({"label": label, "elapsed_ms": float(Time.get_ticks_usec() - start) / 1000.0, "player_visible": world.player.visible, "box_min": str(box_min), "box_max": str(box_max), "mounted_mesh_bounds": str(position_in_box), "box_encloses_mounted_mesh": contains_mesh})
		samples.append({"label": label, "image": root.get_texture().get_image()})
	for sample in samples:
		var error: Error = sample.image.save_png(OUTPUT + sample.label + ".png")
		if error != OK: failures.append("capture: " + sample.label)

func capture_without_silhouette(label: String) -> void:
	if label == "motorcycle-without-silhouette":
		dump_targets()
		var camera_processing: bool = world.camera.is_processing()
		world.camera.set_process(false)
		await remove_one_overlay(world.player, "motorcycle-player-overlay-removed")
		await remove_one_overlay(world.driving.car, "motorcycle-bike-overlay-removed")
		await super.capture_without_silhouette(label)
		world.camera.set_process(camera_processing)
		await mounted_building_control()
	else:
		await super.capture_without_silhouette(label)

func remove_one_overlay(target: Node3D, label: String) -> void:
	var city: Node = world.get_node("CityLook")
	var was_processing := city.is_processing()
	city.set_process(false)
	var removed: Array[Dictionary] = []
	for geometry in target.find_children("*", "GeometryInstance3D", true, false):
		var material = geometry.material_overlay
		if material is ShaderMaterial and material.shader == preload("res://world/city_look/occluded_silhouette.gdshader"):
			removed.append({"geometry": geometry, "material": material})
			geometry.material_overlay = null
	await capture(label)
	for item in removed:
		if is_instance_valid(item.geometry): item.geometry.material_overlay = item.material
	city.set_process(was_processing)

func dump_targets() -> void:
	for target in [world.player, world.driving.car]:
		var data := {"diagnostic_target": str(target), "transform": str(target.global_transform), "geometry": []}
		for geometry in target.find_children("*", "GeometryInstance3D", true, false):
			if not geometry.is_visible_in_tree(): continue
			var material = geometry.material_overlay
			var item := {"path": str(target.get_path_to(geometry)), "transform": str(geometry.global_transform), "aabb": str(geometry.get_aabb())}
			if material is ShaderMaterial and material.shader == preload("res://world/city_look/occluded_silhouette.gdshader"):
				item["box_min"] = str(material.get_shader_parameter("box_min"))
				item["box_max"] = str(material.get_shader_parameter("box_max"))
				item["target_inverse"] = str(material.get_shader_parameter("target_inverse"))
			data.geometry.append(item)
		records.append(data)
		print("MOTORCYCLE_LAYER_DUMP ", JSON.stringify(data))

func mounted_building_control() -> void:
	var bike: Node3D = world.driving.car
	var saved_transform := bike.global_transform
	var point: Vector3 = world.maciota_place.exterior_origin + Vector3(0, .08, .8)
	if not world.session.position_clear(point):
		failures.append("mounted visual control player anchor unavailable")
		return
	# Same real facade as the on-foot positive control. The vehicle fixture is
	# fixed; this checks rendering only, not clearance or driving at this pose.
	bike.global_position = Vector3(point.x, saved_transform.origin.y, point.z)
	await frames(4)
	world.camera.initialized = false
	world.camera._process(1.0)
	await frames(12)
	await capture("mounted-behind-building")
	await super.capture_without_silhouette("mounted-behind-building-without-silhouette")
	bike.global_transform = saved_transform
	await frames(4)
	world.camera.initialized = false
	world.camera._process(1.0)
