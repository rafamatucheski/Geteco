extends SceneTree

## Rendered, isolated profile of the exact presentation pipeline used by
## VehicleGeometryCache._prepare_model_template(). The common renderer is warmed
## first and reported separately; model-specific work remains cold.

const MODEL_PATH := "res://prototypes/living_cast/BossMuscleModel.gd"
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const GEOMETRY_CACHE := preload("res://cars/VehicleGeometryCache.gd")
const WHEEL_CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0
const SURFACE_KEYS_META := &"boss_muscle_surface_material_keys"

var failures: Array[String] = []
var stage: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Boss Muscle pipeline profile requires a rendered display")
		quit(2)
		return
	stage = Node3D.new()
	stage.name = "BossMusclePipelineProfile"
	root.add_child(stage)
	current_scene = stage
	for _frame in 3:
		await process_frame

	var renderer_bootstrap_ms := await _warm_renderer()
	var viewport := _make_vehicle_viewport()
	var capture_path := _capture_path()
	_reset_model_cache()
	var cold := await _profile_instance(viewport, true, "")
	for child in viewport.get_children():
		if child.get_meta("profile_model", false):
			child.free()
	await process_frame
	_reset_model_cache()
	var script := load(MODEL_PATH) as Script
	_check(script != null, "Boss Muscle script remains loaded for cache prewarm")
	var prewarm_started := Time.get_ticks_usec()
	var captures_before := GEOMETRY_CACHE.prepared_template_captures
	var prewarm: Dictionary = GEOMETRY_CACHE._prepare_model_template(MODEL_PATH, viewport, script)
	var prewarm_ms := _elapsed_ms(prewarm_started)
	_check(bool(prewarm.get("captured", false)), "Boss Muscle prewarm captures a prepared presentation template")
	_check(bool(prewarm.get("wheel_mounted", false)), "Boss Muscle prewarm mounts four wheels before capture")
	_check(int(prewarm.get("batched_removed", -1)) == 0, "Baked Boss Muscle prewarm does not repeat mesh fusion")
	_check(GEOMETRY_CACHE.prepared_template_captures == captures_before + 1, "Boss Muscle prewarm records one prepared template capture")
	_check(GEOMETRY_CACHE._models.has(MODEL_PATH), "Boss Muscle prewarm publishes the model in VehicleGeometryCache._models")
	if GEOMETRY_CACHE._models.has(MODEL_PATH):
		_check(bool(GEOMETRY_CACHE._models[MODEL_PATH].get("prepared_presentation", false)), "Boss Muscle cache entry is presentation-ready")
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var warm := await _profile_cached_instance(viewport, script, capture_path)
	var report := {
		"kind": "rendered",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"frame_budget_ms": FRAME_BUDGET_MS,
		"renderer_bootstrap_ms": renderer_bootstrap_ms,
		"cold": cold,
		"prewarm_ms": prewarm_ms,
		"prewarm": prewarm,
		"post_prewarm": warm,
		"capture": capture_path,
		"failures": failures,
	}
	print("BOSS_MUSCLE_PIPELINE_PROFILE ", JSON.stringify(report))
	viewport.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _profile_instance(viewport: SubViewport, cold: bool, capture_path: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	var script := load(MODEL_PATH) as Script
	var resource_load_ms := _elapsed_ms(started)
	_check(script != null, "Boss Muscle script loads")
	if script == null:
		return {}

	started = Time.get_ticks_usec()
	var model := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	_check(model != null, "Boss Muscle constructs")
	if model == null:
		return {}
	model.set_meta("profile_model", true)
	started = Time.get_ticks_usec()
	viewport.add_child(model)
	var add_to_tree_ms := _elapsed_ms(started)
	var authored_wheel_centres := _wheel_centres(model)
	_check(authored_wheel_centres.size() == 4, "Boss Muscle exposes four authored wheel centres")

	started = Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var wheel_mounted: bool = rig.mount(model)
	var wheel_mount_ms := _elapsed_ms(started)
	_check(wheel_mounted and rig.pivots.size() == 4, "Boss Muscle mounts four articulated wheels")

	started = Time.get_ticks_usec()
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	var mesh_batch_ms := _elapsed_ms(started)
	var signature := _visual_signature(model)
	var meshes := _mesh_count(model)
	var triangles := _triangle_count(model)

	started = Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var first_presented_ms := _elapsed_ms(started)
	var construction_ms := constructor_ms + add_to_tree_ms
	var model_pipeline_ms := construction_ms + wheel_mount_ms + mesh_batch_ms + first_presented_ms
	if not cold:
		_check(model_pipeline_ms < FRAME_BUDGET_MS, "Post-prewarm Boss Muscle pipeline stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, model_pipeline_ms])

	if not capture_path.is_empty():
		for _frame in 2:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var save_error := viewport.get_texture().get_image().save_png(capture_path)
		_check(save_error == OK, "Boss Muscle visual capture saves")

	return {
		"resource_load_ms": resource_load_ms,
		"constructor_ms": constructor_ms,
		"add_to_tree_ms": add_to_tree_ms,
		"construction_ms": construction_ms,
		"wheel_marker_centres": authored_wheel_centres.size(),
		"wheel_mount_ms": wheel_mount_ms,
		"wheel_mounted": wheel_mounted,
		"mesh_batch_ms": mesh_batch_ms,
		"batched_nodes_removed": batched_removed,
		"first_presented_ms": first_presented_ms,
		"model_pipeline_ms": model_pipeline_ms,
		"cold_end_to_end_ms": resource_load_ms + model_pipeline_ms,
		"meshes": meshes,
		"triangles": triangles,
		"visual_signature": signature,
	}


func _profile_cached_instance(viewport: SubViewport, script: Script, capture_path: String) -> Dictionary:
	var hits_before := GEOMETRY_CACHE.hits
	var clearance_hits_before := WHEEL_CLEARANCE.prepared_hits
	var started := Time.get_ticks_usec()
	var model := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	_check(model != null, "Cached Boss Muscle constructs")
	if model == null:
		return {}
	model.set_meta("profile_model", true)
	started = Time.get_ticks_usec()
	viewport.add_child(model)
	var restore_add_to_tree_ms := _elapsed_ms(started)
	_check(GEOMETRY_CACHE.hits == hits_before + 1, "Gameplay Boss Muscle restores from VehicleGeometryCache._models")
	_check(bool(model.get_meta("vehicle_mesh_batched", false)), "Restored Boss Muscle remains presentation-ready")
	_check(model.get_meta("boss_muscle_geometry_source", &"") == &"prepared", "Restored Boss Muscle retains exact prepared geometry provenance")

	started = Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var wheel_mounted: bool = rig.mount(model)
	var wheel_mount_ms := _elapsed_ms(started)
	_check(wheel_mounted and rig.pivots.size() == 4, "Cached Boss Muscle remounts four articulated wheels")
	_check(WHEEL_CLEARANCE.prepared_hits == clearance_hits_before + 1, "Cached Boss Muscle reuses baked wheel clearance")

	started = Time.get_ticks_usec()
	var batched_removed := 0
	if not bool(model.get_meta("vehicle_mesh_batched", false)):
		batched_removed = MESH_BATCHER.batch_model(model)
		model.set_meta("vehicle_mesh_batched", true)
	var mesh_batch_ms := _elapsed_ms(started)
	_check(batched_removed == 0, "Cached Boss Muscle performs no runtime rebatch")

	started = Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var first_presented_ms := _elapsed_ms(started)
	var model_pipeline_ms := constructor_ms + restore_add_to_tree_ms + wheel_mount_ms + mesh_batch_ms + first_presented_ms
	_check(model_pipeline_ms < FRAME_BUDGET_MS, "Cache-restored Boss Muscle pipeline stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, model_pipeline_ms])
	var signature := _visual_signature(model)
	_check(signature == 3943922188, "Cache-restored Boss Muscle preserves the exact visual signature")
	_check(_mesh_count(model) == 10, "Cache-restored Boss Muscle preserves 10 operational mesh groups")
	_check(_triangle_count(model) == 26582, "Cache-restored Boss Muscle preserves 26,582 triangles")

	if not capture_path.is_empty():
		for _frame in 2:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var save_error := viewport.get_texture().get_image().save_png(capture_path)
		_check(save_error == OK, "Cache-restored Boss Muscle visual capture saves")

	return {
		"constructor_ms": constructor_ms,
		"restore_add_to_tree_ms": restore_add_to_tree_ms,
		"wheel_mount_ms": wheel_mount_ms,
		"mesh_batch_ms": mesh_batch_ms,
		"batched_nodes_removed": batched_removed,
		"first_presented_ms": first_presented_ms,
		"model_pipeline_ms": model_pipeline_ms,
		"cache_hit": GEOMETRY_CACHE.hits == hits_before + 1,
		"meshes": _mesh_count(model),
		"triangles": _triangle_count(model),
		"visual_signature": signature,
	}


func _reset_model_cache() -> void:
	GEOMETRY_CACHE._models.erase(MODEL_PATH)
	GEOMETRY_CACHE._prepared.erase(MODEL_PATH)
	GEOMETRY_CACHE._miss_started_usec.erase(MODEL_PATH)


func _warm_renderer() -> float:
	var viewport := SubViewport.new()
	viewport.name = "BossMuscleRendererBootstrap"
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
	var camera := Camera3D.new()
	camera.position = Vector3(4.0, 3.0, -5.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.6, 0.0))
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
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
	viewport.name = "BossMuscleVisualReview"
	viewport.size = Vector2i(720, 540)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	stage.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8797a1")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("f4f1e8")
	environment.environment.ambient_light_energy = 0.9
	viewport.add_child(environment)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(12.0, 12.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("59666c")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	viewport.add_child(ground)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	key.light_color = Color("fff3dc")
	key.light_energy = 1.35
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 2.8, -2.0)
	fill.omni_range = 8.0
	fill.light_color = Color("b9d8ff")
	fill.light_energy = 0.75
	fill.shadow_enabled = false
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.position = Vector3(5.7, 3.8, -7.2)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.63, 0.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.3
	viewport.add_child(camera)
	return viewport


func _capture_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture="):
			return argument.trim_prefix("capture=")
	return "D:/geteco/game/_codex_diag/boss-muscle-profile.png"


func _wheel_centres(model: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center"):
			var centre: Vector3 = node.get_meta("wheel_center")
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
		var surface_keys: PackedStringArray = part.get_meta(SURFACE_KEYS_META, PackedStringArray())
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material_key := String(surface_keys[surface_index]) if surface_index < surface_keys.size() else _material_key(model, part.material_override)
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
	return ""


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
