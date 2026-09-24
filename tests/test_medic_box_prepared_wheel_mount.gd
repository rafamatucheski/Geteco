extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/MedicBoxModel.gd"
const WHEEL_RESOURCE_PATH := "res://prototypes/living_cast/models/MedicBoxWheelWells.res"
const PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/models/MedicBoxPreparedGeometry.scn"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_STEPS := 256

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_reset_runtime()
	_check(ResourceLoader.exists(WHEEL_RESOURCE_PATH, "Resource"), "MedicBox fallback wheel-well resource exists")
	var wheel_resource := load(WHEEL_RESOURCE_PATH) as Resource
	_check(wheel_resource != null, "MedicBox fallback wheel-well resource loads")
	var prepared_scene := load(PREPARED_GEOMETRY_PATH) as PackedScene
	_check(prepared_scene != null, "MedicBox integral prepared geometry loads")
	if wheel_resource == null or prepared_scene == null:
		_finish({"error": "resource_missing"})
		return
	_check(int(wheel_resource.get_meta("format_version", 0)) == 1, "MedicBox wheel-well fallback contract is current")
	_check(String(wheel_resource.get_meta("model_id", "")) == "medic_box", "MedicBox wheel-well fallback belongs to MedicBox")
	_check(int(wheel_resource.get_meta("mesh_count", 0)) > 0, "MedicBox fallback contains changed body meshes")
	_check(int(wheel_resource.get_meta("wheel_centres", 0)) == 4, "MedicBox fallback was baked from four wheel centres")
	var prepared_template := prepared_scene.instantiate() as Node3D
	var prepared_signature := int(prepared_template.get_meta("medic_box_prepared_geometry_signature", 0))
	var prepared_meshes := int(prepared_template.get_meta("medic_box_prepared_meshes", 0))
	var prepared_triangles := int(prepared_template.get_meta("medic_box_prepared_triangles", 0))
	var clearance_signature := int(prepared_template.get_meta("vehicle_wheel_clearance_signature", 0))
	_check(prepared_signature != 0 and prepared_meshes > 0 and prepared_triangles > 0, "MedicBox integral template carries fixed geometry metadata")
	_check(clearance_signature != 0, "MedicBox integral template carries a valid wheel-clearance signature")
	prepared_template.free()

	var session := CACHE.begin_region_session(self, &"emergency")
	var job := _job_for_path(CACHE.region_session_jobs(session), MODEL_PATH)
	_check(not job.is_empty(), "emergency regional manifest exposes MedicBox")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"error": "regional_job_missing"})
		return
	var model_resource := load(MODEL_PATH) as Resource
	var prepared_hits_before := CLEARANCE.prepared_hits
	var execution: Dictionary = {"complete": false}
	var stage_rows: Array[Dictionary] = []
	for _step in MAX_STAGE_STEPS:
		execution = CACHE.advance_region_job(session, job, model_resource)
		stage_rows.append({
			"stage": String(execution.get("stage", "")),
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
		})
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		await process_frame
	_check(not execution.has("error"), "MedicBox regional preparation succeeds")
	_check(bool(execution.get("complete", false)), "MedicBox regional preparation reaches atomic commit")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "MedicBox remains a complete geometry-cache model")
	var wheel_mount_usec := _stage_usec(stage_rows, "wheel_mount")
	var preparation: Dictionary = execution.get("preparation", {})
	_check(bool(preparation.get("direct_prepared", false)), "MedicBox regional pipeline publishes the integral prepared template")
	_check(bool(preparation.get("wheel_mount_deferred_to_restore", false)), "MedicBox regional pipeline defers live wheel pivots to gameplay restore")
	_check(wheel_mount_usec == 0, "MedicBox integral regional pipeline performs no wheel carving or mount")
	for row in stage_rows:
		var stage := String(row.get("stage", ""))
		var stage_usec := int(row.get("actual_usec", 0))
		_check(stage_usec <= STAGE_BUDGET_USEC, "MedicBox regional stage %s exceeds 6 ms: %.3f ms" % [stage, stage_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == prepared_hits_before, "MedicBox regional preparation performs no hidden wheel carving")
	_check((preparation.get("unsafe_reference_properties", PackedStringArray()) as PackedStringArray).is_empty(), "MedicBox publishes no live operational Node references")
	var region_report := CACHE.finish_region_session(session, true)
	await process_frame

	# Prove exact equivalence before batching. Cache batching can introduce harmless
	# floating-point round-off while fusing surfaces, so its restored form is
	# compared to this authored form at 0.1 mm below.
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var authored := (model_resource as Script).new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	authored.call("build_procedural_source", false)
	root.add_child(authored)
	var authored_rig := WHEEL_RIG.new()
	var authored_mounted := authored_rig.mount(authored)
	_check(authored_mounted and authored_rig.pivots.size() == 4, "MedicBox authored prepared form mounts four wheels")
	_check(_triangle_count(authored) == prepared_triangles, "MedicBox authored source and integral template preserve the same triangle count")

	var script := model_resource as Script
	var live := script.new() as Node3D
	var sibling := script.new() as Node3D
	root.add_child(live)
	root.add_child(sibling)
	_check(live.get_meta("medic_box_geometry_source", &"") == &"prepared", "MedicBox cache restore identifies the integral prepared source")
	_check(int(live.get_meta("medic_box_prepared_geometry_signature", 0)) == prepared_signature, "MedicBox cache restore retains the fixed integral signature")
	_check(bool(live.get_meta("vehicle_prepared_wheel_wells", false)), "MedicBox cache restore retains prepared wheel metadata")
	_check(int(live.get_meta("vehicle_wheel_clearance_signature", 0)) == clearance_signature, "MedicBox cache restore retains the exact wheel-clearance signature")
	_check(BATCHER.batch_model(live) == 0, "MedicBox cache restore does not repeat mesh batching")

	var runtime_hits_before := CLEARANCE.prepared_hits
	var runtime_mount_started := Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var runtime_mount_usec := Time.get_ticks_usec() - runtime_mount_started
	_check(live_mounted and live_rig.pivots.size() == 4, "MedicBox cache restore remounts four articulated wheels")
	_check(runtime_mount_usec <= STAGE_BUDGET_USEC, "MedicBox cached runtime wheel mount stays within 6 ms, got %.3f ms" % [runtime_mount_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == runtime_hits_before + 1, "MedicBox runtime restore still skips polygon carving")
	_check(_visual_signature(live, 4) == _visual_signature(authored, 4), "MedicBox cache batching preserves geometry/material signature at 0.1 mm")
	_check(_triangle_count(live) == prepared_triangles, "MedicBox prepared path preserves exact triangle count")

	var left_door := live.get_node_or_null("RearDoorLeft") as Node3D
	var right_door := live.get_node_or_null("RearDoorRight") as Node3D
	_check(left_door != null and right_door != null, "MedicBox cache restore retains both rear doors")
	var left_door_meshes: Array[Node] = left_door.find_children("*", "MeshInstance3D", true, false) if left_door != null else []
	var right_door_meshes: Array[Node] = right_door.find_children("*", "MeshInstance3D", true, false) if right_door != null else []
	_check(left_door_meshes.size() >= 3 and right_door_meshes.size() >= 3, "MedicBox prepared path preserves panel, window and handle on both doors")
	live.call("set_rear_doors", true, true)
	_check(left_door != null and left_door.rotation.y > 1.8 and right_door != null and right_door.rotation.y < -1.8, "MedicBox prepared rear doors still open")
	live.call("set_rear_doors", false, true)
	_check(left_door != null and right_door != null and is_zero_approx(left_door.rotation.y) and is_zero_approx(right_door.rotation.y), "MedicBox prepared rear doors still close")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "MedicBox prepared instances retain independent paint")
	var door_uses_instance_paint := false
	for node in left_door_meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.material_override == live_paint:
			door_uses_instance_paint = true
	_check(door_uses_instance_paint, "MedicBox prepared rear door is rebound to the live paint material")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "MedicBox prepared paint remains visible and non-black")
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "MedicBox repaint cannot recolor another cached instance")
	var originals := live.get("originals") as Dictionary
	_check(not originals.is_empty(), "MedicBox prepared body retains damage baselines")
	live.call("apply_impact", Vector3(0.7, 0.8, -2.2), Vector3(-1.0, 0.0, 0.0), 9.0)
	_check(int(live.get("impact_count")) == 1, "MedicBox prepared body still accepts damage")
	_check(not (live.get("damaged_vertices") as Dictionary).is_empty(), "MedicBox prepared body deforms an actual cached mesh")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and (live.get("damaged_vertices") as Dictionary).is_empty(), "MedicBox prepared body still repairs completely")

	var result := {
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"prepared_meshes": prepared_meshes,
		"visual_signature": prepared_signature,
		"triangles": prepared_triangles,
		"regional_wheel_mount_usec": wheel_mount_usec,
		"regional_wheel_mount_ms": wheel_mount_usec / 1000.0,
		"runtime_restore_mount_usec": runtime_mount_usec,
		"runtime_restore_mount_ms": runtime_mount_usec / 1000.0,
		"regional_stage_rows": stage_rows,
		"regional_total_active_usec": int(execution.get("total_active_usec", 0)),
		"regional_total_active_ms": int(execution.get("total_active_usec", 0)) / 1000.0,
		"regional_over_budget_stages": region_report.get("over_budget_stages", []),
		"wheel_centres": live_rig.pivots.size(),
		"damage_parts": originals.size(),
		"unsafe_reference_properties": preparation.get("unsafe_reference_properties", PackedStringArray()),
	}
	authored.free()
	live.free()
	sibling.free()
	_finish(result)


