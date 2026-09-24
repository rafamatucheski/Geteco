extends SceneTree

## Perfil renderizado e isolado do caminho regional real do RanchSingle:
## recurso já carregado -> _prepare_model_template -> captura em _models ->
## nova instância restaurada -> rig -> gate de batching -> primeira apresentação.

const MODEL_PATH := "res://prototypes/living_cast/models/RanchSingleModel.gd"
const GEOMETRY_CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const WHEEL_CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0
const REGIONAL_SLICE_BUDGET_MS := 6.0
const EXPECTED_WHEELS := 4
const EXPECTED_SIGNATURE := 2058053124

var failures: Array[String] = []
var stage: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("RanchSingle regional profile requires a rendered display")
		quit(2)
		return
	stage = Node3D.new()
	stage.name = "RanchSingleRegionalPipelineProfile"
	root.add_child(stage)
	current_scene = stage
	for _frame in 3:
		await process_frame

	var renderer_bootstrap_ms := await _warm_renderer()
	var viewport := _make_vehicle_viewport()
	var started := Time.get_ticks_usec()
	var script := load(MODEL_PATH) as Script
	var resource_load_ms := _elapsed_ms(started)
	_check(script != null, "RanchSingle resource loads")
	if script == null:
		_finish({"resource_load_ms": resource_load_ms})
		return

	_reset_model_cache()
	_reset_pipeline_caches()
	var misses_before := GEOMETRY_CACHE.misses
	var cold_builds_before := GEOMETRY_CACHE.cold_builds
	var captures_before := GEOMETRY_CACHE.prepared_template_captures
	started = Time.get_ticks_usec()
	var prewarm: Dictionary = GEOMETRY_CACHE._prepare_model_template(MODEL_PATH, viewport, script)
	var prewarm_ms := _elapsed_ms(started)
	_check(prewarm_ms < REGIONAL_SLICE_BUDGET_MS, "RanchSingle regional prewarm must fit the %.2f ms scheduler slice, got %.3f ms" % [REGIONAL_SLICE_BUDGET_MS, prewarm_ms])
	_check(GEOMETRY_CACHE.misses == misses_before + 1, "Regional prewarm starts from one real cache miss")
	_check(GEOMETRY_CACHE.cold_builds == cold_builds_before + 1, "Regional prewarm performs one cold RanchSingle build")
	_check(bool(prewarm.get("model_ready", false)), "Regional prewarm enters the RanchSingle in the warmup tree")
	_check(bool(prewarm.get("wheel_mounted", false)), "Regional prewarm mounts authored RanchSingle wheels")
	_check(bool(prewarm.get("captured", false)), "Regional prewarm captures the final presentation template")
	_check(GEOMETRY_CACHE.prepared_template_captures == captures_before + 1, "Regional prewarm records one prepared capture")
	_check(GEOMETRY_CACHE._models.has(MODEL_PATH), "Regional prewarm publishes RanchSingle in _models")
	if GEOMETRY_CACHE._models.has(MODEL_PATH):
		_check(bool(GEOMETRY_CACHE._models[MODEL_PATH].get("prepared_presentation", false)), "RanchSingle cache entry is presentation-ready")

	# Flush the warmup request after _prepare_model_template has freed its model.
	# No first model remains resident when the gameplay instance is measured.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var post_prewarm := await _profile_cached_gameplay_instance(viewport, script, _capture_path())
	var report := {
		"kind": "rendered",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"frame_budget_ms": FRAME_BUDGET_MS,
		"regional_slice_budget_ms": REGIONAL_SLICE_BUDGET_MS,
		"renderer_bootstrap_ms": renderer_bootstrap_ms,
		"resource_load_ms": resource_load_ms,
		"prewarm_ms": prewarm_ms,
		"prewarm": prewarm,
		"post_prewarm": post_prewarm,
		"capture": _capture_path(),
	}
	viewport.free()
	_finish(report)


