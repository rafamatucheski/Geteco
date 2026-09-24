extends SceneTree

## Regression contract for the resumable direct-prepared attach path. It keeps
## the four large Mountain vehicles private across every attach slice, cancels
## at representative partial boundaries, retries, and validates the gameplay
## instance only after the atomic cache commit.

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_JOB_STEPS := 256

const SPECS := [
	{
		"id": "summit_suv",
		"path": "res://prototypes/living_cast/models/SummitSUVModel.gd",
		"wheels": 4,
		"impact": Vector3(0.82, 0.9, -1.2),
	},
	{
		"id": "arctic_jeep",
		"path": "res://prototypes/living_cast/models/ArcticJeepModel.gd",
		"wheels": 4,
		"impact": Vector3(0.82, 0.9, -1.2),
	},
	{
		"id": "ranch_single",
		"path": "res://prototypes/living_cast/models/RanchSingleModel.gd",
		"wheels": 4,
		"impact": Vector3(0.78, 0.82, -2.48),
	},
	{
		"id": "snow_plow",
		"path": "res://prototypes/living_cast/models/SnowPlowModel.gd",
		"wheels": 6,
		"impact": Vector3(0.75, 0.8, -2.0),
	},
]

var failures: Array[String] = []
var telemetry: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for spec in SPECS:
		await _exercise_vehicle(spec)
	print("PREPARED_VEHICLE_ATTACH_RESUMPTION telemetry=%s failures=%s" % [JSON.stringify(telemetry), failures])
	quit(0 if failures.is_empty() else 1)


func _exercise_vehicle(spec: Dictionary) -> void:
	var id := String(spec.id)
	var path := String(spec.path)
	_reset_model(path)
	var discovery := await _complete_job(spec, "discovery")
	var attach_steps: Array = discovery.get("attach_steps", [])
	_check(attach_steps.size() >= 2, "%s attach is split across at least two resumable slices" % id)
	if not bool(discovery.get("complete", false)) or attach_steps.size() < 2:
		return
	_validate_attach_trace(spec, attach_steps)

	var boundaries: Array[int] = [1]
	if attach_steps.size() >= 3:
		boundaries.append(2)
	var middle := maxi(1, ceili(attach_steps.size() / 2.0))
	if not boundaries.has(middle):
		boundaries.append(middle)
	var last_slice := maxi(1, attach_steps.size() - 1)
	if not boundaries.has(last_slice):
		boundaries.append(last_slice)
	if not boundaries.has(attach_steps.size()):
		boundaries.append(attach_steps.size())
	for boundary in boundaries:
		await _cancel_at_attach_boundary(spec, boundary)

	# The last cancellation leaves no publication. A fresh session must retry the
	# whole job and still produce a usable gameplay instance.
	var retry := await _complete_job(spec, "retry_after_cancel")
	_check(bool(retry.get("complete", false)), "%s completes after attach cancellation" % id)
	if bool(retry.get("complete", false)):
		await _validate_gameplay_restore(spec, retry.get("script") as Script)
	telemetry[id] = {
		"attach_slices": attach_steps.size(),
		"cancel_boundaries": boundaries,
		"discovery_max_stage_usec": int(discovery.get("max_stage_usec", 0)),
		"retry_max_stage_usec": int(retry.get("max_stage_usec", 0)),
		"retry_stages": retry.get("stages", []),
	}
	_reset_model(path)


