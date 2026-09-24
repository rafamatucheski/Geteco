extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const SEDAN := preload("res://prototypes/living_cast/models/UnionSedanModel.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/UnionSedanModel.gd"
const ORIGINAL_GEOMETRY_SIGNATURE := 1216502398
const ORIGINAL_VISUAL_SIGNATURE := 1953729020

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A new process starts with the model-local primitive cache empty. Removing the
	# packed template makes this sample exercise the actual cold constructor.
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)

	var started := Time.get_ticks_usec()
	var cold: Node3D = SEDAN.new()
	var cold_new_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	root.add_child(cold)
	var cold_ready_usec := Time.get_ticks_usec() - started
	var cold_signature := _geometry_signature(cold)

	var hits_before := CACHE.hits
	started = Time.get_ticks_usec()
	var warm: Node3D = SEDAN.new()
	var warm_new_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	root.add_child(warm)
	var warm_ready_usec := Time.get_ticks_usec() - started

	check(CACHE.hits == hits_before + 1, "second Union Sedan restores from VehicleGeometryCache")
	check(cold_signature == ORIGINAL_GEOMETRY_SIGNATURE, "cold Union Sedan preserves the pre-optimization visual signature")
	check(_geometry_signature(warm) == cold_signature, "cached Union Sedan preserves exact 3D geometry, materials and transforms")
	check(_mesh_count(cold) >= 50, "cold Union Sedan keeps its detailed 3D presentation")
	check(_mesh_count(warm) == _mesh_count(cold), "cached Union Sedan keeps every visible 3D part")
	check(_unique_mesh_count(cold) <= 33, "repeated Union Sedan parts share immutable mesh resources")
	check(_wheel_centers(cold).size() == 4, "cold Union Sedan exposes four articulated wheel centers")
	check(_wheel_centers(warm).size() == 4, "cached Union Sedan preserves four articulated wheel centers")

	var cold_paint := cold.get("paint") as StandardMaterial3D
	var warm_paint := warm.get("paint") as StandardMaterial3D
	check(cold_paint != null and warm_paint != null, "both Union Sedans retain visible paint")
	if cold_paint != null and warm_paint != null:
		check(cold_paint != warm_paint, "cached Union Sedans own independent paint materials")
		var expected := warm_paint.albedo_color
		cold_paint.albedo_color = Color.MAGENTA
		check(warm_paint.albedo_color == expected, "repainting one Union Sedan cannot alter another")
		check(expected.v > 0.20 and expected.a > 0.99, "cached paint remains visible instead of becoming black")

	var rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
	check(rig.mount(warm), "cached Union Sedan remains mountable by the live wheel rig")
	check(rig.pivots.size() == 4 and rig.spinners.size() == 4, "live wheel rig mounts all four 3D wheels")

	# Mirror the real traffic presentation path. The triangle signature ignores
	# node grouping and ordering, so it proves that static mesh fusion changes
	# neither shape nor material assignment.
	var presentation: Node3D = SEDAN.new()
	root.add_child(presentation)
	var visual_signature_before := _visual_triangle_signature(presentation)
	check(visual_signature_before == ORIGINAL_VISUAL_SIGNATURE, "Union Sedan preserves the pre-optimization triangle/material signature")
	var presentation_rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
	check(presentation_rig.mount(presentation), "traffic presentation extracts the Union Sedan wheel rig")
	var visual_signature_mounted := _visual_triangle_signature(presentation)
	started = Time.get_ticks_usec()
	preload("res://cars/VehicleMeshBatcher.gd").batch_model(presentation)
	var batch_usec := Time.get_ticks_usec() - started
	var visual_signature_after := _visual_triangle_signature(presentation)
	check(visual_signature_after == visual_signature_mounted, "mesh batching preserves the mounted Union Sedan triangle/material signature")

	started = Time.get_ticks_usec()
	var hot_presentation: Node3D = SEDAN.new()
	root.add_child(hot_presentation)
	var hot_rig := preload("res://prototypes/living_cast/VehicleWheelRig.gd").new()
	check(hot_rig.mount(hot_presentation), "hot Union Sedan presentation extracts the live wheel rig")
	preload("res://cars/VehicleMeshBatcher.gd").batch_model(hot_presentation)
	var hot_presentation_usec := Time.get_ticks_usec() - started
	check(_visual_triangle_signature(hot_presentation) == visual_signature_after, "hot Union Sedan presentation matches the first fused presentation")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_render(cold, presentation)

	print("UNION_SEDAN_CACHE_RESULT cold_new_us=%d cold_ready_us=%d warm_new_us=%d warm_ready_us=%d cold_batch_us=%d hot_presentation_us=%d speedup=%.2f meshes=%d unique_meshes=%d signature=%d visual_signature=%d failures=%d" % [
		cold_new_usec,
		cold_ready_usec,
		warm_new_usec,
		warm_ready_usec,
		batch_usec,
		hot_presentation_usec,
		float(cold_new_usec + cold_ready_usec) / maxf(float(warm_new_usec + warm_ready_usec), 1.0),
		_mesh_count(cold),
		_unique_mesh_count(cold),
		cold_signature,
		visual_signature_before,
		failures.size(),
	])
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _capture_render(cold: Node3D, warm: Node3D) -> void:
	root.size = Vector2i(960, 540)
	RenderingServer.set_default_clear_color(Color("91a3af"))
	cold.hide()
	warm.position = Vector3.ZERO

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(4.2, 2.9, 5.6), Vector3(0.0, 0.72, 0.0), Vector3.UP)
	camera.fov = 38.0
	camera.make_current()

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	root.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 2.4, 2.0)
	fill.omni_range = 9.0
	fill.light_energy = 2.0
	root.add_child(fill)

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var capture_path := "res://_codex_diag/union-sedan-cache.png"
	var save_error := image.save_png(ProjectSettings.globalize_path(capture_path))
	check(save_error == OK, "rendered Union Sedan inspection image is saved")
	print("UNION_SEDAN_CACHE_CAPTURE path=%s error=%d" % [capture_path, save_error])


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and node.visible else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _unique_mesh_count(node: Node) -> int:
	var meshes := {}
	_collect_mesh_resources(node, meshes)
	return meshes.size()