func _reset_runtime() -> void:
	CACHE._models.clear()
	CACHE._prepared.clear()
	CACHE._operationally_warmed_paths.clear()
	CACHE._region_reports.clear()
	CACHE._retained_regions.clear()
	CACHE._active_region_sessions.clear()
	CACHE._deferred_constructor_paths.clear()
	CACHE._regional_capture_suppressed_paths.clear()
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	CLEARANCE.prepared_hits = 0


func _job_for_path(jobs: Array[Dictionary], path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == path:
			return job
	return {}


func _stage_usec(rows: Array[Dictionary], wanted: String) -> int:
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			return int(row.get("actual_usec", 0))
	return 0


func _count_meta(parent: Node, key: StringName) -> int:
	var count := 1 if parent.has_meta(key) else 0
	for child in parent.get_children():
		count += _count_meta(child, key)
	return count


func _triangle_count(parent: Node) -> int:
	var count := 0
	if parent is MeshInstance3D:
		var mesh := (parent as MeshInstance3D).mesh
		if mesh != null:
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				count += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
	for child in parent.get_children():
		count += _triangle_count(child)
	return count


func _visual_signature(model: Node3D, decimals: int) -> int:
	var triangles: Array[String] = []
	_collect_visual_triangles(model, Transform3D.IDENTITY, triangles, decimals)
	triangles.sort()
	return hash(triangles)


func _collect_visual_triangles(node: Node, parent_transform: Transform3D, triangles: Array[String], decimals: int) -> void:
	var model_transform := parent_transform
	if node is Node3D:
		model_transform = parent_transform * (node as Node3D).transform
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
					var point := model_transform * vertices[vertex_index]
					points.append(_point_key(point, decimals))
				points.sort()
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(child, model_transform, triangles, decimals)


func _point_key(point: Vector3, decimals: int) -> String:
	var scale := pow(10.0, decimals)
	return "%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)]


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("MEDIC_BOX_PREPARED_WHEEL_MOUNT ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