func _complete_job(spec: Dictionary, phase: String) -> Dictionary:
	var id := String(spec.id)
	var path := String(spec.path)
	_reset_model(path)
	var opened := await _open_job(path)
	if opened.has("error"):
		_check(false, "%s %s opens regional job: %s" % [id, phase, opened.get("error", "unknown")])
		return {"complete": false}
	var session := opened.get("session", {}) as Dictionary
	var job := opened.get("job", {}) as Dictionary
	var script := opened.get("script") as Script
	var stages: Array[String] = []
	var attach_steps: Array[Dictionary] = []
	var max_stage_usec := 0
	var result: Dictionary = {"complete": false}
	for _step_index in MAX_JOB_STEPS:
		var models_before := CACHE._models.has(path)
		var prepared_before := CACHE._prepared.has(path)
		_check(models_before == prepared_before, "%s %s never exposes one half of the cache pair" % [id, phase])
		_check(not models_before, "%s %s remains unpublished before commit" % [id, phase])
		result = CACHE.advance_region_job(session, job, script as Resource)
		var stage := String(result.get("stage", ""))
		var actual_usec := int(result.get("actual_usec", 0))
		stages.append(stage)
		max_stage_usec = maxi(max_stage_usec, actual_usec)
		_check(not result.has("error"), "%s %s stage succeeds: %s" % [id, phase, stage])
		_check(actual_usec <= STAGE_BUDGET_USEC, "%s %s stage %s stays within 6 ms, got %.3f ms" % [id, phase, stage, actual_usec / 1000.0])
		if _is_attach_stage(stage):
			attach_steps.append({
				"stage": stage,
				"next_stage": String(result.get("next_stage", "")),
				"actual_usec": actual_usec,
				"detail": (result.get("stage_detail", {}) as Dictionary).duplicate(true),
			})
		if result.has("error") or bool(result.get("complete", false)):
			break
		_check(not CACHE._models.has(path) and not CACHE._prepared.has(path), "%s %s partial stage remains private: %s" % [id, phase, stage])
		await process_frame

	var completed := bool(result.get("complete", false)) and bool(result.get("executed", false))
	_check(completed, "%s %s reaches an executed commit" % [id, phase])
	_check(CACHE._models.has(path) == CACHE._prepared.has(path), "%s %s commit keeps cache pair atomic" % [id, phase])
	_check(not completed or (CACHE._models.has(path) and CACHE._prepared.has(path)), "%s %s publishes both cache entries on completion" % [id, phase])
	_check(bool(result.get("preparation", {}).get("direct_prepared", false)), "%s %s stays on direct prepared route" % [id, phase])
	_check(stages.count("prepared_scene_instantiate") == 1, "%s %s instantiates the prepared scene once" % [id, phase])
	_check(stages.count("prepared_scene_validate") == 1, "%s %s validates the prepared scene once" % [id, phase])
	for forbidden in ["procedural_build", "wheel_mount", "batching", "flatten", "capture_pack"]:
		_check(not stages.has(forbidden), "%s %s omits legacy stage %s" % [id, phase, forbidden])
	var report := CACHE.finish_region_session(session, not completed)
	_check(int(report.get("max_stage_usec", 0)) <= STAGE_BUDGET_USEC, "%s %s report has no stage above 6 ms" % [id, phase])
	_check((report.get("over_budget_stages", []) as Array).is_empty(), "%s %s report has no hidden over-budget slice" % [id, phase])
	var reported_attach := 0
	for step in report.get("stage_steps", []):
		if String(step.get("path", "")) != path:
			continue
		_check(int(step.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "%s %s telemetry slice stays within 6 ms" % [id, phase])
		if _is_attach_stage(String(step.get("stage", ""))):
			reported_attach += 1
	_check(reported_attach == attach_steps.size(), "%s %s telemetry records every attach slice" % [id, phase])
	return {
		"complete": completed,
		"script": script,
		"stages": stages,
		"attach_steps": attach_steps,
		"max_stage_usec": max_stage_usec,
	}


func _cancel_at_attach_boundary(spec: Dictionary, boundary: int) -> void:
	var id := String(spec.id)
	var path := String(spec.path)
	_reset_model(path)
	var opened := await _open_job(path)
	if opened.has("error"):
		_check(false, "%s cancellation boundary %d opens regional job" % [id, boundary])
		return
	var session := opened.get("session", {}) as Dictionary
	var job := opened.get("job", {}) as Dictionary
	var script := opened.get("script") as Script
	var seen_attach := 0
	var prepared_root_ref: WeakRef = null
	var detached_child_refs: Array[WeakRef] = []
	var warmup_ref: WeakRef = weakref(session.get("warmup_view"))
	var cancelled := false
	for _step_index in MAX_JOB_STEPS:
		var result := CACHE.advance_region_job(session, job, script as Resource)
		var stage := String(result.get("stage", ""))
		var actual_usec := int(result.get("actual_usec", 0))
		_check(not result.has("error"), "%s cancellation stage succeeds before boundary %d: %s" % [id, boundary, stage])
		_check(actual_usec <= STAGE_BUDGET_USEC, "%s cancellation stage %s stays within 6 ms" % [id, stage])
		_check(not CACHE._models.has(path) and not CACHE._prepared.has(path), "%s boundary %d remains atomically unpublished" % [id, boundary])
		if _is_attach_stage(stage):
			seen_attach += 1
		if seen_attach == boundary:
			var state: Dictionary = (session.get("job_states", {}) as Dictionary).get(path, {})
			var prepared_root := state.get("prepared_root") as Node3D
			_check(is_instance_valid(prepared_root), "%s boundary %d retains a private prepared root" % [id, boundary])
			if is_instance_valid(prepared_root):
				prepared_root_ref = weakref(prepared_root)
			for child_value in state.get("prepared_attach_children", []):
				var child := child_value as Node
				if is_instance_valid(child) and child.get_parent() == null:
					detached_child_refs.append(weakref(child))
			var report := CACHE.finish_region_session(session, true)
			_check(bool(report.get("cancelled", false)), "%s boundary %d records cancellation" % [id, boundary])
			cancelled = true
			break
		if result.has("error") or bool(result.get("complete", false)):
			break
		await process_frame
	_check(cancelled, "%s reaches attach cancellation boundary %d" % [id, boundary])
	_check(not CACHE._models.has(path) and not CACHE._prepared.has(path), "%s cancellation boundary %d publishes nothing" % [id, boundary])
	_check(not CACHE._miss_started_usec.has(path), "%s cancellation boundary %d clears miss timing" % [id, boundary])
	_check(not CACHE._deferred_constructor_paths.has(path), "%s cancellation boundary %d clears constructor deferral" % [id, boundary])
	_check(not CACHE._regional_capture_suppressed_paths.has(path), "%s cancellation boundary %d clears capture suppression" % [id, boundary])
	await process_frame
	if prepared_root_ref != null:
		_check(prepared_root_ref.get_ref() == null, "%s cancellation boundary %d frees the partial prepared root" % [id, boundary])
	for child_ref in detached_child_refs:
		_check(child_ref.get_ref() == null, "%s cancellation boundary %d frees every detached attach child" % [id, boundary])
	_check(warmup_ref.get_ref() == null, "%s cancellation boundary %d releases the warmup viewport" % [id, boundary])


func _validate_attach_trace(spec: Dictionary, attach_steps: Array) -> void:
	var id := String(spec.id)
	_check(String(attach_steps.front().get("stage", "")) == "prepared_scene_attach_begin", "%s attach trace starts with begin" % id)
	_check(String(attach_steps.back().get("stage", "")) == "prepared_scene_attach_finish", "%s attach trace ends with finish" % id)
	var begin_detail := attach_steps.front().get("detail", {}) as Dictionary
	var finish_detail := attach_steps.back().get("detail", {}) as Dictionary
	var slice_count := int(begin_detail.get("slice_count", -1))
	_check(int(begin_detail.get("slice_index", -2)) == -1 and slice_count > 0, "%s attach begin declares a positive slice count" % id)
	_check(attach_steps.size() == slice_count + 2, "%s attach trace has begin + every child slice + finish" % id)
	for attach_index in range(1, attach_steps.size() - 1):
		var step := attach_steps[attach_index] as Dictionary
		var detail := step.get("detail", {}) as Dictionary
		_check(String(step.get("stage", "")) == "prepared_scene_attach_slice", "%s attach child %d uses the slice stage" % [id, attach_index - 1])
		_check(int(detail.get("slice_index", -1)) == attach_index - 1, "%s attach slice indexes are contiguous at %d" % [id, attach_index - 1])
		_check(int(detail.get("slice_count", -1)) == slice_count, "%s attach slice %d keeps a stable count" % [id, attach_index - 1])
		_check(not String(detail.get("unit_name", "")).is_empty(), "%s attach slice %d identifies its presentation group" % [id, attach_index - 1])
	_check(int(finish_detail.get("slice_index", -1)) == slice_count, "%s attach finish reaches the declared count" % id)
	_check(int(finish_detail.get("slice_count", -1)) == slice_count, "%s attach finish keeps the declared count" % id)


func _validate_gameplay_restore(spec: Dictionary, script: Script) -> void:
	var id := String(spec.id)
	var path := String(spec.path)
	_check(script != null, "%s retry keeps its Script resource" % id)
	if script == null:
		return
	var live := script.new() as Node3D
	var sibling := script.new() as Node3D
	root.add_child(live)
	root.add_child(sibling)
	await process_frame
	_check(_all_mesh_surfaces_bound(live), "%s restore binds every mesh surface to runtime materials" % id)
	_check(_all_mesh_surfaces_bound(sibling), "%s sibling restore binds every mesh surface" % id)
	_check(_materials_are_instance_local(live, sibling), "%s restore keeps all materials instance-local" % id)
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "%s restore keeps paint independent" % id)
	if live_paint != null:
		var color := live_paint.albedo_color
		_check(maxf(color.r, maxf(color.g, color.b)) > 0.12, "%s restore does not lose paint into black" % id)
	var originals := live.get("originals") as Dictionary
	_check(not originals.is_empty(), "%s restore captures deformable body geometry" % id)
	var fallback_impact: Vector3 = spec.get("impact", Vector3.ZERO)
	var impact := _damage_surface_point(originals, fallback_impact)
	live.call("apply_impact", impact, Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(live.get("impact_count")) == 1 and float(live.call("max_deformation")) > 0.0, "%s restore preserves damage" % id)
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and is_zero_approx(float(live.call("max_deformation"))), "%s restore preserves repair" % id)
	var prepared_hits_before := CLEARANCE.prepared_hits
	var rig := WHEEL_RIG.new()
	_check(rig.mount(live) and rig.pivots.size() == int(spec.wheels), "%s restore remounts %d wheels" % [id, int(spec.wheels)])
	_check(CLEARANCE.prepared_hits == prepared_hits_before + 1, "%s wheel restore reuses prepared clearance" % id)
	_check(BATCHER.batch_model(live) == 0, "%s restore requires no gameplay rebatch" % id)
	_check(CACHE._models.has(path) and CACHE._prepared.has(path), "%s gameplay validation keeps committed cache pair" % id)
	live.free()
	sibling.free()


