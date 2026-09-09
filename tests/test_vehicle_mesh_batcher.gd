extends SceneTree
const Batcher = preload("res://VehicleMeshBatcher.gd")
const Door = preload("res://prototypes/living_cast/VehicleDoor3D.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); print("FAIL ", label)
func _initialize() -> void: call_deferred("run")
func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in node.get_children():
		if child is MeshInstance3D: result.append(child)
		result.append_array(meshes(child))
	return result
func stats(model: Node3D) -> Dictionary:
	var result := {"vertices": 0, "faces": 0, "materials": {}, "bounds": AABB(), "count": 0}
	for node in meshes(model):
		if not node.visible: continue
		var transform := model.global_transform.affine_inverse() * node.global_transform
		var bounds: AABB = transform * node.mesh.get_aabb()
		result.bounds = bounds if result.count == 0 else result.bounds.merge(bounds)
		result.count += 1
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			result.vertices += arrays[Mesh.ARRAY_VERTEX].size()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			result.faces += (arrays[Mesh.ARRAY_VERTEX].size() if indices.is_empty() else indices.size()) / 3
		result.materials[node.material_override] = true
	return result
func extract_wheels(model: Node3D) -> void:
	var centers: Array[Vector3] = []
	for node in model.get_children():
		if node.has_meta("wheel_center") and not centers.has(node.get_meta("wheel_center")): centers.append(node.get_meta("wheel_center"))
	for center in centers:
		var pivot := Node3D.new()
		pivot.position = center
		model.add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		for node in model.get_children():
			if node is MeshInstance3D and node.get_meta("wheel_center",Vector3.INF) == center:
				node.reparent(spin if node.get_meta("wheel_spins",false) else pivot,true)
func run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	for path in ["models/SummitSUVModel", "models/UnionSedanModel", "models/BoxrunnerModel", "CoupeDamageModel"]:
		var model: Node3D = load("res://prototypes/living_cast/" + path + ".gd").new()
		root.add_child(model)
		extract_wheels(model)
		var before := stats(model)
		var removed := Batcher.batch_model(model)
		var after := stats(model)
		print(path, " mesh count ", before.count, " -> ", after.count, " vertices ", before.vertices, " -> ", after.vertices, " faces ", before.faces, " -> ", after.faces)
		check(removed > 0 and after.count < before.count, path + " batches reduce draw calls")
		check(before.vertices == after.vertices, path + " raw vertices preserved")
		check(before.faces == after.faces, path + " topology preserved")
		check(before.bounds.position.is_equal_approx(after.bounds.position) and before.bounds.size.is_equal_approx(after.bounds.size), path + " bounds preserved")
		check(before.materials == after.materials, path + " same material resources")
		for source in model.originals: check(is_instance_valid(source) and source.get_parent() == model, path + " no stale damage references")
		model.apply_impact(Vector3(0.9,0.8,-1.5),Vector3(-1,0,0),12)
		check(model.max_deformation() > 0 and model.max_deformation() <= 0.141, path + " damage bounded and functional")
		check(Batcher.batch_model(model) == 0, path + " never bake damaged geometry")
		model.repair()
		check(model.max_deformation() == 0, path + " repairs pristine geometry")
		var reference: Node3D = load("res://prototypes/living_cast/" + path + ".gd").new()
		root.add_child(reference)
		extract_wheels(reference)
		for side in [-1.0,1.0]:
			var door := Door.new()
			model.add_child(door)
			door.configure(model,side)
			check(door.extracted_triangles > 0, path + " extracts door side " + str(side))
			var baseline_door := Door.new()
			reference.add_child(baseline_door)
			baseline_door.configure(reference,side)
			check(door.extracted_triangles == baseline_door.extracted_triangles, path + " door geometry matches unbatched side " + str(side))
		model.apply_impact(Vector3(0.9,0.8,-1.5),Vector3(-1,0,0),12)
		check(model.max_deformation() <= 0.141, path + " post door damage bounded")
		model.repair()
		check(model.max_deformation() == 0, path + " post door repair")
		reference.free()
		model.free()
	print("VEHICLE_MESH_BATCHER failures=", failures)
	quit(0 if failures.is_empty() else 1)
