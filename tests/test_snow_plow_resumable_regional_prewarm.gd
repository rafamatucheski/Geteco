extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const STAGE_BUDGET_USEC := 6000
const EXPECTED_MESHES := 46
const EXPECTED_VISUAL_SIGNATURE := 3643091624
const EXPECTED_TRIANGLES := 38642

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_snow_plow_cache()
	await _cancel_partial_job_without_publication()
	await _complete_resumable_job()
	print("SNOW_PLOW_RESUMABLE_REGIONAL_PREWARM failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)


func _cancel_partial_job_without_publication() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _snow_plow_job(session)
	_check(not job.is_empty(), "Mountain session exposes SnowPlow")
	_check(String(job.get("cancel_granularity", "")) == "between_stages", "SnowPlow advertises cancellation between resumable stages")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_job_resource(session, job)
	_check(not loaded.has("error"), "SnowPlow threaded resource resolves before staged work")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var observed: Array[String] = []
	for _index in 4:
		var step := CACHE.advance_region_job(session, job, loaded.resource as Resource)
		var stage := String(step.get("stage", ""))
		observed.append(stage)
		_check(not step.has("error"), "partial SnowPlow stage succeeds: %s" % stage)
		_check(int(step.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "partial SnowPlow stage %s stays within 6 ms" % stage)
		_check(not CACHE._models.has(MODEL_PATH), "partial SnowPlow never publishes _models")
		_check(not CACHE._prepared.has(MODEL_PATH), "partial SnowPlow never publishes _prepared")
		if step.has("error"):
			break
		await process_frame
	var cancelled := CACHE.finish_region_session(session, true)
	_check(bool(cancelled.get("cancelled", false)), "partial SnowPlow session records cancellation")
	_check(not CACHE._models.has(MODEL_PATH), "cancelled SnowPlow leaves no cache template")
	_check(not CACHE._prepared.has(MODEL_PATH), "cancelled SnowPlow leaves no false prepared marker")
	_check(not CACHE._miss_started_usec.has(MODEL_PATH), "cancelled SnowPlow clears cold-build timing state")
	_check(not CACHE._deferred_constructor_paths.has(MODEL_PATH), "cancelled SnowPlow clears constructor deferral state")
	_check(not CACHE._regional_capture_suppressed_paths.has(MODEL_PATH), "cancelled SnowPlow clears capture suppression state")
	_check(observed == ["construct_shell", "strategy_select", "prepared_materials", "prepared_scene_instantiate"], "SnowPlow enters the direct prepared-resource path before cancellation")
	await process_frame


func _complete_resumable_job() -> void:
	var session := CACHE.begin_region_session(self, &"mountain")
	var job := _snow_plow_job(session)
	_check(not job.is_empty(), "resumed Mountain session keeps SnowPlow queued")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return
	var loaded := await _load_job_resource(session, job)
	_check(not loaded.has("error"), "resumed SnowPlow reacquires its threaded resource")
	if loaded.has("error"):
		CACHE.finish_region_session(session, true)
		return
	var stages: Array[String] = []
	var max_stage_usec := 0
	var result := {"complete": false}
	# The prepared scene now attaches 46 presentation groups in resumable
	# per-frame slices, plus begin/finish and the surrounding cache stages.
	for _index in 128:
		_check(not CACHE._models.has(MODEL_PATH), "SnowPlow remains private until its commit stage")
		_check(not CACHE._prepared.has(MODEL_PATH), "SnowPlow is not falsely prepared between stages")
		result = CACHE.advance_region_job(session, job, loaded.resource as Resource)
		var stage := String(result.get("stage", ""))
		stages.append(stage)
		max_stage_usec = maxi(max_stage_usec, int(result.get("actual_usec", 0)))
		_check(not result.has("error"), "SnowPlow resumable stage succeeds: %s" % stage)
		_check(int(result.get("actual_usec", 0)) <= STAGE_BUDGET_USEC, "SnowPlow stage %s stays within 6 ms" % stage)
		if result.has("error"):
			break
		if bool(result.get("complete", false)):
			break
		await process_frame
	_check(bool(result.get("complete", false)), "SnowPlow staged prewarm reaches atomic commit")
	_check(bool(result.get("executed", false)), "SnowPlow commit counts one completed model")
	_check(bool(result.get("resource_reused", false)), "SnowPlow staged job reuses the threaded Script resource")
	_check(bool(result.get("preparation", {}).get("direct_prepared", false)), "SnowPlow publishes its validated prepared resource directly")
	_check(stages.count("prepared_scene_instantiate") == 1, "SnowPlowGeometry is instantiated exactly once during prewarm")
	_check(not stages.has("procedural_build"), "SnowPlow prewarm does not rebuild procedural geometry")
	_check(not stages.has("wheel_mount"), "SnowPlow prewarm does not remount already prepared wheel geometry")
	_check(not stages.has("batching"), "SnowPlow prewarm does not rebatch prepared geometry")
	_check(not stages.has("flatten"), "SnowPlow prewarm does not flatten wheels again")
	_check(not stages.has("capture_pack"), "SnowPlow direct publication avoids geometry capture and packing")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "SnowPlow publishes _models and _prepared atomically")
	if CACHE._models.has(MODEL_PATH):
		var entry: Dictionary = CACHE._models[MODEL_PATH]
		_check(bool(entry.get("direct_prepared_resource", false)), "SnowPlow cache entry records direct prepared publication")
		_check(bool(entry.get("prepared_presentation", false)), "SnowPlow cache entry is presentation-ready")

	var report := CACHE.finish_region_session(session, false)
	var snow_steps: Array = []
	for step in report.get("stage_steps", []):
		if String(step.get("path", "")) == MODEL_PATH:
			snow_steps.append(step)
	_check(snow_steps.size() == stages.size(), "SnowPlow report retains telemetry for every active stage")
	_check(int(report.get("max_stage_usec", 0)) <= STAGE_BUDGET_USEC, "regional report keeps every SnowPlow stage within 6 ms")
	_check((report.get("over_budget_stages", []) as Array).is_empty(), "regional report exposes no hidden SnowPlow over-budget stage")

	var script := loaded.resource as Script
	_check(script != null, "threaded SnowPlow resource remains a Script for gameplay restore")
	if script == null:
		return
	var hits_before := CACHE.hits
	var live := script.new() as Node3D
	root.add_child(live)
	var sibling := script.new() as Node3D
	root.add_child(sibling)
	_check(CACHE.hits == hits_before + 2, "gameplay SnowPlows restore from the directly published cache")
	_check(_mesh_count(live) == EXPECTED_MESHES and _mesh_count(sibling) == EXPECTED_MESHES, "direct restore preserves all 46 prepared SnowPlow meshes")
	_check(_materials_match_runtime_roles(live), "direct restore binds every SnowPlow part to this instance's materials")
	_check(_materials_match_runtime_roles(sibling), "direct restore rebinds sibling parts without shared materials")
	_check(_role_count(live, &"plow_steel") > 0 and _role_count(live, &"plow_edge") > 0, "direct restore preserves blade face and cutting edge")
	_check(_role_count(live, &"road_salt") > 0 and _role_count(live, &"paint") > 0, "direct restore preserves hopper volume and salt load")
	_check(int(live.get_meta("visual_signature", 0)) == EXPECTED_VISUAL_SIGNATURE, "direct restore retains the exact SnowPlow visual signature")
	_check(int(live.get_meta("triangle_count", 0)) == EXPECTED_TRIANGLES, "direct restore retains the exact SnowPlow triangle contract")
	_check(int(live.get_meta("vehicle_wheel_clearance_signature", 0)) != 0, "direct restore retains authored six-wheel clearance metadata")
	_check(_materials_are_instance_local(live, sibling), "all SnowPlow runtime materials are independent per gameplay instance")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "direct restore keeps SnowPlow paint independent")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.CYAN
		_check(sibling_paint.albedo_color == sibling_color, "repainting one SnowPlow cannot recolor its sibling")

	var originals := live.get("originals") as Dictionary
	_check(not originals.is_empty(), "direct restore runs _ready and captures SnowPlow damage geometry")
	live.call("apply_impact", Vector3(0.75, 0.8, -2.0), Vector3(-1.0, 0.0, 0.0), 12.0)
	_check(int(live.get("impact_count")) == 1, "direct restore preserves SnowPlow gameplay damage")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0, "direct restore preserves SnowPlow repair")

	var rig := WHEEL_RIG.new()
	_check(rig.mount(live) and rig.pivots.size() == 6, "direct restore remounts all six SnowPlow wheels")
	_check(BATCHER.batch_model(live) == 0, "direct restore performs no SnowPlow rebatch work")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "direct restore retains the prepared batching marker")
	_check(live.get_meta("snow_plow_geometry_source", &"") == &"prepared", "direct restore retains the SnowPlow prepared-source marker")
	_check(max_stage_usec <= STAGE_BUDGET_USEC, "largest SnowPlow stage stays within the scheduler slice")
	live.free()
	sibling.free()


