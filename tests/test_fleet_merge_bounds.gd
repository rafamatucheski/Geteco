extends SceneTree
## A rotated cylinder's transformed AABB includes empty corners, unlike its vertices.
const MERGER := preload("res://runtime/FleetSpeedPass.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func fixture() -> Node3D:
	var model := Node3D.new()
	var material := StandardMaterial3D.new()
	for i in 2:
		var part := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = 12
		part.mesh = cylinder
		part.material_override = material
		part.rotation = Vector3(0.37, 0.23, 0.49)
		part.position.x = i * 2.0
		model.add_child(part)
	return model

func geometry(model: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for part: MeshInstance3D in model.get_children():
		for vertex in part.mesh.get_faces():
			points.append(part.transform * vertex)
	return points

func same_triangles(before: PackedVector3Array, after: PackedVector3Array) -> bool:
	if before.size() != after.size(): return false
	# Mesh conversion changes representable positions by up to 0.082 mm here.
	# Compare ordered triangle vertices within 0.1 mm, not rounded grid bins:
	# arbitrarily close points can fall on opposite sides of a bin boundary.
	for index in before.size():
		if before[index].distance_to(after[index]) > 0.0001: return false
	return true

func run() -> void:
	for iteration in 2:
		var model := fixture()
		var before := geometry(model)
		MERGER.merge_parts(model, "rotated_cylinder_regression")
		check(model.get_child_count() == 1, "Rotated parts merge, including the cached plan")
		check(same_triangles(before, geometry(model)), "All transformed triangle vertices survive merging")
		model.free()
	print("FLEET_MERGE_BOUNDS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
