extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const CAPTURE_SIZE := Vector2i(640, 640)

var failures: Array[String] = []
var viewport: SubViewport
var camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("68717a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dbe4ec")
	environment.ambient_light_energy = 1.15
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.5
	viewport.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	key_light.light_energy = 1.3
	viewport.add_child(key_light)

	_reset_model_cache()
	var script := load(MODEL_PATH) as Script
	_check(script != null, "SnowPlow script loads for visual equivalence")
	if script == null:
		_finish({"error": "load_failed"})
		return

	var baked := script.new() as Node3D
	viewport.add_child(baked)
	var baked_rig := WHEEL_RIG.new()
	_check(baked_rig.mount(baked), "Baked SnowPlow mounts for visual comparison")
	if not bool(baked.get_meta("vehicle_mesh_batched", false)):
		BATCHER.batch_model(baked)

	# Rebuild the exact retained authoring source without changing runtime code.
	var authored := script.new() as Node3D
	for child in authored.get_children():
		authored.remove_child(child)
		child.free()
	authored.materials.clear()
	authored.paint = null
	authored._build_procedural_geometry()
	viewport.add_child(authored)
	var authored_rig := WHEEL_RIG.new()
	_check(authored_rig.mount(authored), "Authored SnowPlow mounts for visual comparison")
	BATCHER.batch_model(authored)

	_check(_visual_signature(authored) == _visual_signature(baked), "Baked and authored geometry have identical transformed triangle/material signatures")
	_check(_material_contract(authored) == _material_contract(baked), "Baked and authored material colors/roles match")
	_check(_bounds(authored).is_equal_approx(_bounds(baked)), "Baked and authored world bounds match")

	var out_dir := _output_dir()
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	var rows: Array[Dictionary] = []
	for view in [
		{"name": "front", "eye": Vector3(7.5, 4.3, -11.5), "target": Vector3(0.0, 0.85, -0.9)},
		{"name": "side", "eye": Vector3(11.5, 4.5, 1.0), "target": Vector3(0.0, 0.9, 0.0)},
	]:
		camera.look_at_from_position(view.eye, view.target, Vector3.UP)
		authored.show()
		baked.hide()
		var authored_image := await _capture()
		authored.hide()
		baked.show()
		var baked_image := await _capture()
		var difference := _image_difference(authored_image, baked_image)
		_check(float(difference.rms) <= 0.002, "%s baked render differs from authorship: RMS %.6f" % [view.name, difference.rms])
		rows.append({"view": view.name, "rms": difference.rms, "max": difference.max})
		if not out_dir.is_empty():
			_check(authored_image.save_png(out_dir.path_join("authored-%s.png" % view.name)) == OK, "%s authored capture saves" % view.name)
			_check(baked_image.save_png(out_dir.path_join("baked-%s.png" % view.name)) == OK, "%s baked capture saves" % view.name)

	baked.free()
	authored.free()
	_finish({
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"rows": rows,
	})


func _capture() -> Image:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _image_difference(a: Image, b: Image) -> Dictionary:
	var squared := 0.0
	var maximum := 0.0
	var samples := a.get_width() * a.get_height() * 3
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			for delta in [absf(ca.r - cb.r), absf(ca.g - cb.g), absf(ca.b - cb.b)]:
				squared += delta * delta
				maximum = maxf(maximum, delta)
	return {"rms": sqrt(squared / maxf(samples, 1.0)), "max": maximum}


func _material_contract(model: Node3D) -> Array[String]:
	var contract: Array[String] = []
	_collect_material_contract(model, contract)
	contract.sort()
	return contract


func _collect_material_contract(node: Node, contract: Array[String]) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		var color := material.albedo_color if material != null else Color.TRANSPARENT
		contract.append("%.6f,%.6f,%.6f,%.6f" % [color.r, color.g, color.b, color.a])
	for child in node.get_children():
		_collect_material_contract(child, contract)


func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mesh in meshes:
		var transformed := mesh.global_transform * mesh.mesh.get_aabb()
		if not initialized:
			result = transformed
			initialized = true
		else:
			result = result.merge(transformed)
	return result


func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)


func _visual_signature(model: Node3D) -> int:
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
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
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


func _reset_model_cache() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _output_dir() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("out_dir="):
			return argument.trim_prefix("out_dir=")
	return ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("SNOW_PLOW_BAKED_VISUAL_EQUIVALENCE ", JSON.stringify(result))
	if is_instance_valid(viewport):
		viewport.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
