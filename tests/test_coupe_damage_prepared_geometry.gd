extends SceneTree

const MODEL_PATH := "res://prototypes/living_cast/CoupeDamageModel.gd"
const PREPARED_GEOMETRY_PATH := "res://prototypes/living_cast/CoupeDamagePreparedGeometry.scn"
const CAPTURE_PATH := "res://_codex_diag/coupe-damage-prepared.png"
const CACHE := preload("res://cars/VehicleGeometryCache.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const STATIC_VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")
const STAGE_BUDGET_USEC := 6000
const MAX_STAGE_SAFETY_STEPS := 512
const EXPECTED_SIGNATURE := 909733885
const EXPECTED_MESHES := 38
const EXPECTED_TRIANGLES := 61039

var failures: Array[String] = []
var stage_root: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("CoupeDamage prepared contract requires a rendered display")
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	stage_root = Node3D.new()
	stage_root.name = "CoupeDamagePreparedContract"
	root.add_child(stage_root)
	current_scene = stage_root
	for _frame in 3:
		await process_frame
	STATIC_VIEW.reset_global_graphics_prewarm_for_tests()
	var loading_session := STATIC_VIEW.begin_graphics_prewarm_loading_session()
	var global_bootstrap: Dictionary = await STATIC_VIEW.prewarm_graphics_backend(self, 3000, loading_session)
	_check(bool(global_bootstrap.get("ready", false)), "Global loading graphics bootstrap completes before Coupe measurement")
	var vehicle_material_bootstrap_ms := await _warm_renderer()
	_reset_runtime()

	var prepared_scene := load(PREPARED_GEOMETRY_PATH) as PackedScene
	_check(prepared_scene != null, "CoupeDamage integral prepared geometry loads")
	if prepared_scene == null:
		_finish({"error": "resource_missing"})
		return
	var prepared_template := prepared_scene.instantiate() as Node3D
	var prepared_signature := int(prepared_template.get_meta("coupe_damage_prepared_geometry_signature", 0))
	var prepared_meshes := int(prepared_template.get_meta("coupe_damage_prepared_meshes", 0))
	var prepared_triangles := int(prepared_template.get_meta("coupe_damage_prepared_triangles", 0))
	var clearance_signature := int(prepared_template.get_meta("vehicle_wheel_clearance_signature", 0))
	_check(prepared_template.get_script() == null, "CoupeDamage prepared root is scriptless")
	_check(prepared_signature == EXPECTED_SIGNATURE, "CoupeDamage prepared signature is fixed")
	_check(prepared_meshes == EXPECTED_MESHES, "CoupeDamage prepared mesh count is fixed")
	_check(prepared_triangles == EXPECTED_TRIANGLES, "CoupeDamage prepared triangle count is fixed")
	_check(clearance_signature != 0, "CoupeDamage prepared wheel-clearance signature is valid")
	_check(_mesh_count(prepared_template) == EXPECTED_MESHES, "CoupeDamage prepared metadata matches physical meshes")
	_check(_triangle_count(prepared_template) == EXPECTED_TRIANGLES, "CoupeDamage prepared metadata matches physical triangles")
	prepared_template.free()

	var model_resource := load(MODEL_PATH) as Script
	_check(model_resource != null, "CoupeDamage script loads")
	if model_resource == null:
		_finish({"error": "script_missing"})
		return
	var session := CACHE.begin_region_session(self, &"harbor")
	var job := _job_for_path(CACHE.region_session_jobs(session), MODEL_PATH)
	_check(not job.is_empty(), "Harbor regional manifest exposes CoupeDamage")
	if job.is_empty():
		CACHE.finish_region_session(session, true)
		_finish({"error": "regional_job_missing"})
		return
	var prepared_hits_before := CLEARANCE.prepared_hits
	var execution: Dictionary = {"complete": false}
	var stage_rows: Array[Dictionary] = []
	var stage_steps := 0
	while stage_steps < MAX_STAGE_SAFETY_STEPS:
		stage_steps += 1
		execution = CACHE.advance_region_job(session, job, model_resource)
		stage_rows.append({
			"stage": String(execution.get("stage", "")),
			"actual_usec": int(execution.get("actual_usec", 0)),
			"over_budget": bool(execution.get("over_budget", false)),
			"slice_index": int(execution.get("slice_index", -2)),
			"slice_count": int(execution.get("slice_count", 0)),
			"unit_name": String(execution.get("unit_name", "")),
		})
		if execution.has("error") or bool(execution.get("complete", false)):
			break
		await process_frame
	_check(not execution.has("error"), "CoupeDamage regional preparation succeeds")
	_check(bool(execution.get("complete", false)), "CoupeDamage regional preparation reaches atomic commit")
	_check(stage_steps < MAX_STAGE_SAFETY_STEPS, "CoupeDamage regional preparation stays within the corruption safety bound")
	_check(CACHE._models.has(MODEL_PATH) and CACHE._prepared.has(MODEL_PATH), "CoupeDamage publishes model and prepared markers atomically")
	var preparation: Dictionary = execution.get("preparation", {})
	_check(bool(preparation.get("direct_prepared", false)), "CoupeDamage regional pipeline publishes the direct prepared template")
	_check(bool(preparation.get("wheel_mount_deferred_to_restore", false)), "CoupeDamage regional pipeline defers live wheel pivots to gameplay restore")
	_check(_stage_usec(stage_rows, "wheel_mount") == 0, "CoupeDamage regional pipeline performs no wheel carve or mount")
	var max_stage_usec := 0
	for row in stage_rows:
		var stage_usec := int(row.get("actual_usec", 0))
		max_stage_usec = maxi(max_stage_usec, stage_usec)
		_check(stage_usec <= STAGE_BUDGET_USEC, "CoupeDamage regional stage %s exceeds 6 ms: %.3f ms" % [String(row.get("stage", "")), stage_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == prepared_hits_before, "CoupeDamage regional preparation performs no hidden wheel carving")
	var attach_rows := _stage_rows(stage_rows, "prepared_scene_attach_slice")
	_check(attach_rows.size() == EXPECTED_MESHES, "CoupeDamage fixture follows every variable prepared attach slice")
	var region_report := CACHE.finish_region_session(session, true)
	await process_frame

	# Build the reproducible authored fallback only after measuring the real cold
	# regional path, so expensive offline equivalence work cannot warm it.
	CACHE._deferred_constructor_paths[MODEL_PATH] = 1
	var authored := model_resource.new() as Node3D
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	authored.call("build_coupe_procedural_source")
	stage_root.add_child(authored)
	var authored_rig := WHEEL_RIG.new()
	var authored_mounted := authored_rig.mount(authored)
	_check(authored_mounted and authored_rig.pivots.size() == 4, "CoupeDamage procedural fallback mounts four wheels")
	_check(_triangle_count(authored) == EXPECTED_TRIANGLES, "CoupeDamage procedural fallback preserves the prepared triangle count")

	var live := model_resource.new() as Node3D
	var sibling := model_resource.new() as Node3D
	stage_root.add_child(live)
	stage_root.add_child(sibling)
	sibling.visible = false
	_check(live.get_meta("coupe_damage_geometry_source", &"") == &"prepared", "CoupeDamage cache restore identifies the prepared source")
	_check(int(live.get_meta("coupe_damage_prepared_geometry_signature", 0)) == EXPECTED_SIGNATURE, "CoupeDamage cache restore retains the fixed signature")
	_check(bool(live.get_meta("vehicle_mesh_batched", false)), "CoupeDamage cache restore remains pre-batched")
	_check(bool(live.get_meta("vehicle_prepared_wheel_wells", false)), "CoupeDamage cache restore retains prepared wheel metadata")
	_check(BATCHER.batch_model(live) == 0, "CoupeDamage cache restore never repeats mesh batching")

	var runtime_hits_before := CLEARANCE.prepared_hits
	var runtime_mount_started := Time.get_ticks_usec()
	var live_rig := WHEEL_RIG.new()
	var live_mounted := live_rig.mount(live)
	var runtime_mount_usec := Time.get_ticks_usec() - runtime_mount_started
	_check(live_mounted and live_rig.pivots.size() == 4, "CoupeDamage cache restore remounts four articulated wheels")
	_check(runtime_mount_usec <= STAGE_BUDGET_USEC, "CoupeDamage cached wheel mount stays within 6 ms, got %.3f ms" % [runtime_mount_usec / 1000.0])
	_check(CLEARANCE.prepared_hits == runtime_hits_before + 1, "CoupeDamage cached wheel mount skips polygon carving")
	_check(_triangle_count(live) == EXPECTED_TRIANGLES, "CoupeDamage prepared path preserves exact triangles")
	_check(_visual_signature(live, 4) == _visual_signature(authored, 4), "CoupeDamage prepared path preserves authored geometry/materials at 0.1 mm")

	var live_paint := live.get("paint") as StandardMaterial3D
	var sibling_paint := sibling.get("paint") as StandardMaterial3D
	_check(live_paint != null and sibling_paint != null and live_paint != sibling_paint, "CoupeDamage prepared instances retain independent paint")
	if live_paint != null and sibling_paint != null:
		var sibling_color := sibling_paint.albedo_color
		_check(sibling_color.v > 0.15 and sibling_color.a > 0.99, "CoupeDamage paint remains visible and non-black")
		live_paint.albedo_color = Color.MAGENTA
		_check(sibling_paint.albedo_color == sibling_color, "CoupeDamage repaint cannot recolor another cached instance")
		live_paint.albedo_color = Color("b83632")

	var originals := live.get("originals") as Dictionary
	var lamp_sources := live.get("lamp_sources") as Dictionary
	_check(originals.size() >= 1, "CoupeDamage prepared body retains damage baselines")
	_check(lamp_sources.size() >= 4, "CoupeDamage prepared body retains independently damageable lights")
	live.call("apply_impact", Vector3(0.7, 0.78, -1.35), Vector3(-1.0, 0.0, 0.0), 9.0)
	_check(int(live.get("impact_count")) == 1, "CoupeDamage prepared body accepts deformation")
	_check(not (live.get("damaged_vertices") as Dictionary).is_empty(), "CoupeDamage prepared body deforms a cached paint mesh")
	if not lamp_sources.is_empty():
		var lamp_node := lamp_sources.keys()[0] as MeshInstance3D
		var lamp_data := lamp_sources[lamp_node] as Dictionary
		live.call("apply_impact", lamp_data.get("position", Vector3.ZERO), Vector3(0.0, 0.0, 1.0), 9.0)
		var front_broken: Array = live.get("broken_lamps")
		var rear_broken: Array = live.get("broken_tail_lamps")
		_check(front_broken.has(true) or rear_broken.has(true), "CoupeDamage prepared lights still break on a local impact")
	live.call("repair")
	_check(int(live.get("impact_count")) == 0 and (live.get("damaged_vertices") as Dictionary).is_empty(), "CoupeDamage prepared body repairs completely")
	_check(not (live.get("broken_lamps") as Array).has(true) and not (live.get("broken_tail_lamps") as Array).has(true), "CoupeDamage repair restores every light")

	var corrupt := prepared_scene.instantiate() as Node3D
	corrupt.set_meta("coupe_damage_prepared_geometry_signature", EXPECTED_SIGNATURE + 1)
	_check(not bool(live.call("validate_vehicle_prepared_template", corrupt)), "CoupeDamage rejects a corrupt prepared signature")
	corrupt.free()

	authored.visible = false
	var capture_error := await _capture_live_model(live)
	_check(capture_error == OK, "CoupeDamage rendered validation capture saves successfully")
	var result := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"global_renderer_bootstrap_ms": int(global_bootstrap.get("elapsed_usec", 0)) / 1000.0,
		"vehicle_material_bootstrap_ms": vehicle_material_bootstrap_ms,
		"stage_budget_usec": STAGE_BUDGET_USEC,
		"stage_steps": stage_steps,
		"attach_slices": attach_rows.size(),
		"max_stage_usec": max_stage_usec,
		"max_stage_ms": max_stage_usec / 1000.0,
		"regional_total_active_usec": int(execution.get("total_active_usec", 0)),
		"regional_total_active_ms": int(execution.get("total_active_usec", 0)) / 1000.0,
		"regional_over_budget_stages": region_report.get("over_budget_stages", []),
		"stage_rows": stage_rows,
		"runtime_restore_mount_usec": runtime_mount_usec,
		"runtime_restore_mount_ms": runtime_mount_usec / 1000.0,
		"prepared_signature": prepared_signature,
		"prepared_meshes": prepared_meshes,
		"prepared_triangles": prepared_triangles,
		"wheel_centres": live_rig.pivots.size(),
		"damage_parts": originals.size(),
		"lamps": lamp_sources.size(),
		"capture_path": ProjectSettings.globalize_path(CAPTURE_PATH),
	}
	authored.free()
	live.free()
	sibling.free()
	_finish(result)


