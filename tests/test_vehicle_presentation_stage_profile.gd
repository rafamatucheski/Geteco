extends SceneTree

## Decomposes the common 3D vehicle presentation path without changing runtime
## code. Headless runs are structural CPU profiles; only a rendered run reports
## first-frame presentation latency and viewport CPU/GPU timings.
##
## Short rendered invocation (only with no other Godot process running):
##   Godot --path D:/geteco/game --script res://tests/test_vehicle_presentation_stage_profile.gd
## Structural invocation:
##   Godot --headless --path D:/geteco/game --script res://tests/test_vehicle_presentation_stage_profile.gd

const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const CONTACT_SHADOW := preload("res://systems/ContactShadow.gd")

const CASES := [
	{
		"id": "union_sedan",
		"path": "res://prototypes/living_cast/models/UnionSedanModel.gd",
		"target_length": 82.0,
		"target_width": 34.0,
	},
	{
		"id": "american_flatbed",
		"path": "res://prototypes/living_cast/models/AmericanFlatbedModel.gd",
		"target_length": 136.0,
		"target_width": 48.0,
	},
]

const PIXELS_PER_METRE := 74.0 / 4.46
const FRAME_BUDGET_MS := 1000.0 / 60.0

class VehiclePresentationHost:
	extends Node2D
	var visual: Sprite2D
	var body_viewport: SubViewport

