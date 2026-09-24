extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/ArcticJeepModel.gd"
const MATERIAL_ROLE_META := &"arctic_jeep_material_role"
const SURFACE_ROLES_META := &"arctic_jeep_surface_material_roles"
const STAGE_BUDGET_USEC := 6000
const EXPECTED_SIGNATURE := 2561308829
const EXPECTED_MESHES := 12
const EXPECTED_TRIANGLES := 9158
const EXPECTED_CLEARANCE_SIGNATURE := 2025983418

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_caches()
	await _cancel_partial_job()
	await _complete_resumed_job()
	print("ARCTIC_JEEP_RESUMABLE_REGIONAL_PREWARM failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)


func _cancel_partial_job() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _arctic_job(session)
	_check(not job.is_empty(), "Mountain session exposes ArcticJeep")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_resource(session, job)
	_check(not loaded.has("error"), "ArcticJeep threaded Script resolves")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var observed: Array[String] = []
	for _index in 4:
		var step := CACHE.advance_region_job(session, job, loaded.resource as Resource)
		var stage := String(step.get("stage", ""))
		observed.append(stage)
		_check(not step.has("error"), "partial ArcticJeep stage succeeds: %s" % stage)
		_check(int(step.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "partial ArcticJeep stage %s stays within 6 ms" % stage)
		_check(not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH), "partial ArcticJeep remains unpublished")
		if step.has("error"):
			break
		await process_frame
	var report := CACHE.finish_region_session(session, true)
	_check(observed == ["construct_shell", "strategy_select", "prepared_materials", "prepared_scene_instantiate"], "ArcticJeep enters direct prepared stages before cancellation")
	_check(bool(report.get("cancelled", false)), "ArcticJeep partial session records cancellation")
	_check(not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH), "cancelled ArcticJeep publishes no partial entry")
	_check(not CACHE._deferred_constructor_paths.has(MODEL_PATH), "cancelled ArcticJeep clears constructor deferral")
	_check(not CACHE._regional_capture_suppressed_paths.has(MODEL_PATH), "cancelled ArcticJeep clears capture suppression")
	await process_frame


func _complete_resumed_job() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _arctic_job(session)
	_check(not job.is_empty(), "resumed Mountain session keeps ArcticJeep queued")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_resource(session, job)
	_check(not loaded.has("error"), "resumed ArcticJeep reacquires its threaded Script")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var stages: Array[String] = []
	var max_stage_usec := 0
	var result: Dictionary = {"complete": false}
	for _index in 32:
		_check(not CACHE._models.has(MODEL_PATH) and not CACHE._prepared.has(MODEL_PATH), "ArcticJeep remains private until commit")
		result = CACHE.advance_region_job(session, job, loaded.resource as Resource)
		var stage := String(result.get("stage", ""))
		var actual_usec := int(result.get("actual_usec", 0))
		stages.append(stage)
		max_stage_usec = maxi(max_stage_usec, actual_usec)
		_check(not result.has("error"), "ArcticJeep stage succeeds: %s" % stage)
		_check(actual_usec <= STAGE_BUDGET_USEC, "ArcticJeep stage %s stays within 6 ms, got %.3f ms" % [stage, actual_usec / 1000.0])
		if result.has("error") or bool(result.get("complete", false)):
			break
		await process_frame
	_check(bool(result.get("complete", false)) and bool(result.get("executed", false)), "ArcticJeep reaches atomic regional commit")
	_check(bool(result.get("resource_reused", false)), "ArcticJeep reuses its threaded Script resource")
	_check(bool(result.get("preparation", {}).get("direct_prepared", false)), "ArcticJeep publishes its prepared resource directly")
	_check(stages.count("prepared_scene_instantiate") == 1, "ArcticJeep prepared scene is instantiated once")
	for forbidden in ["procedural_build", "wheel_mount", "batching", "flatten", "capture_pack"]:
		_check(not stages.has(forbidden), "ArcticJeep direct prewarm omits %s" % forbidden)
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "ArcticJeep publishes cache entry and prepared marker together")
	if CACHE._models.has(MODEL_PATH):
		var entry: Dictionary = CACHE._models[MODEL_PATH]
		_check(bool(entry.get("direct_prepared_resource", false)), "ArcticJeep cache entry records direct publication")
		_check(bool(entry.get("prepared_presentation", false)), "ArcticJeep cache entry is presentation-ready")

	var report := CACHE.finish_region_session(session, false)
	var arctic_steps: Array = []
	for step in report.get("stage_steps", []):
		if String(step.get("path", "")) == MODEL_PATH:
			arctic_steps.append(step)
	_check(arctic_steps.size() == stages.size(), "ArcticJeep report retains every staged step")
	_check(int(report.get("max_stage_usec", 0)) <= STAGE_BUDGET_USEC, "ArcticJeep report maximum stays within 6 ms")
	_check((report.get("over_budget_stages", []) as Array).is_empty(), "ArcticJeep report has no hidden over-budget stage")

	var script := loaded.resource as Script
	_check(script != null, "threaded ArcticJeep resource remains reusable for gameplay")
	if script == null:
		return
	var hits_before := CACHE.hits
	var live := script.new() as Node3D
	root.add_child(live)
	var sibling := script.new() as Node3D
	root.add_child(sibling)
	_check(CACHE.hits == hits_before + 2, "two gameplay ArcticJeeps restore from regional cache")
	_check(_mesh_count(live) == EXPECTED_MESHES and _mesh_count(sibling) == EXPECTED_MESHES, "gameplay restore preserves 12 compact prepared meshes")
	_check(_triangle_count(live) == EXPECTED_TRIANGLES, "gameplay restore preserves 9,158 triangles")
	_check(_geometry_signature(live) == EXPECTED_SIGNATURE, "gameplay restore preserves exact ArcticJeep geometry/material signature")
	_check(int(live.get_meta("vehicle_wheel_clearance_signature", 0)) == EXPECTED_CLEARANCE_SIGNATURE, "gameplay restore retains prepared wheel clearance")
	_check(_materials_match_roles(live) and _materials_match_roles(sibling), "gameplay restore rebinds every prepared material role")
	_check(_materials_are_instance_local(live, sibling), "ArcticJeep materials remain independent per gameplay instance")
	_check(_role_count(live, &"canvas") > 0 and _role_count(live, &"rear_lens") > 0, "canvas cabin and rear lenses survive prepared restore")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "ArcticJeep paint is independent")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.CYAN
		_check(sibling_paint.albedo_color == sibling_color, "repainting one ArcticJeep does not recolor another")

	var originals := live.get("originals") as Dictionary
	var lamp_sources := live.get("lamp_sources") as Dictionary
	_check(not originals.is_empty(), "prepared ArcticJeep captures deformable paint geometry")
	_check(lamp_sources.size() == 2, "prepared ArcticJeep captures both authored headlamps")
	live.call("apply_impact", Vector3(0.82, 0.9, -1.2), Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(live.get("impact_count")) == 1 and float(live.call("max_deformation")) > 0.0, "prepared ArcticJeep retains localized damage")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and is_zero_approx(float(live.call("max_deformation"))), "prepared ArcticJeep repair restores geometry")

	var prepared_hits_before := CLEARANCE.prepared_hits
	var rig := WHEEL_RIG.new()
	_check(rig.mount(live) and rig.pivots.size() == 4, "prepared ArcticJeep remounts four articulated wheels")
	_check(CLEARANCE.prepared_hits == prepared_hits_before + 1, "gameplay wheel mount reuses prepared clearance")
	_check(BATCHER.batch_model(live) == 0, "gameplay restore requires no ArcticJeep rebatch")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "gameplay restore retains batching metadata")
	_check(live.get_meta("arctic_jeep_geometry_source", &"") == &"prepared", "gameplay restore retains prepared-source metadata")
	_check(max_stage_usec <= STAGE_BUDGET_USEC, "largest ArcticJeep regional stage stays within scheduler slice")
	live.free()
	sibling.free()


