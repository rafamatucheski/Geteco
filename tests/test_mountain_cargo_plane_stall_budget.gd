extends SceneTree

const PLANE_MODEL := preload("res://world/mountain_pass/art/review_0908/CrashedCargoPlane3D.gd")
const CARGO_PLANE := preload("res://world/mountain_pass/MountainCargoPlane.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error(message)


func _count_type(node: Node, type_name: StringName) -> int:
	var count := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		count += _count_type(child, type_name)
	return count


func _measure_add(parent: Node, child: Node) -> int:
	var started := Time.get_ticks_usec()
	parent.add_child(child)
	return Time.get_ticks_usec() - started


func _run() -> void:
	var host := Node2D.new()
	root.add_child(host)
	current_scene = host

	var bare_model := PLANE_MODEL.new()
	var bare_usec := _measure_add(host, bare_model)
	await process_frame
	var bare_meshes := _count_type(bare_model, &"MeshInstance3D")
	var bare_multimeshes := _count_type(bare_model, &"MultiMeshInstance3D")
	_check(bare_model.has_node("CutawayRoof"), "cargo plane keeps the cutaway roof contract")
	_check(bare_model.footprint_size == Vector2(28.0, 24.0), "cargo plane footprint is unchanged")
	bare_model.queue_free()
	await process_frame

	var cargo_plane := CARGO_PLANE.new()
	var full_usec := _measure_add(host, cargo_plane)
	var first_presented_started := Time.get_ticks_usec()
	await process_frame
	var first_presented_usec := Time.get_ticks_usec() - first_presented_started
	var model := cargo_plane.get_node_or_null("ModelViewport3D/CrashedCargoPlane3D")
	if model == null:
		model = cargo_plane.model
	var smg := cargo_plane.get_node_or_null("CargoSMG")
	var floor_weapon := cargo_plane.model.get_node_or_null("CargoSMGModel/FloorWeapon") if cargo_plane.model else null
	var treasure := cargo_plane.model.get_node_or_null("SmugglerTreasure") if cargo_plane.model else null
	_check(model != null, "full cargo plane keeps its 3D aircraft model")
	_check(smg != null and floor_weapon != null, "full cargo plane keeps its SMG pickup")
	_check(treasure != null and cargo_plane.treasure_lid != null and cargo_plane.gold != null, "full cargo plane keeps treasure, lid and gold state")
	_check(cargo_plane.get_node_or_null("FuselageWall") != null, "full cargo plane keeps walkable collision solids")

	var full_meshes := _count_type(cargo_plane, &"MeshInstance3D")
	var full_multimeshes := _count_type(cargo_plane, &"MultiMeshInstance3D")
	var report := {
		"bare_add_usec": bare_usec,
		"full_add_usec": full_usec,
		"first_presented_frame_usec": first_presented_usec,
		"bare_mesh_instances": bare_meshes,
		"bare_multimesh_instances": bare_multimeshes,
		"full_mesh_instances": full_meshes,
		"full_multimesh_instances": full_multimeshes,
		"failures": failures,
	}
	print("MOUNTAIN_CARGO_PLANE_STALL ", JSON.stringify(report))
	cargo_plane.queue_free()
	host.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
