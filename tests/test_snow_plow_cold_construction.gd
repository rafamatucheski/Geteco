extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/models/SnowPlowModel.gd"
const GEOMETRY_RESOURCE_PATH := "res://prototypes/living_cast/models/SnowPlowGeometry.scn"
const WHEEL_WELL_RESOURCE_PATH := "res://prototypes/living_cast/models/SnowPlowWheelWells.res"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0

var failures: Array[String] = []
var fixture: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	fixture = SubViewport.new()
	fixture.name = "SnowPlowColdConstructionFixture"
	fixture.size = Vector2i(512, 512)
	fixture.own_world_3d = true
	fixture.transparent_bg = true
	fixture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(fixture)
	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.look_at_from_position(Vector3(7.0, 6.0, -9.0), Vector3(0.0, 0.9, -0.3), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.shadow_enabled = true
	fixture.add_child(sun)
	_check(ResourceLoader.exists(GEOMETRY_RESOURCE_PATH, "PackedScene"), "SnowPlow baked geometry resource exists")
	var geometry_resource := load(GEOMETRY_RESOURCE_PATH) as PackedScene
	_check(geometry_resource != null, "SnowPlow baked geometry resource loads")
	if geometry_resource != null:
		var geometry_root := geometry_resource.instantiate() as Node3D
		_check(int(geometry_root.get_meta("format_version", 0)) == 1, "SnowPlow geometry format is supported")
		_check(String(geometry_root.get_meta("model_id", "")) == "snow_plow_truck", "SnowPlow geometry belongs to the model")
		_check(int(geometry_root.get_meta("mesh_count", 0)) == 46, "SnowPlow geometry contains the 46 prepared mesh nodes")
		_check(int(geometry_root.get_meta("visual_signature", 0)) == 3643091624, "SnowPlow geometry records the exact baseline signature")
		_check(int(geometry_root.get_meta("triangle_count", 0)) == 38642, "SnowPlow geometry records the exact triangle count")
		var role_counts: Dictionary = geometry_root.get_meta("material_role_counts", {})
		_check(role_counts.has("plow_steel") and role_counts.has("plow_edge"), "SnowPlow baked geometry keeps blade face and cutting edge")
		geometry_root.free()
	_check(ResourceLoader.exists(WHEEL_WELL_RESOURCE_PATH, "Resource"), "SnowPlow baked wheel-well resource exists")
	var wheel_well_resource := load(WHEEL_WELL_RESOURCE_PATH) as Resource
	_check(wheel_well_resource != null, "SnowPlow baked wheel-well resource loads")
	if wheel_well_resource != null:
		_check(int(wheel_well_resource.get_meta("format_version", 0)) == 1, "SnowPlow wheel-well format is supported")
		_check(String(wheel_well_resource.get_meta("model_id", "")) == "snow_plow_truck", "SnowPlow wheel-well resource belongs to the model")
		_check(int(wheel_well_resource.get_meta("mesh_count", 0)) == 5, "SnowPlow wheel-well resource has every carved mesh")
		_check(int(wheel_well_resource.get_meta("visual_signature", 0)) == 3643091624, "SnowPlow wheel-well resource records the exact baseline signature")
		_check(int(wheel_well_resource.get_meta("triangle_count", 0)) == 38642, "SnowPlow wheel-well resource records the exact triangle count")

	_reset_all_caches()
	var started := Time.get_ticks_usec()
	var script := load(MODEL_PATH) as Script
	var script_load_ms := _elapsed_ms(started)
	_check(script != null, "SnowPlow script loads")
	if script == null:
		_finish({"script_load_ms": script_load_ms})
		return

	started = Time.get_ticks_usec()
	var cold := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	fixture.add_child(cold)
	var ready_ms := _elapsed_ms(started)
	var raw_meshes := _mesh_count(cold)
	var raw_unique_meshes := _unique_mesh_count(cold)
	var wheel_centers := _wheel_centers(cold)

	started = Time.get_ticks_usec()
	var cold_rig := WHEEL_RIG.new()
	var mounted := cold_rig.mount(cold)
	var mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var removed := BATCHER.batch_model(cold)
	var batch_ms := _elapsed_ms(started)
	var prepared_signature := _visual_signature(cold)
	var prepared_triangles := _triangle_count(cold)
	var cold_first_presented_ms = null
	if DisplayServer.get_name() != "headless":
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		cold_first_presented_ms = _elapsed_ms(started)
	_check(mounted and cold_rig.pivots.size() == 6, "SnowPlow mounts six articulated wheel rigs")
	_check(removed == 0 and bool(cold.get_meta("vehicle_mesh_batched", false)), "SnowPlow ships in the exact prepared batching form")
	_check(wheel_centers.size() == 6, "SnowPlow preserves all six authored wheel centres")
	_check(constructor_ms + ready_ms + mount_ms + batch_ms < FRAME_BUDGET_MS, "SnowPlow cold CPU pipeline stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, constructor_ms + ready_ms + mount_ms + batch_ms])
	cold.free()

	_reset_all_caches()
	started = Time.get_ticks_usec()
	var prewarm_report: Dictionary = CACHE._prepare_model_template(MODEL_PATH, fixture)
	var prewarm_ms := _elapsed_ms(started)
	_check(bool(prewarm_report.get("wheel_mounted", false)), "SnowPlow prewarm mounts its wheels")
	_check(int(prewarm_report.get("batched_removed", 0)) == 0, "SnowPlow prewarm does not repeat its baked static batching")
	_check(bool(prewarm_report.get("captured", false)), "SnowPlow prewarm captures a prepared template")
	_check(prewarm_ms < FRAME_BUDGET_MS, "SnowPlow isolated prewarm stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, prewarm_ms])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

	started = Time.get_ticks_usec()
	var live := script.new() as Node3D
	fixture.add_child(live)
	var restore_add_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var restore_mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var live_removed := 0
	if not bool(live.get_meta("vehicle_mesh_batched", false)):
		live_removed = BATCHER.batch_model(live)
	var restore_batch_ms := _elapsed_ms(started)
	var runtime_ms := restore_add_ms + restore_mount_ms + restore_batch_ms
	_check(live_mounted and live_rig.pivots.size() == 6, "Prepared SnowPlow restores six articulated wheels")
	_check(live_removed == 0, "Prepared SnowPlow does not repeat mesh batching")
	_check(_visual_signature(live) == prepared_signature, "Prepared SnowPlow preserves the cold visual signature")
	_check(runtime_ms < FRAME_BUDGET_MS, "Prepared SnowPlow restore path stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, runtime_ms])

	var sibling := script.new() as Node3D
	fixture.add_child(sibling)
	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "SnowPlow paint stays independent per instance")
	if live_paint != null and sibling_paint != null:
		var live_color := live_paint.albedo_color
		var sibling_color := sibling_paint.albedo_color
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "Repainting one SnowPlow cannot recolor another")
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "SnowPlow paint remains non-black and opaque")
		live_paint.albedo_color = live_color
	sibling.hide()

	var runtime_first_presented_ms = null
	if DisplayServer.get_name() != "headless":
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		runtime_first_presented_ms = _elapsed_ms(started)
		_check(runtime_first_presented_ms < FRAME_BUDGET_MS, "Prepared SnowPlow first presented frame stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, runtime_first_presented_ms])
		var capture_path := _capture_path()
		if not capture_path.is_empty():
			var image := fixture.get_texture().get_image()
			_check(image.save_png(capture_path) == OK, "SnowPlow visual capture saves")

	var originals: Dictionary = live.get("originals")
	_check(not originals.is_empty(), "Prepared SnowPlow retains deformable body parts")
	if live.has_method("apply_impact"):
		live.apply_impact(Vector3(0.75, 0.8, -2.0), Vector3(-1.0, 0.0, 0.0), 12.0)
		_check(int(live.get("impact_count")) == 1, "Prepared SnowPlow still accepts gameplay damage")

	var result := {
		"kind": "rendered" if DisplayServer.get_name() != "headless" else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"script_load_ms": script_load_ms,
		"constructor_ms": constructor_ms,
		"ready_ms": ready_ms,
		"mount_ms": mount_ms,
		"batch_ms": batch_ms,
		"cold_pipeline_ms": constructor_ms + ready_ms + mount_ms + batch_ms,
		"cold_first_presented_ms": cold_first_presented_ms,
		"prewarm_ms": prewarm_ms,
		"runtime_restore_add_ms": restore_add_ms,
		"runtime_mount_ms": restore_mount_ms,
		"runtime_batch_ms": restore_batch_ms,
		"runtime_pipeline_ms": runtime_ms,
		"runtime_first_presented_ms": runtime_first_presented_ms,
		"prepared_signature": prepared_signature,
		"prepared_triangles": prepared_triangles,
		"raw_meshes": raw_meshes,
		"raw_unique_meshes": raw_unique_meshes,
		"cold_batched_removed": removed,
		"wheel_centres": wheel_centers.size(),
		"damage_parts": originals.size(),
	}
	live.free()
	sibling.free()
	_finish(result)


func _reset_all_caches() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _wheel_centers(model: Node3D) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center"):
			var center: Vector3 = node.get_meta("wheel_center")
			if not centers.has(center):
				centers.append(center)
	return centers


func _mesh_count(parent: Node) -> int:
	var count := 1 if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null else 0
	for child in parent.get_children():
		count += _mesh_count(child)
	return count


func _unique_mesh_count(parent: Node) -> int:
	var ids: Dictionary = {}
	_collect_mesh_ids(parent, ids)
	return ids.size()


func _collect_mesh_ids(parent: Node, ids: Dictionary) -> void:
	if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null:
		ids[(parent as MeshInstance3D).mesh.get_instance_id()] = true
	for child in parent.get_children():
		_collect_mesh_ids(child, ids)


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


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _capture_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("capture_path="):
			return argument.trim_prefix("capture_path=")
	return ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("SNOW_PLOW_COLD_CONSTRUCTION ", JSON.stringify(result))
	if is_instance_valid(fixture):
		fixture.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