func _profile_cached_gameplay_instance(viewport: SubViewport, script: Script, capture_path: String) -> Dictionary:
	var hits_before := GEOMETRY_CACHE.hits
	var clearance_hits_before := WHEEL_CLEARANCE.prepared_hits
	var started := Time.get_ticks_usec()
	var model := script.new() as Node3D
	var constructor_restore_ms := _elapsed_ms(started)
	_check(model != null, "Cached RanchSingle constructs")
	if model == null:
		return {}
	model.set_meta("ranch_profile_model", true)
	started = Time.get_ticks_usec()
	viewport.add_child(model)
	var add_to_tree_ms := _elapsed_ms(started)
	_check(GEOMETRY_CACHE.hits == hits_before + 1, "Gameplay RanchSingle restores from VehicleGeometryCache._models")
	_check(bool(model.get_meta("vehicle_mesh_batched", false)), "Restored RanchSingle remains presentation-ready")

	var wheel_centres := _wheel_centres(model)
	started = Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var mounted: bool = rig.mount(model)
	var wheel_mount_ms := _elapsed_ms(started)
	_check(mounted and rig.pivots.size() == EXPECTED_WHEELS, "Cached RanchSingle remounts four articulated wheels")
	_check(wheel_centres.size() == EXPECTED_WHEELS, "Cached RanchSingle preserves four authored wheel centres")
	_check(WHEEL_CLEARANCE.prepared_hits == clearance_hits_before + 1, "Cached RanchSingle reuses prepared wheel clearance")

	started = Time.get_ticks_usec()
	var batched_removed := 0
	if not bool(model.get_meta("vehicle_mesh_batched", false)):
		batched_removed = MESH_BATCHER.batch_model(model)
		model.set_meta("vehicle_mesh_batched", true)
	var mesh_batch_ms := _elapsed_ms(started)
	_check(batched_removed == 0, "Cached RanchSingle performs no runtime rebatch")

	var visual_signature := _visual_signature(model)
	_check(visual_signature == EXPECTED_SIGNATURE, "Cache-restored RanchSingle preserves the exact visual signature")
	var meshes := _mesh_count(model)
	var triangles := _triangle_count(model)
	started = Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var first_presented_ms := _elapsed_ms(started)
	var model_pipeline_ms := constructor_restore_ms + add_to_tree_ms + wheel_mount_ms + mesh_batch_ms + first_presented_ms
	_check(model_pipeline_ms < FRAME_BUDGET_MS, "Cache-restored RanchSingle pipeline stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, model_pipeline_ms])

	if not capture_path.is_empty():
		for _frame in 2:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var save_error := viewport.get_texture().get_image().save_png(capture_path)
		_check(save_error == OK, "Cached RanchSingle visual capture saves")

	return {
		"constructor_restore_ms": constructor_restore_ms,
		"add_to_tree_ms": add_to_tree_ms,
		"wheel_mount_ms": wheel_mount_ms,
		"mesh_batch_ms": mesh_batch_ms,
		"batched_nodes_removed": batched_removed,
		"first_presented_ms": first_presented_ms,
		"model_pipeline_ms": model_pipeline_ms,
		"cache_hit": GEOMETRY_CACHE.hits == hits_before + 1,
		"wheel_centres": wheel_centres.size(),
		"meshes": meshes,
		"triangles": triangles,
		"visual_signature": visual_signature,
	}


func _reset_model_cache() -> void:
	GEOMETRY_CACHE._models.erase(MODEL_PATH)
	GEOMETRY_CACHE._prepared.erase(MODEL_PATH)
	GEOMETRY_CACHE._miss_started_usec.erase(MODEL_PATH)


func _reset_pipeline_caches() -> void:
	WHEEL_CLEARANCE._cache.clear()
	WHEEL_CLEARANCE._content_keys.clear()
	MESH_BATCHER._mesh_cache.clear()
	MESH_BATCHER._format_cache.clear()
	MESH_BATCHER._primitive_formats.clear()


func _warm_renderer() -> float:
	var viewport := SubViewport.new()
	viewport.name = "RanchSingleRendererBootstrap"
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8797a1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.85
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	viewport.add_child(light)
	var sample := MeshInstance3D.new()
	sample.mesh = BoxMesh.new()
	viewport.add_child(sample)
	var started := Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var elapsed := _elapsed_ms(started)
	viewport.free()
	await process_frame
	return elapsed


func _make_vehicle_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "RanchSingleVisualReview"
	viewport.size = Vector2i(720, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	stage.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8c9aa3")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff7e8")
	environment.environment.ambient_light_energy = 0.9
	viewport.add_child(environment)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12.0, 12.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("56646b")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	viewport.add_child(ground)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	key.light_color = Color("fff1d6")
	key.light_energy = 1.35
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 3.2, -2.0)
	fill.omni_range = 9.0
	fill.light_color = Color("b9d8ff")
	fill.light_energy = 0.7
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(5.9, 4.0, -7.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.75, 0.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	viewport.add_child(camera)
	return viewport


func _capture_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			return argument.trim_prefix("capture=")
	return "D:/geteco/game/_codex_diag/ranch-single-regional.png"


func _wheel_centres(model: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for child in model.get_children():
		if child.has_meta("wheel_center"):
			var centre: Vector3 = child.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	return centres


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _triangle_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in node.get_children():
		count += _triangle_count(child)
	return count


func _visual_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_visual(model, model, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_visual(model: Node3D, node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := _material_key(model, part.get_active_material(surface_index))
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
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_visual(model, child, world_transform, entries)


func _material_key(model: Node3D, material: Material) -> String:
	var materials: Dictionary = model.get("materials")
	for key in materials:
		if materials[key] == material:
			return String(key)
	return "unknown"


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("RANCH_SINGLE_REGIONAL_PIPELINE ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
