extends SceneTree

## One-pass rendered profiler for Harbor vehicle models that deliberately remain
## outside VehicleGeometryCache's restore contract. Common renderer setup is
## warmed once, while every model script and constructor stays cold in this
## process. This makes the ranking compare model work instead of whichever case
## happened to initialize the rendering backend first.

const FRAME_BUDGET_MS := 1000.0 / 60.0
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const MESH_BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const CASES: Array[Dictionary] = [
	{"id": "regional_intercity_coach", "path": "res://geodata/transit/RegionalIntercityCoachModel.gd"},
	{"id": "police_motorcycle", "path": "res://police/PoliceMotorcycleModel.gd"},
	{"id": "boss_muscle", "path": "res://prototypes/living_cast/BossMuscleModel.gd"},
	{"id": "cabriolet", "path": "res://prototypes/living_cast/CabrioletModel.gd"},
	{"id": "medic_box", "path": "res://prototypes/living_cast/models/MedicBoxModel.gd"},
	{"id": "rescue_pumper", "path": "res://prototypes/living_cast/models/RescuePumperModel.gd"},
	{"id": "harbor_container_truck", "path": "res://world/harbor/HarborContainerTruckModel.gd"},
	{"id": "harbor_transit_bus", "path": "res://world/harbor/HarborTransitBusModel.gd"},
	{"id": "port_boss_roadster", "path": "res://world/harbor/PortBossRoadsterModel.gd"},
	{"id": "port_forklift", "path": "res://world/harbor/PortForkliftModel.gd"},
	{"id": "urban_bus", "path": "res://world/harbor/urban_transit/UrbanBusModel.gd"},
	{"id": "urban_bus_trailer", "path": "res://world/harbor/urban_transit/UrbanBusTrailerModel.gd"},
]

var failures: Array[String] = []
var stage: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This profiler requires a rendered display; headless cannot measure first presentation.")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	stage = Node3D.new()
	stage.name = "ExternalHarborVehicleProfile"
	root.add_child(stage)
	current_scene = stage

	for _frame in 3:
		await process_frame
	var renderer_warmup_ms := await _warm_renderer()
	var rows: Array[Dictionary] = []
	for case_data in CASES:
		rows.append(await _profile_case(case_data))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.model_pipeline_ms) > float(b.model_pipeline_ms)
	)

	var over_budget: Array[String] = []
	for row in rows:
		if float(row.model_pipeline_ms) > FRAME_BUDGET_MS:
			over_budget.append(String(row.id))
	var report := {
		"kind": "rendered",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [root.size.x, root.size.y],
		"frame_budget_ms": FRAME_BUDGET_MS,
		"renderer_warmup_ms": renderer_warmup_ms,
		"ranking": rows,
		"over_budget": over_budget,
		"failures": failures,
	}
	print("EXTERNAL_HARBOR_MODEL_PROFILE ", JSON.stringify(report))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _warm_renderer() -> float:
	var viewport := _make_viewport("RendererWarmup")
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


func _profile_case(case_data: Dictionary) -> Dictionary:
	var id := String(case_data.id)
	var path := String(case_data.path)
	var viewport := _make_viewport("Profile_%s" % id)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)

	var started := Time.get_ticks_usec()
	var script := load(path) as Script
	var resource_load_ms := _elapsed_ms(started)
	if script == null:
		failures.append("Could not load %s" % path)
		viewport.free()
		return {"id": id, "path": path, "cold_end_to_end_ms": INF}

	started = Time.get_ticks_usec()
	var model := script.new() as Node3D
	var constructor_ms := _elapsed_ms(started)
	if model == null:
		failures.append("Could not instantiate %s" % path)
		viewport.free()
		return {"id": id, "path": path, "cold_end_to_end_ms": INF}

	started = Time.get_ticks_usec()
	viewport.add_child(model)
	var add_to_tree_ms := _elapsed_ms(started)
	var authored_wheel_centres := _wheel_centres(model)
	started = Time.get_ticks_usec()
	var rig := WHEEL_RIG.new()
	var wheel_mounted: bool = rig.mount(model)
	var wheel_mount_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var batched_removed: int = MESH_BATCHER.batch_model(model)
	var mesh_batch_ms := _elapsed_ms(started)
	var node_count := _node_count(model)
	var mesh_count := _mesh_count(model)
	var triangle_count := _triangle_count(model)

	started = Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var first_presented_ms := _elapsed_ms(started)
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport_cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
	var viewport_gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	var construction_ms := constructor_ms + add_to_tree_ms
	var model_pipeline_ms := construction_ms + wheel_mount_ms + mesh_batch_ms + first_presented_ms
	var cold_end_to_end_ms := resource_load_ms + model_pipeline_ms

	var row := {
		"id": id,
		"path": path,
		"resource_load_ms": resource_load_ms,
		"constructor_ms": constructor_ms,
		"add_to_tree_ms": add_to_tree_ms,
		"construction_ms": construction_ms,
		"wheel_marker_centres": authored_wheel_centres.size(),
		"wheel_mounted": wheel_mounted,
		"wheel_mount_ms": wheel_mount_ms,
		"batched_nodes_removed": batched_removed,
		"mesh_batch_ms": mesh_batch_ms,
		"first_presented_ms": first_presented_ms,
		"model_pipeline_ms": model_pipeline_ms,
		"cold_end_to_end_ms": cold_end_to_end_ms,
		"viewport_cpu_ms": viewport_cpu_ms,
		"viewport_gpu_ms": viewport_gpu_ms,
		"nodes": node_count,
		"meshes": mesh_count,
		"triangles": triangle_count,
	}
	print("EXTERNAL_HARBOR_MODEL_ROW ", JSON.stringify(row))
	viewport.free()
	await process_frame
	await process_frame
	return row


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2i(384, 384)
	viewport.transparent_bg = false
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
	sun.shadow_enabled = false
	viewport.add_child(sun)

	var camera := Camera3D.new()
	camera.position = Vector3(7.5, 6.0, 9.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, 0.0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	viewport.add_child(camera)
	return viewport


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _wheel_centres(model: Node3D) -> Array[Vector3]:
	var centres: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center"):
			var centre: Vector3 = node.get_meta("wheel_center")
			if not centres.has(centre):
				centres.append(centre)
	return centres


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


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0
