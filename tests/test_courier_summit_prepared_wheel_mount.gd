extends SceneTree

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")

const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_STEPS := 16
const MODELS := [
	{
		"id": "courier_van",
		"region": &"emergency",
		"path": "res://prototypes/living_cast/models/CourierVanModel.gd",
		"resource": "res://prototypes/living_cast/models/CourierVanWheelWells.res",
	},
	{
		"id": "summit_suv",
		"region": &"mountain",
		"path": "res://prototypes/living_cast/models/SummitSUVModel.gd",
		"resource": "res://prototypes/living_cast/models/SummitSUVWheelWells.res",
	},
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rows: Array[Dictionary] = []
	for spec in MODELS:
		rows.append(await _exercise_model(spec))
	print("COURIER_SUMMIT_PREPARED_WHEEL_MOUNT ", JSON.stringify({
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"models": rows,
		"failures": failures,
	}))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _exercise_model(spec: Dictionary) -> Dictionary:
	var id := String(spec.id)
	var model_path := String(spec.path)
	var resource_path := String(spec.resource)
	_reset_runtime()
	_check(ResourceLoader.exists(resource_path, "Resource"), "%s prepared wheel-well resource exists" % id)
	var prepared := load(resource_path) as Resource
	_check(prepared != null, "%s prepared wheel-well resource loads" % id)
	if prepared == null:
		return {"id": id, "error": "resource_missing"}
	_check(int(prepared.get_meta("format_version", 0)) == 1, "%s prepared resource contract is current" % id)
	_check(String(prepared.get_meta("model_id", "")) == id, "%s prepared resource belongs to the model" % id)
	_check(int(prepared.get_meta("mesh_count", 0)) > 0, "%s resource contains changed body meshes" % id)

	# Exercise the same resumable regional stages used by the approach
	# coordinator, with one rendered process frame between stage reservations.
	var session := CACHE.begin_region_session(self, spec.region as StringName)
	var job := _job_for_path(CACHE.region_session_jobs(session), model_path)
	_check(not job.is_empty(), "%s regional manifest exposes the model" % id)
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		return {"id": id, "error": "regional_job_missing"}
	var model_resource := load(model_path) as Resource
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
	_check(not execution.has("error"), "%s regional preparation succeeds" % id)
	_check(bool(execution.get("complete", false)), "%s regional preparation completes within bounded stages" % id)
	var wheel_mount_usec := _stage_usec(stage_rows, "wheel_mount")
	_check(wheel_mount_usec > 0, "%s regional preparation reports wheel_mount" % id)
	_check(wheel_mount_usec <= STAGE_BUDGET_USEC, "%s wheel_mount stays within 6 ms, got %.3f ms" % [id, wheel_mount_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == prepared_hits_before + 1, "%s wheel_mount reuses prepared clearance without polygon carving" % id)
	var preparation: Dictionary = execution.get("preparation", {})
	_check((preparation.get("unsafe_reference_properties", PackedStringArray()) as PackedStringArray).is_empty(), "%s publishes no live operational Node references" % id)
	var region_report := CACHE.finish_region_session(session, false)
	await process_frame

	# Verify exact equivalence before batching. This isolates the prepared wheel
	# resource from harmless vertex round-off introduced when static surfaces are
	# fused into cache batches.
	CACHE._deferred_constructor_paths[model_path] = 1
	var authored := (model_resource as Script).new() as Node3D
	CACHE._deferred_constructor_paths.erase(model_path)
	authored.call("build")
	root.add_child(authored)
	var authored_rig := WHEEL_RIG.new()
	var authored_mounted := authored_rig.mount(authored)
	_check(authored_mounted and authored_rig.pivots.size() == 4, "%s authored prepared form mounts four wheels" % id)
	_check(_visual_signature(authored, 5) == int(prepared.get_meta("visual_signature", 0)), "%s prepared resource preserves exact authored geometry/material signature" % id)
	_check(_triangle_count(authored) == int(prepared.get_meta("triangle_count", 0)), "%s prepared resource preserves authored triangle count" % id)

	# Restore the published cache entry and prove the gameplay instance keeps the
	# same visual/damage/material contracts, then remount its live wheel pivots.
	var script := model_resource as Script
	var live := script.new() as Node3D
	root.add_child(live)
	_check(bool(live.get_meta("vehicle_prepared_wheel_wells", false)), "%s cache restore keeps prepared wheel metadata" % id)
	_check(int(live.get_meta("vehicle_wheel_clearance_signature", 0)) == int(prepared.get_meta("wheel_clearance_signature", 0)), "%s cache restore keeps prepared clearance signature" % id)
	var runtime_hits_before := CLEARANCE.prepared_hits
	var started := Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var runtime_mount_usec := Time.get_ticks_usec() - started
	_check(live_mounted and live_rig.pivots.size() == 4, "%s restores four articulated 3D wheels" % id)
	_check(runtime_mount_usec <= STAGE_BUDGET_USEC, "%s cached runtime wheel mount stays within 6 ms, got %.3f ms" % [id, runtime_mount_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == runtime_hits_before + 1, "%s cached runtime mount still skips polygon carving" % id)
	_check(_visual_signature(live, 4) == _visual_signature(authored, 4), "%s cache batching preserves geometry/material signature at 0.1 mm" % id)
	_check(_triangle_count(live) == int(prepared.get_meta("triangle_count", 0)), "%s prepared path preserves triangle count" % id)
	var capture_path := ""
	if _capture_requested():
		capture_path = await _capture_live_model(live, id)
		_check(not capture_path.is_empty(), "%s rendered inspection capture saves successfully" % id)

	var sibling := script.new() as Node3D
	root.add_child(sibling)
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "%s keeps paint independent per cache restore" % id)
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "%s repaint cannot recolor another instance" % id)
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "%s prepared paint remains visible and non-black" % id)

	var originals: Dictionary = live.get("originals")
	_check(not originals.is_empty(), "%s keeps repair baselines for damageable body meshes" % id)
	if live.has_method("apply_impact") and live.has_method("repair"):
		live.call("apply_impact", Vector3(0.55, 0.80, -1.0), Vector3(-1.0, 0.0, 0.0), 12.0)
		_check(int(live.get("impact_count")) == 1, "%s prepared body still accepts damage" % id)
		live.call("repair")
		_check(int(live.get("impact_count")) == 0 and (live.get("damaged_vertices") as Dictionary).is_empty(), "%s repair restores prepared body baseline" % id)

	var row := {
		"id": id,
		"path": model_path,
		"prepared_meshes": int(prepared.get_meta("mesh_count", 0)),
		"triangles": int(prepared.get_meta("triangle_count", 0)),
		"regional_wheel_mount_usec": wheel_mount_usec,
		"regional_wheel_mount_ms": wheel_mount_usec / 1000.0,
		"runtime_restore_mount_usec": runtime_mount_usec,
		"runtime_restore_mount_ms": runtime_mount_usec / 1000.0,
		"regional_stage_rows": stage_rows,
		"regional_over_budget_stages": region_report.get("over_budget_stages", []),
		"wheel_centres": live_rig.pivots.size(),
		"damage_parts": originals.size(),
		"unsafe_reference_properties": preparation.get("unsafe_reference_properties", PackedStringArray()),
		"capture_path": capture_path,
	}
	authored.free()
	live.free()
	sibling.free()
	return row


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