func _warm_renderer() -> float:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage_root.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(4.0, 3.0, 5.0)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	viewport.add_child(camera)
	var opaque := StandardMaterial3D.new()
	opaque.albedo_color = Color("b83632")
	opaque.metallic = 0.25
	opaque.roughness = 0.24
	var double_sided := opaque.duplicate() as StandardMaterial3D
	double_sided.cull_mode = BaseMaterial3D.CULL_DISABLED
	var emissive := opaque.duplicate() as StandardMaterial3D
	emissive.emission_enabled = true
	emissive.emission = Color("e6f0ed")
	emissive.emission_energy_multiplier = 0.65
	var warmup_materials: Array[StandardMaterial3D] = [opaque, double_sided, emissive]
	for index in warmup_materials.size():
		var sample := MeshInstance3D.new()
		sample.mesh = BoxMesh.new()
		sample.position.x = float(index) * 1.5 - 1.5
		sample.material_override = warmup_materials[index]
		viewport.add_child(sample)
	var started := Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	viewport.free()
	await process_frame
	return elapsed


func _capture_live_model(live: Node3D) -> Error:
	RenderingServer.set_default_clear_color(Color("6f7f91"))
	var camera := Camera3D.new()
	camera.position = Vector3(5.4, 3.0, 6.4)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.65, 0.0), Vector3.UP)
	stage_root.add_child(camera)
	camera.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	stage_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 140.0, 0.0)
	fill.light_energy = 0.65
	stage_root.add_child(fill)
	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(14.0, 14.0)
	ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("c4ccd3")
	ground_material.roughness = 0.85
	ground.material_override = ground_material
	stage_root.add_child(ground)
	live.visible = true
	for _frame in 2:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))