func _damage_surface_point(originals: Dictionary, fallback: Vector3) -> Vector3:
	for node_value in originals:
		var part := node_value as MeshInstance3D
		var mesh := originals[node_value] as Mesh
		if part == null or mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
		if not vertices.is_empty():
			return part.transform * vertices[0]
	return fallback


func _open_job(path: String) -> Dictionary:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job: Dictionary = {}
	for candidate in CACHE.region_session_jobs(session):
		if String(candidate.get("path", "")) == path:
			job = candidate
			break
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return {"error": "job_not_exposed"}
	var resource_state := CACHE.request_region_job_resource(session, job)
	for _frame in 600:
		if String(resource_state.get("state", "")) != "loading":
			break
		await process_frame
		resource_state = CACHE.poll_region_job_resource(session, job)
	if resource_state.has("error") or not resource_state.get("resource") is Script:
		CACHE.finish_region_session(session, true)
		return {"error": resource_state.get("error", "thread_load_failed")}
	return {
		"session": session,
		"job": job,
		"script": resource_state.get("resource") as Script,
	}


func _is_attach_stage(stage: String) -> bool:
	return stage == "prepared_scene_attach" or stage.begins_with("prepared_scene_attach_")


func _all_mesh_surfaces_bound(model: Node3D) -> bool:
	return _node_mesh_surfaces_bound(model, model.get("materials") as Dictionary)


func _node_mesh_surfaces_bound(node: Node, materials: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		if part.mesh == null:
			return false
		for surface_index in part.mesh.get_surface_count():
			var active := part.get_active_material(surface_index)
			if active == null or not materials.values().has(active):
				return false
	for child in node.get_children():
		if not _node_mesh_surfaces_bound(child, materials):
			return false
	return true


func _materials_are_instance_local(first: Node3D, second: Node3D) -> bool:
	var first_materials := first.get("materials") as Dictionary
	var second_materials := second.get("materials") as Dictionary
	if first_materials.is_empty() or first_materials.size() != second_materials.size():
		return false
	for role in first_materials:
		if not second_materials.has(role) or first_materials[role] == second_materials[role]:
			return false
	return true


func _reset_model(path: String) -> void:
	CACHE._models.erase(path)
	CACHE._prepared.erase(path)
	CACHE._operationally_warmed_paths.erase(path)
	CACHE._miss_started_usec.erase(path)
	CACHE._deferred_constructor_paths.erase(path)
	CACHE._regional_capture_suppressed_paths.erase(path)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
