extends Node3D
## Fixed roadside signal in metres. Front faces -Z; arm extends toward +X.
var lenses: Array[StandardMaterial3D] = []
const COLORS := [Color("ff332b"), Color("ffc62f"), Color("36e277")]

func _init() -> void:
	var steel := _material(Color("66737b"), 0.72, 0.36)
	var dark := _material(Color("20272a"), 0.25, 0.65)
	var concrete := _material(Color("a3a29a"), 0.0, 0.94)
	var rim := _material(Color("c9af62"), 0.38, 0.48)
	_box(Vector3(0, 0.07, 0), Vector3(0.58, 0.14, 0.58), concrete)
	_box(Vector3(0, 0.17, 0), Vector3(0.4, 0.06, 0.4), steel)
	for x in [-0.14, 0.14]:
		for z in [-0.14, 0.14]:
			_cylinder(Vector3(x, 0.22, z), 0.033, 0.055, steel, 6)
	_cylinder(Vector3(0, 1.75, 0), 0.072, 3.1, steel)
	_cylinder(Vector3(0, 0.37, 0), 0.105, 0.3, dark)
	_cylinder(Vector3(0, 3.31, 0), 0.09, 0.07, steel)
	_box(Vector3(0, 0.8, -0.072), Vector3(0.085, 0.28, 0.035), dark)
	var arm := _cylinder(Vector3(0.37, 3.23, 0), 0.052, 0.74, steel)
	arm.rotation.z = PI * 0.5
	for y in [2.76, 3.67]:
		_box(Vector3(0.72, y, 0.1), Vector3(0.28, 0.055, 0.28), steel)
	# Narrow reflective perimeter, dark backplate, sealed three-aspect housing.
	_box(Vector3(0.74, 3.22, 0.1), Vector3(0.72, 1.58, 0.05), rim)
	_box(Vector3(0.74, 3.22, 0.135), Vector3(0.65, 1.51, 0.02), dark)
	_box(Vector3(0.74, 3.22, 0.06), Vector3(0.65, 1.51, 0.05), dark)
	_box(Vector3(0.74, 3.22, -0.055), Vector3(0.5, 1.37, 0.23), dark)
	for index in 3:
		var y := 3.65 - float(index) * 0.43
		var ring := _cylinder(Vector3(0.74, y, -0.19), 0.19, 0.075, dark, 24)
		ring.rotation.x = PI * 0.5
		var lens := _material(COLORS[index].darkened(0.93), 0.05, 0.3)
		lenses.append(lens)
		var lamp := _cylinder(Vector3(0.74, y, -0.235), 0.151, 0.028, lens, 24)
		lamp.rotation.x = PI * 0.5
		_visor(Vector3(0.74, y, 0), dark)
	set_signal_state(0)

func set_signal_state(state: int) -> void:
	for index in lenses.size():
		var on := index == clampi(state, 0, 2)
		lenses[index].albedo_color = COLORS[index] if on else COLORS[index].darkened(0.93)
		lenses[index].emission = COLORS[index]
		lenses[index].emission_enabled = on
		lenses[index].emission_energy_multiplier = 1.5 if on else 0.0

func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

func _box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, at, material)

func _cylinder(at: Vector3, radius: float, height: float, material: Material, sides := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(mesh, at, material)

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node

func _visor(at: Vector3, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 16:
		var a := deg_to_rad(-15.0 + step * 210.0 / 16.0)
		var b := deg_to_rad(-15.0 + (step + 1) * 210.0 / 16.0)
		var back_a := Vector3(cos(a) * 0.19, sin(a) * 0.19, -0.19)
		var back_b := Vector3(cos(b) * 0.19, sin(b) * 0.19, -0.19)
		var front_a := back_a + Vector3(0, 0, -0.22)
		var front_b := back_b + Vector3(0, 0, -0.22)
		for point in [back_a, front_a, back_b, back_b, front_a, front_b]:
			surface.add_vertex(point)
	surface.generate_normals()
	var visor_material := material.duplicate() as StandardMaterial3D
	visor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(surface.commit(), at, visor_material)
