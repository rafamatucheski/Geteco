extends Node3D

var materials: Dictionary = {}

func material(color: String, metal := 0.0) -> StandardMaterial3D:
	var key := color + str(metal)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = 0.83 if metal == 0.0 else 0.45
		mat.metallic = metal
		materials[key] = mat
	return materials[key]

func box(label: String, size: Vector3, pos: Vector3, color: String, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material(color)
	part.position = pos
	(self if parent == null else parent).add_child(part)
	return part

func cylinder(label: String, radius: float, height: float, pos: Vector3, color: String, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	part.mesh = mesh
	part.material_override = material(color)
	part.position = pos
	(self if parent == null else parent).add_child(part)
	return part

func beam(label: String, a: Vector3, b: Vector3, width: float, color: String, parent: Node3D = null) -> MeshInstance3D:
	var part := box(label, Vector3(width, a.distance_to(b), width), (a + b) * 0.5, color, parent)
	part.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return part

func lettering(text: String, pos: Vector3, size := 36, color := "dfd0a3") -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.009
	label.modulate = Color(color)
	label.outline_size = 2
	label.position = pos
	add_child(label)
	return label

func lantern(pos: Vector3, parent: Node3D = null) -> Node3D:
	var prop := Node3D.new()
	prop.name = "OilLantern"
	prop.position = pos
	(self if parent == null else parent).add_child(prop)
	cylinder("Base", 0.14, 0.06, Vector3(0, 0.03, 0), "323b32", prop)
	var glass := cylinder("AmberGlass", 0.095, 0.26, Vector3(0, 0.19, 0), "e6a44e", prop)
	var glow := material("e6a44e").duplicate() as StandardMaterial3D
	glow.emission_enabled = true
	glow.emission = Color("e6a44e")
	glow.emission_energy_multiplier = 0.8
	glass.material_override = glow
	cylinder("Cap", 0.14, 0.07, Vector3(0, 0.35, 0), "323b32", prop)
	for x in [-0.12, 0.12]: beam("Guard", Vector3(x, 0.04, 0), Vector3(x, 0.36, 0), 0.018, "323b32", prop)
	return prop