func _job_for_path(jobs: Array[Dictionary], path: String) -> Dictionary:
	for job in jobs:
		if String(job.get("path", "")) == path:
			return job
	return {}


func _stage_rows(rows: Array[Dictionary], wanted: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			result.append(row)
	return result


func _stage_usec(rows: Array[Dictionary], wanted: String) -> int:
	for row in rows:
		if String(row.get("stage", "")) == wanted:
			return int(row.get("actual_usec", 0))
	return 0


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


func _visual_signature(model: Node3D, decimals: int) -> int:
	var triangles: Array[String] = []
	_collect_visual_triangles(model, model, Transform3D.IDENTITY, triangles, decimals)
	triangles.sort()
	return hash(triangles)


func _collect_visual_triangles(model: Node3D, node: Node, parent_transform: Transform3D, triangles: Array[String], decimals: int) -> void:
	var model_transform := parent_transform
	if node is Node3D:
		model_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface_index in part.mesh.get_surface_count() if part.mesh != null else 0:
			var material := part.get_active_material(surface_index) as StandardMaterial3D
			var color := material.albedo_color if material != null else Color.TRANSPARENT
			var arrays := part.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var triangle_count := indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for triangle_index in triangle_count:
				var points: Array[String] = []
				for corner in 3:
					var vertex_index := indices[triangle_index * 3 + corner] if not indices.is_empty() else triangle_index * 3 + corner
					points.append(_point_key(model_transform * vertices[vertex_index], decimals))
				points.sort()
				triangles.append("%.5f,%.5f,%.5f,%.5f:%s" % [color.r, color.g, color.b, color.a, "|".join(points)])
	for child in node.get_children():
		_collect_visual_triangles(model, child, model_transform, triangles, decimals)


func _point_key(point: Vector3, decimals: int) -> String:
	var scale := pow(10.0, decimals)
	return "%d,%d,%d" % [roundi(point.x * scale), roundi(point.y * scale), roundi(point.z * scale)]


func _reset_runtime() -> void:
	CACHE._models.erase(MODEL_PATH)
	CACHE._prepared.erase(MODEL_PATH)
	CACHE._operationally_warmed_paths.erase(MODEL_PATH)
	CACHE._region_reports.erase(&"harbor")
	CACHE._retained_regions.erase(&"harbor")
	CACHE._deferred_constructor_paths.erase(MODEL_PATH)
	CACHE._regional_capture_suppressed_paths.erase(MODEL_PATH)
	CACHE._miss_started_usec.erase(MODEL_PATH)
	CLEARANCE._cache.clear()
	CLEARANCE._content_keys.clear()
	BATCHER._mesh_cache.clear()
	BATCHER._format_cache.clear()
	BATCHER._primitive_formats.clear()


func _finish(result: Dictionary) -> void:
	result["failures"] = failures
	print("COUPE_DAMAGE_PREPARED_CONTRACT ", JSON.stringify(result))
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