var failures: Array[String] = []
var rendered := false
var stage: Node2D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size

	var world := Node2D.new()
	world.name = "VehiclePresentationStageProfile"
	root.add_child(world)
	current_scene = world
	var camera_2d := Camera2D.new()
	world.add_child(camera_2d)
	camera_2d.make_current()
	stage = Node2D.new()
	stage.name = "Samples"
	world.add_child(stage)

	# Let autoload node-added hooks settle outside every measured stage.
	for _frame in 3:
		await process_frame

	var rows: Array[Dictionary] = []
	for case_data in CASES:
		var model_path := String(case_data.path)
		CACHE._models.erase(model_path)
		CACHE._prepared.erase(model_path)
		var cold := await _profile_sample(case_data, "cold")
		rows.append(cold)
		var warm := await _profile_sample(case_data, "warm")
		rows.append(warm)
		check(not bool(cold.cache_hit), "%s cold sample must build instead of restore" % case_data.id)
		check(bool(warm.cache_hit), "%s warm sample must restore from VehicleGeometryCache" % case_data.id)
		check(int(cold.wheel_count) >= 4, "%s cold sample must mount authored 3D wheels" % case_data.id)
		check(int(warm.wheel_count) == int(cold.wheel_count), "%s warm sample must preserve every wheel" % case_data.id)
		check(bool(cold.has_contact_shadow) and bool(cold.has_projected_vehicle_shadow), "%s cold sample must bind both vehicle shadows" % case_data.id)
		check(bool(warm.has_contact_shadow) and bool(warm.has_projected_vehicle_shadow), "%s warm sample must bind both vehicle shadows" % case_data.id)

	var report := {
		"kind": "rendered" if rendered else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if rendered else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"rows": rows,
		"largest_cpu_stage": _largest_stage(rows),
		"largest_post_model_stage": _largest_stage(rows, ["resource_load_ms", "model_new_or_cache_restore_ms"]),
		"largest_warm_stage": _largest_stage(rows, [], "warm"),
		"failures": failures,
	}
	print("VEHICLE_PRESENTATION_STAGE_PROFILE ", JSON.stringify(report))
	if not rendered:
		print("VEHICLE_PRESENTATION_STAGE_PROFILE_NOTE headless is structural only; first_presented_frame_ms and GPU/viewport render time are intentionally not measured")

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _profile_sample(case_data: Dictionary, temperature: String) -> Dictionary:
	var row: Dictionary = {
		"vehicle": String(case_data.id),
		"temperature": temperature,
		"cache_hit": false,
		"rendered": rendered,
	}
	var host := VehiclePresentationHost.new()
	host.name = "%s_%s" % [case_data.id, temperature]
	stage.add_child(host)
	var display := Sprite2D.new()
	display.name = "Visual"
	host.add_child(display)
	host.visual = display

	var target_length := float(case_data.target_length)
	var target_width := float(case_data.target_width)
	var viewport_size := 256 if target_length > 100.0 else 192
	var camera_size := maxf(6.0, (target_length / PIXELS_PER_METRE) * 1.25)
	var started := Time.get_ticks_usec()
	var shadow_cached_before := CONTACT_SHADOW._vehicle_texture != null
	CONTACT_SHADOW.add_vehicle(host, Vector2(target_length, target_width))
	row["contact_shadow_seed_ms"] = _elapsed_ms(started)
	row["contact_shadow_shared_texture_was_cached"] = shadow_cached_before

	started = Time.get_ticks_usec()
	var model_resource = load(String(case_data.path))
	row["resource_load_ms"] = _elapsed_ms(started)
	check(model_resource != null, "%s model resource must load" % case_data.id)
	if model_resource == null:
		host.queue_free()
		return row

	started = Time.get_ticks_usec()
	var viewport := SubViewport.new()
	viewport.name = "Vehicle3DRender"
	viewport.size = Vector2i(viewport_size, viewport_size)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(viewport)
	host.body_viewport = viewport
	row["subviewport_create_config_add_ms"] = _elapsed_ms(started)

	var hits_before := CACHE.hits
	var misses_before := CACHE.misses
	started = Time.get_ticks_usec()
	var model := model_resource.new() as Node3D
	row["model_new_or_cache_restore_ms"] = _elapsed_ms(started)
	row["cache_hit"] = CACHE.hits > hits_before
	row["cache_miss"] = CACHE.misses > misses_before

	started = Time.get_ticks_usec()
	viewport.add_child(model)
	row["model_add_to_subviewport_ms"] = _elapsed_ms(started)
	row["nodes_before_mount"] = _node_count(model)

	started = Time.get_ticks_usec()
	var rig = WHEEL_RIG.new()
	var mounted: bool = rig.mount(model)
	row["wheel_rig_mount_ms"] = _elapsed_ms(started)
	row["wheel_mounted"] = mounted
	row["wheel_count"] = rig.pivots.size()

	started = Time.get_ticks_usec()
	var lamp_mounts: Array[Vector3] = []
	var lens: Material = model.materials.get("headlight") as Material if "materials" in model else null
	for child in model.get_children():
		if child is MeshInstance3D and lens != null and child.material_override == lens:
			lamp_mounts.append(child.position)
	lamp_mounts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	if lamp_mounts.size() >= 2:
		lamp_mounts = [lamp_mounts[0], lamp_mounts[-1]]
	row["lamp_scan_ms"] = _elapsed_ms(started)
	row["lamp_mount_count"] = lamp_mounts.size()

	started = Time.get_ticks_usec()
	var already_batched := bool(model.get_meta("vehicle_mesh_batched", false))
	var batched_removed := 0
	if not already_batched:
		batched_removed = BATCHER.batch_model(model)
		model.set_meta("vehicle_mesh_batched", true)
	model.rotation.y = -PI * 0.5
	row["mesh_batch_ms"] = _elapsed_ms(started)
	row["batch_applicable"] = not already_batched
	row["batched_nodes_removed"] = batched_removed

	started = Time.get_ticks_usec()
	var camera := Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	camera.position = Vector3(0, 8, 4)
	camera.look_at(Vector3(0, 0.45, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = camera_size
	row["camera_create_config_add_ms"] = _elapsed_ms(started)

	started = Time.get_ticks_usec()
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.environment.ambient_light_color = Color.WHITE
	world_environment.environment.ambient_light_energy = 0.7
	viewport.add_child(world_environment)
	row["environment_create_config_add_ms"] = _elapsed_ms(started)

	started = Time.get_ticks_usec()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.0
	viewport.add_child(sun)
	row["directional_light_create_config_add_ms"] = _elapsed_ms(started)

	started = Time.get_ticks_usec()
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
	display.region_enabled = false
	display.centered = true
	camera.force_update_transform()
	display.offset = Vector2(viewport.size) * 0.5 - camera.unproject_position(Vector3.ZERO)
	display.scale = Vector2.ONE * (PIXELS_PER_METRE * camera_size / float(viewport_size))
	display.rotation = 0.0
	display.modulate = Color.WHITE
	display.visible = true
	row["texture_and_offset_ms"] = _elapsed_ms(started)

	started = Time.get_ticks_usec()
	CONTACT_SHADOW.add_vehicle(host, Vector2(target_length, target_width))
	row["contact_shadow_bind_ms"] = _elapsed_ms(started)
	row["contact_shadow_total_ms"] = float(row.contact_shadow_seed_ms) + float(row.contact_shadow_bind_ms)
	row["has_contact_shadow"] = host.has_node("ContactShadow")
	row["has_projected_vehicle_shadow"] = display.has_node("VehicleShadow")
	row["nodes_after_pipeline"] = _node_count(viewport)
	row["sync_pipeline_total_ms"] = _sum_sync_stages(row)

	if rendered:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		started = Time.get_ticks_usec()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		row["first_presented_frame_ms"] = _elapsed_ms(started)
		await process_frame
		await RenderingServer.frame_post_draw
		row["viewport_render_cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		row["viewport_render_gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	else:
		row["first_presented_frame_ms"] = null
		row["viewport_render_cpu_ms"] = null
		row["viewport_render_gpu_ms"] = null

	host.queue_free()
	await process_frame
	return row


func _sum_sync_stages(row: Dictionary) -> float:
	var total := 0.0
	for key in _sync_stage_keys():
		total += float(row.get(key, 0.0))
	return total


func _largest_stage(rows: Array[Dictionary], excluded: Array = [], temperature := "") -> Dictionary:
	var result := {"vehicle": "", "temperature": "", "stage": "", "ms": 0.0}
	for row in rows:
		if not temperature.is_empty() and String(row.temperature) != temperature:
			continue
		for key in _sync_stage_keys():
			if key in excluded:
				continue
			var value := float(row.get(key, 0.0))
			if value > float(result.ms):
				result = {
					"vehicle": String(row.vehicle),
					"temperature": String(row.temperature),
					"stage": key,
					"ms": value,
				}
	return result


func _sync_stage_keys() -> Array[String]:
	return [
		"contact_shadow_seed_ms",
		"resource_load_ms",
		"subviewport_create_config_add_ms",
		"model_new_or_cache_restore_ms",
		"model_add_to_subviewport_ms",
		"wheel_rig_mount_ms",
		"lamp_scan_ms",
		"mesh_batch_ms",
		"camera_create_config_add_ms",
		"environment_create_config_add_ms",
		"directional_light_create_config_add_ms",
		"texture_and_offset_ms",
		"contact_shadow_bind_ms",
	]


func _elapsed_ms(started_usec: int) -> float:
	return (Time.get_ticks_usec() - started_usec) / 1000.0


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