func _job_for_path(jobs: Array[Dictionary], model_path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == model_path:
			return job
	return {}


func _stage_usec(rows: Array[Dictionary], wanted: String) -> int:
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			return int(row.get("actual_usec", 0))
	return 0


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
					points.append(_point_key(point, decimals))
				points.sort()
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(child, world_transform, triangles, decimals)


func _point_key(point: Vector3, decimals: int) -> String:
	var scale := pow(10.0, decimals)
	return "%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)]


func _capture_requested() -> bool:
	return OS.get_cmdline_user_args().has("capture")


func _capture_live_model(model: Node3D, id: String) -> String:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 480)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("9eabb8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	viewport.add_child(world_environment)

	var camera := Camera3D.new()
	camera.fov = 34.0
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(4.8, 3.1, -6.2), Vector3(0.0, 1.0, 0.0), Vector3.UP)
	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.35
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	viewport.add_child(key_light)

	model.reparent(viewport)
	model.position = Vector3.ZERO
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output_dir := ProjectSettings.globalize_path("res://.godot/courier_summit_prepared")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("%s.png" % id)
	var image := viewport.get_texture().get_image()
	var error := image.save_png(output_path)
	model.reparent(root)
	model.position = Vector3.ZERO
	viewport.free()
	return output_path if error == OK else ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