func _collect_mesh_resources(node: Node, meshes: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes[(node as MeshInstance3D).mesh.get_instance_id()] = true
	for child in node.get_children():
		_collect_mesh_resources(child, meshes)


func _wheel_centers(model: Node3D) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for child in model.get_children():
		if child is MeshInstance3D and child.has_meta("wheel_center"):
			var center: Vector3 = child.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	return centers


func _geometry_signature(model: Node3D) -> int:
	var parts: Array = []
	_collect_geometry(model, Transform3D.IDENTITY, parts)
	return hash(parts)


func _visual_triangle_signature(model: Node3D) -> int:
	var triangles: Array[String] = []
	_collect_visual_triangles(model, Transform3D.IDENTITY, triangles)
	triangles.sort()
	return hash(triangles)


func _collect_visual_triangles(node: Node, parent_transform: Transform3D, triangles: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		var color := material.albedo_color if material != null else Color.TRANSPARENT
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					var point := world_transform * vertices[vertex_index]
					points.append("%.5f,%.5f,%.5f" % [point.x, point.y, point.z])
				points.sort()
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(child, world_transform, triangles)


func _collect_geometry(node: Node, parent_transform: Transform3D, parts: Array) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		parts.append([
			part.mesh.get_class() if part.mesh != null else "",
			part.mesh.get_aabb() if part.mesh != null else AABB(),
			world_transform,
			material.albedo_color if material != null else Color.TRANSPARENT,
			part.get_meta("wheel_center", Vector3.INF),
			part.get_meta("wheel_radius", 0.0),
			part.get_meta("wheel_spins", false),
		])
	for child in node.get_children():
		_collect_geometry(child, world_transform, parts)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
