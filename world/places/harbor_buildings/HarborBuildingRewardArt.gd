extends RefCounted
## Readable objects for the shared walking pickup presentation; no floating text.
const MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")

static func build(reward: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "BuildingRewardArt"
	if reward.get("kind", "") == "cash":
		for bundle in 3:
			var at := Vector3((bundle % 2) * .13 - .065, .14 + bundle * .025, 0)
			_box(root, at, Vector3(.25, .035, .13), "91a289", "paper")
			_box(root, at + Vector3(0, .023, 0), Vector3(.043, .008, .136), "d6c7a1", "paper")
		return root
	match str(reward.get("item", "")):
		"water":
			_cylinder(root, Vector3(0, .20, 0), .072, .28, "779fa5", "glass")
			_cylinder(root, Vector3(0, .36, 0), .044, .048, "52798b", "metal")
			_cylinder(root, Vector3(0, .19, 0), .074, .10, "d5d8c6", "paper")
		"first_aid":
			_box(root, Vector3(0, .16, 0), Vector3(.31, .19, .22), "d6d6bf", "cloth")
			_box(root, Vector3(0, .259, 0), Vector3(.045, .012, .14), "a35b4d", "cloth")
			_box(root, Vector3(0, .260, 0), Vector3(.14, .012, .045), "a35b4d", "cloth")
		"lockpick":
			_box(root, Vector3(0, .14, 0), Vector3(.27, .05, .15), "4f5c56", "cloth")
			for tool in 3:
				_box(root, Vector3(-.07 + tool * .06, .18, 0), Vector3(.012, .015, .19), "c1c3b2", "metal")
				_box(root, Vector3(-.06 + tool * .06, .18, -.09), Vector3(.034, .015, .02), "c1c3b2", "metal")
		_:
			_box(root, Vector3(0, .14, 0), Vector3(.27, .09, .17), "d3c6a1", "paper")
			_box(root, Vector3(0, .193, 0), Vector3(.09, .013, .18), "7e9676", "paper")
	return root

static func _box(root: Node3D, at: Vector3, size: Vector3, color: String, kind: String) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = MATERIALS.material(kind, Color(color))
	root.add_child(node)

static func _cylinder(root: Node3D, at: Vector3, radius: float, height: float, color: String, kind: String) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.position = at
	node.material_override = MATERIALS.material(kind, Color(color))
	root.add_child(node)
