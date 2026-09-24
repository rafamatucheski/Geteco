extends Node3D
## Presentation-only adapter for the original CivilianDriverModel.
var coat_color := Color("3f6872")
var limbs: Array[Node3D] = []
var clock := 0.0
var walking := false
var appearance_variant := 0
static var shared_sphere: SphereMesh
static var materials: Dictionary = {}

func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	if shared_sphere == null:
		shared_sphere = SphereMesh.new()
		shared_sphere.radial_segments = 10
		shared_sphere.rings = 5
		shared_sphere.height = 2
		shared_sphere.radius = 1
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		materials[color] = material
	var mesh := MeshInstance3D.new()
	mesh.mesh = shared_sphere
	mesh.scale = size * 0.5
	mesh.position = point
	mesh.material_override = materials[color]
	parent.add_child(mesh)
	return mesh
