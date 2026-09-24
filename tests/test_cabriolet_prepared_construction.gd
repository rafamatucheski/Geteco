extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/CabrioletModel.gd"
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const WHEEL_CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const MATERIAL_KEY_META := &"cabriolet_material_key"
const EXPECTED_GEOMETRY_SIGNATURE := 887016387
const EXPECTED_MESHES := 39
const EXPECTED_TRIANGLES := 56358
const FRAME_BUDGET_MS := 1000.0 / 60.0

var failures: Array[String] = []
var stage: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	stage = Node3D.new()
	stage.name = "CabrioletPreparedConstructionTest"
	root.add_child(stage)
	current_scene = stage
	for _frame in 3:
		await process_frame
	var renderer_bootstrap_ms = null
	if rendered:
		renderer_bootstrap_ms = await _warm_renderer()

	var viewport := _make_viewport()
	var started := Time.get_ticks_usec()
	var script := load(MODEL_PATH) as Script
	var resource_load_ms := _elapsed_ms(started)
	check(script != null, "Cabriolet script and prepared resource load")
	if script == null:
		_finish({"resource_load_ms": resource_load_ms})
		return

	started = Time.get_ticks_usec()
	var model := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	viewport.add_child(model)
	var add_to_tree_ms := _elapsed_ms(started)
	var wheel_centres := _wheel_centres(model)
	var geometry_signature := _geometry_signature(model)
	check(geometry_signature == EXPECTED_GEOMETRY_SIGNATURE, "Prepared Cabriolet preserves exact carved/batched material geometry")
	check(_mesh_count(model) == EXPECTED_MESHES, "Prepared Cabriolet preserves %d presentation meshes" % EXPECTED_MESHES)
	check(_triangle_count(model) == EXPECTED_TRIANGLES, "Prepared Cabriolet preserves %d presented triangles" % EXPECTED_TRIANGLES)
	check(wheel_centres.size() == 4, "Prepared Cabriolet preserves four authored wheel centres")
	check(bool(model.call("is_open_top")), "Cabriolet remains open-top")

	var prepared_hits_before := WHEEL_CLEARANCE.prepared_hits
	started = Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var wheel_mounted: bool = rig.mount(model)
	var wheel_mount_ms := _elapsed_ms(started)
	check(wheel_mounted and rig.pivots.size() == 4, "Prepared Cabriolet mounts all four articulated wheels")
	check(WHEEL_CLEARANCE.prepared_hits == prepared_hits_before + 1, "Wheel mount recognizes the baked clearance signature")

	started = Time.get_ticks_usec()
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	var mesh_batch_ms := _elapsed_ms(started)
	check(batched_removed == 0, "Prepared Cabriolet does not repeat mesh fusion")
	check(_geometry_signature(model) == EXPECTED_GEOMETRY_SIGNATURE, "Mount/batch preserve the exact presented geometry")
	check(wheel_mount_ms < FRAME_BUDGET_MS, "Prepared wheel mount stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, wheel_mount_ms])
	check(mesh_batch_ms < FRAME_BUDGET_MS, "Prepared batching stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, mesh_batch_ms])

	var first_presented_ms = null
	if rendered:
		started = Time.get_ticks_usec()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		first_presented_ms = _elapsed_ms(started)
		check(first_presented_ms < FRAME_BUDGET_MS, "Prepared first presentation stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, first_presented_ms])

	check((model.get("originals") as Dictionary).size() > 0, "Damage system captures prepared painted body meshes")
	check((model.get("lamp_sources") as Dictionary).size() > 0, "Damage system captures prepared lamps")
	model.call("apply_impact", Vector3(0.70, 0.75, -1.2), Vector3(-1.0, 0.0, 0.0), 12.0)
	check(int(model.get("impact_count")) == 1, "Prepared Cabriolet accepts body damage")
	model.call("repair")
	check(int(model.get("impact_count")) == 0, "Prepared Cabriolet repairs body damage")
	check(_geometry_signature(model) == EXPECTED_GEOMETRY_SIGNATURE, "Repair restores exact prepared geometry")

	started = Time.get_ticks_usec()
	var sibling := script.new() as Node3D
	viewport.add_child(sibling)
	var warm_construction_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var sibling_rig := WHEEL_RIG.new()
	var sibling_mounted: bool = sibling_rig.mount(sibling)
	var warm_wheel_mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var warm_batched_removed: int = MESH_BATCHER.batch_model(sibling)
	var warm_mesh_batch_ms := _elapsed_ms(started)
	var warm_first_presented_ms = null
	if rendered:
		started = Time.get_ticks_usec()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		warm_first_presented_ms = _elapsed_ms(started)
	var warm_model_pipeline_ms := warm_construction_ms + warm_wheel_mount_ms + warm_mesh_batch_ms + (float(warm_first_presented_ms) if warm_first_presented_ms != null else 0.0)
	check(sibling_mounted and sibling_rig.pivots.size() == 4, "Warm Cabriolet mounts all four wheels")
	check(warm_batched_removed == 0, "Warm Cabriolet does not repeat mesh fusion")
	if rendered:
		check(warm_model_pipeline_ms < FRAME_BUDGET_MS, "Warm gameplay pipeline stays below %.2f ms, got %.3f ms" % [FRAME_BUDGET_MS, warm_model_pipeline_ms])
	var model_paint := model.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	check(model_paint != null and sibling_paint != null and model_paint != sibling_paint, "Every Cabriolet keeps independent paint")
	if model_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		model_paint.albedo_color = Color.MAGENTA
		check(sibling_paint.albedo_color == sibling_color, "Repainting one Cabriolet cannot recolor another")

	var construction_ms := constructor_ms + add_to_tree_ms
	var model_pipeline_ms := construction_ms + wheel_mount_ms + mesh_batch_ms + (float(first_presented_ms) if first_presented_ms != null else 0.0)
	var cold_end_to_end_ms := resource_load_ms + model_pipeline_ms
	var result := {
		"kind": "rendered" if rendered else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if rendered else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"renderer_bootstrap_ms": renderer_bootstrap_ms,
		"resource_load_ms": resource_load_ms,
		"constructor_ms": constructor_ms,
		"add_to_tree_ms": add_to_tree_ms,
		"construction_ms": construction_ms,
		"wheel_mount_ms": wheel_mount_ms,
		"mesh_batch_ms": mesh_batch_ms,
		"first_presented_ms": first_presented_ms,
		"cold_end_to_end_ms": cold_end_to_end_ms,
		"model_pipeline_ms": model_pipeline_ms,
		"warm_construction_ms": warm_construction_ms,
		"warm_wheel_mount_ms": warm_wheel_mount_ms,
		"warm_mesh_batch_ms": warm_mesh_batch_ms,
		"warm_first_presented_ms": warm_first_presented_ms,
		"warm_model_pipeline_ms": warm_model_pipeline_ms,
		"batched_nodes_removed": batched_removed,
		"geometry_signature": geometry_signature,
		"meshes": _mesh_count(model),
		"triangles": _triangle_count(model),
		"wheel_centres": wheel_centres.size(),
	}
	model.free()
	sibling.free()
	viewport.free()
	_finish(result)


func _warm_renderer() -> float:
	var viewport := _make_viewport()
	viewport.name = "RendererBootstrapControl"
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


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "CabrioletViewport"
	viewport.size = Vector2i(384, 384)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("20242b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.0
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(7.5, 6.0, 9.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.75, 0.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.0
	viewport.add_child(camera)
	return viewport


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
		var material_key := String(part.get_meta(MATERIAL_KEY_META, ""))
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
				entries.append("%s:%s" % [material_key, "|".join(points)])
	for child in node.get_children():
		_collect_geometry(child, world_transform, entries)


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("CABRIOLET_PREPARED_CONSTRUCTION ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)
