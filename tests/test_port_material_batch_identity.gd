extends SceneTree

const OPTIMIZER := preload("res://assets/regions/source/prototypes/harbor_art_pack/PortMeshOptimizer.gd")
var failures := 0

func _initialize() -> void:
	var red := StandardMaterial3D.new()
	red.resource_name = "SharedLabel"
	red.albedo_color = Color.RED
	var blue := StandardMaterial3D.new()
	blue.resource_name = "SharedLabel"
	blue.albedo_color = Color.BLUE
	_check([red, blue], 2, "distinct materials sharing a name")
	_check([red, red], 1, "shared material instance")
	var unnamed_a := StandardMaterial3D.new()
	var unnamed_b := StandardMaterial3D.new()
	_check([unnamed_a, unnamed_b], 2, "distinct unnamed materials")
	_check([null, null], 1, "material-less meshes")
	if failures == 0: print("PASS port material batch identity: 4 scenarios")
	quit(failures)

func _check(materials: Array, expected: int, label: String) -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	for index in materials.size():
		var instance := MeshInstance3D.new()
		instance.mesh = BoxMesh.new()
		instance.material_override = materials[index]
		instance.position = Vector3(index * 2.0, 0, 0)
		fixture.add_child(instance)
	var stats: Dictionary = OPTIMIZER.optimize_hierarchy(fixture, false)
	_expect(int(stats.after_count) == expected, label + ": batch count")
	var preserved: Array = []
	for batch in fixture.get_node("BatchedStaticGeometry").get_children():
		preserved.append(batch.material_override)
	for source in materials:
		_expect(preserved.has(source), label + ": material identity preserved")
	fixture.free()

func _expect(condition: bool, label: String) -> void:
	if condition: return
	push_error("FAIL " + label)
	failures += 1