func _snow_plow_job(session: Dictionary) -> Dictionary:
	for job in CACHE.region_session_jobs(session):
		if String(job.get("path", "")) == MODEL_PATH:
			return job
	return {}


func _load_job_resource(session: Dictionary, job: Dictionary) -> Dictionary:
	var state := CACHE.request_region_job_resource(session, job)
	for _frame in 600:
		if String(state.get("state", "")) != "loading":
			return state
		await process_frame
		state = CACHE.poll_region_job_resource(session, job)
	return {"error": "thread_load_timeout", "retryable": true}


func _mesh_count(node: Node) -> int:
	var result := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		result += _mesh_count(child)
	return result


func _materials_match_runtime_roles(node: Node) -> bool:
	var model := node as Node3D
	if model == null:
		return false
	var model_materials := model.get("materials") as Dictionary
	return _node_materials_match_runtime_roles(node, model_materials)


func _node_materials_match_runtime_roles(node: Node, model_materials: Dictionary) -> bool:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var role := StringName(part.get_meta(&"snow_plow_material_role", &""))
		if role == &"" or part.material_override != model_materials.get(role):
			return false
	for child in node.get_children():
		if not _node_materials_match_runtime_roles(child, model_materials):
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
	if node is MeshInstance3D and StringName(node.get_meta(&"snow_plow_material_role", &"")) == expected_role:
		count += 1
	for child in node.get_children():
		count += _role_count(child, expected_role)
	return count


func _reset_snow_plow_cache() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CACHE.misses = 0
	CACHE.cold_builds = 0
	CACHE.cold_build_usec = 0
	CACHE.regional_misses = 0
	CACHE.regional_cold_builds = 0
	CACHE.regional_cold_build_usec = 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
