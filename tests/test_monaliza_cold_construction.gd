extends SceneTree

const MODEL_PATH := "res://world/harbor/monaliza/MonalizaModel.gd"
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const FRAME_BUDGET_MS := 1000.0 / 60.0
const EXPECTED_VISUAL_SIGNATURE := 302201904
const EXPECTED_TRIANGLES := 39671
const COLD_PIPELINE_BASELINE_MS := 708.496

var failures: Array[String] = []
var fixture: SubViewport
var model_script: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_usec()
	model_script = load(MODEL_PATH) as Script
	var script_load_ms := _elapsed_ms(started)
	check(model_script != null and model_script.can_instantiate(), "Monaliza model script and baked resource load")
	if model_script == null or not model_script.can_instantiate():
		quit(1)
		return
	fixture = SubViewport.new()
	fixture.name = "MonalizaColdConstructionFixture"
	fixture.size = Vector2i(512, 384)
	fixture.own_world_3d = true
	fixture.transparent_bg = true
	fixture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(fixture)

	var camera := Camera3D.new()
	fixture.add_child(camera)
	camera.look_at_from_position(Vector3(5.7, 3.6, -6.5), Vector3(0, 0.55, 0), Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	fixture.add_child(light)

	started = Time.get_ticks_usec()
	var cold := model_script.new() as Node3D
	var cold_constructor_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	fixture.add_child(cold)
	var cold_add_ready_ms := _elapsed_ms(started)
	var cold_profile: Dictionary = model_script.last_build_profile_usec()
	var cold_signature := _visual_signature(cold)
	var cold_triangles := _triangle_count(cold)
	var cold_meshes := _mesh_count(cold)
	var cold_unique_meshes := _unique_mesh_count(cold)
	var cold_wheels := _wheel_centers(cold)
	var cold_paint := cold.get("paint") as StandardMaterial3D
	var trunk := cold.get("trunk_pivot") as Node3D
	var prebatch_signature := cold_signature
	started = Time.get_ticks_usec()
	var cold_rig := WHEEL_RIG.new()
	var cold_mounted := cold_rig.mount(cold)
	var cold_mount_ms := _elapsed_ms(started)
	var mounted_signature := _visual_signature(cold)
	var mounted_triangles := _triangle_count(cold)
	started = Time.get_ticks_usec()
	var cold_batched_removed := BATCHER.batch_model(cold)
	var cold_batch_ms := _elapsed_ms(started)
	var postbatch_signature := _visual_signature(cold)

	started = Time.get_ticks_usec()
	var warm := model_script.new() as Node3D
	var warm_constructor_ms := _elapsed_ms(started)
	fixture.add_child(warm)
	var warm_profile: Dictionary = model_script.last_build_profile_usec()

	check(cold_signature == _visual_signature(warm), "cold and warm Monaliza keep the same visual signature")
	check(cold_signature == EXPECTED_VISUAL_SIGNATURE, "baked Monaliza preserves the exact pre-optimization mounted visual signature")
	check(cold_triangles == _triangle_count(warm), "cold and warm Monaliza keep the same triangle count")
	check(cold_triangles == EXPECTED_TRIANGLES, "baked Monaliza preserves the exact pre-optimization triangle count")
	check(cold_meshes == _mesh_count(warm), "cold and warm Monaliza keep every authored mesh")
	check(cold_wheels.size() == 4 and _wheel_centers(warm).size() == 4, "Monaliza keeps four articulated wheel centres")
	check(cold_paint != null and cold_paint.albedo_color.v > 0.15, "Monaliza paint remains visible instead of black")
	check(trunk != null and trunk.name == "MonalizaTrunkHinge", "Monaliza keeps the functional trunk pivot")
	check(cold_mounted and cold_rig.pivots.size() == 4, "Monaliza mounts four live wheel rigs")
	check(cold_mount_ms < FRAME_BUDGET_MS, "Monaliza wheel mounting stays below one 60 FPS frame")
	check(cold_batched_removed > 0, "Monaliza exercises the real mesh batching path")
	check(postbatch_signature == prebatch_signature, "mesh batching preserves Monaliza's visual signature")
	var warm_paint := warm.get("paint") as StandardMaterial3D
	check(cold_paint != warm_paint, "Monaliza paint remains independent per instance")
	if cold_paint != null and warm_paint != null:
		var expected := warm_paint.albedo_color
		cold_paint.albedo_color = Color.MAGENTA
		check(warm_paint.albedo_color == expected, "repainting one Monaliza cannot recolor another")

	var first_presented_ms = null
	var runtime_first_presented_ms = null
	var warm_mount_ms := 0.0
	var warm_batch_ms := 0.0
	if DisplayServer.get_name() != "headless":
		cold_paint.albedo_color = Color("183b91")
		warm.hide()
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		first_presented_ms = _elapsed_ms(started)
		if "--capture" in OS.get_cmdline_user_args():
			var capture_path := ProjectSettings.globalize_path("res://_codex_diag/monaliza-baked-wheel-wells.png")
			var save_error := fixture.get_texture().get_image().save_png(capture_path)
			check(save_error == OK, "rendered Monaliza inspection image is saved")
			print("MONALIZA_CAPTURE path=%s error=%d" % [capture_path, save_error])
		started = Time.get_ticks_usec()
		var warm_rig := WHEEL_RIG.new()
		check(warm_rig.mount(warm) and warm_rig.pivots.size() == 4, "runtime Monaliza mounts four live wheel rigs")
		warm_mount_ms = _elapsed_ms(started)
		started = Time.get_ticks_usec()
		BATCHER.batch_model(warm)
		warm_batch_ms = _elapsed_ms(started)
		cold.hide()
		warm.show()
		started = Time.get_ticks_usec()
		fixture.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		runtime_first_presented_ms = _elapsed_ms(started)
		check(warm_constructor_ms + warm_mount_ms + warm_batch_ms < FRAME_BUDGET_MS, "post-prewarm Monaliza construction pipeline stays below one 60 FPS frame")
		check(runtime_first_presented_ms < FRAME_BUDGET_MS, "post-prewarm Monaliza first presented frame stays below one 60 FPS frame")

	var originals: Dictionary = cold.get("originals")
	check(not originals.is_empty(), "Monaliza retains deformable painted body parts")
	cold.apply_impact(Vector3(0.7, 0.7, -1.2), Vector3(-1, 0, 0), 12.0)
	check(int(cold.get("impact_count")) == 1, "Monaliza still accepts gameplay damage")
	cold.repair()
	check(int(cold.get("impact_count")) == 0, "Monaliza damage remains repairable")

	var result := {
		"kind": "rendered" if DisplayServer.get_name() != "headless" else "headless_structural",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "not_measured",
		"frame_budget_ms": FRAME_BUDGET_MS,
		"script_load_ms": script_load_ms,
		"cold_constructor_ms": cold_constructor_ms,
		"cold_add_ready_ms": cold_add_ready_ms,
		"cold_mount_ms": cold_mount_ms,
		"cold_batch_ms": cold_batch_ms,
		"cold_pipeline_ms": cold_constructor_ms + cold_add_ready_ms + cold_mount_ms + cold_batch_ms,
		"cold_pipeline_baseline_ms": COLD_PIPELINE_BASELINE_MS,
		"cold_batched_removed": cold_batched_removed,
		"warm_constructor_ms": warm_constructor_ms,
		"warm_mount_ms": warm_mount_ms,
		"warm_batch_ms": warm_batch_ms,
		"warm_pipeline_ms": warm_constructor_ms + warm_mount_ms + warm_batch_ms,
		"cold_profile_usec": cold_profile,
		"warm_profile_usec": warm_profile,
		"first_presented_ms": first_presented_ms,
		"runtime_first_presented_ms": runtime_first_presented_ms,
		"visual_signature": cold_signature,
		"mounted_visual_signature": mounted_signature,
		"batched_visual_signature": postbatch_signature,
		"triangles": cold_triangles,
		"mounted_triangles": mounted_triangles,
		"batched_triangles": _triangle_count(cold),
		"meshes": cold_meshes,
		"unique_meshes": cold_unique_meshes,
		"wheel_centres": cold_wheels.size(),
		"damage_parts": originals.size(),
		"failures": failures,
	}
	print("MONALIZA_COLD_CONSTRUCTION ", JSON.stringify(result))
	fixture.free()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	quit(0)


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


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