func _arctic_job(session: Dictionary) -> Dictionary:
	for job in CACHE.region_session_jobs(session):
		if String(job.get("path", "")) == MODEL_PATH:
			return job
	return {}


func _load_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var state := CACHE.request_region_job_resource(session, job)
	for _frame in 600:
		if String(state.get("state", "")) != "loading":
			return state
		await process_frame
		state = CACHE.poll_region_job_resource(session, job)
	return {"error": "thread_load_timeout", "retryable": true}


func _materials_match_roles(node: Node3D) -> bool:
	return _node_materials_match_roles(node, node.get("materials") as Dictionary)


func _node_materials_match_roles(node: Node, materials: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		if surface_roles.size() != part.mesh.get_surface_count():
			return false
		for surface_index in surface_roles.size():
			var expected := materials.get(StringName(surface_roles[surface_index])) as Material
			if expected == null or part.get_active_material(surface_index) != expected:
				return false
	for child in node.get_children():
		if not _node_materials_match_roles(child, materials):
			return false
	return true


func _materials_are_instance_local(first: Node3D, second: Node3D) -> bool:
	var first_materials := first.get("materials") as Dictionary
	var second_materials := second.get("materials") as Dictionary
	for role in first_materials:
		if not second_materials.has(role) or first_materials[role] == second_materials[role]:
			return false
	return true


func _role_count(node: Node, expected_role: StringName) -> int:
	var count := 0
	if node is MeshInstance3D:
		var surface_roles: PackedStringArray = node.get_meta(SURFACE_ROLES_META, PackedStringArray())
		for role in surface_roles:
			if StringName(role) == expected_role:
				count += 1
	for child in node.get_children():
		count += _role_count(child, expected_role)
	return count


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


func _geometry_signature(model: Node3D) -> int:
	var entries: Array[String] = []
	_collect_geometry(model, Transform3D.IDENTITY, entries)
	entries.sort()
	return hash(entries)


func _collect_geometry(node: Node, parent_transform: Transform3D, entries: Array[String]) -> void:
	var world_transform := parent_transform
	if node is Node3D:
		world_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var surface_roles: PackedStringArray = part.get_meta(SURFACE_ROLES_META, PackedStringArray())
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var role := StringName(surface_roles[surface_index]) if surface_index < surface_roles.size() else StringName(part.get_meta(MATERIAL_ROLE_META, &""))
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
				entries.append("%s:%s" % [role, "|".join(points)])
	for child in node.get_children():
		_collect_geometry(child, world_transform, entries)


func _reset_caches() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
