extends RefCounted
## Componentes estáticos de fachada em metros. Sem luzes, física ou atualizações por quadro.

static func gable(parent: Node3D, label: String, half_width: float, base_y: float, ridge_y: float, z: float, depth: float, material: Material) -> MeshInstance3D:
	var vertices := [Vector3(-half_width, base_y, z-depth*.5), Vector3(half_width, base_y, z-depth*.5), Vector3(0, ridge_y, z-depth*.5), Vector3(-half_width, base_y, z+depth*.5), Vector3(half_width, base_y, z+depth*.5), Vector3(0, ridge_y, z+depth*.5)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 3, 5, 4, 0, 3, 4, 0, 4, 1, 0, 2, 5, 0, 5, 3, 1, 4, 5, 1, 5, 2]:
		var point: Vector3 = vertices[index]
		surface.set_uv(Vector2(point.x, point.y))
		surface.add_vertex(point)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.set_meta("exterior_part", "roof_gable")
	parent.add_child(mesh)
	return mesh

static func window(parent: Node3D, point: Vector3, yaw: float, width: float, height: float, frame: Material, glass: Material) -> Node3D:
	var group := Node3D.new()
	group.name = "FacadeWindow"
	group.position = point
	group.rotation.y = yaw
	parent.add_child(group)
	# +Z local aponta para fora; a origem é a face externa da parede.
	_piece(group, "WindowRecess", Vector3(0, 0, .025), Vector3(width, height, .05), frame)
	_piece(group, "WindowGlass", Vector3(0, 0, .06), Vector3(width-.16, height-.16, .025), glass).set_meta("exterior_part", "window_glass")
	for side in [-1.0, 1.0]:
		_piece(group, "WindowJamb", Vector3(side*(width*.5-.045), 0, .09), Vector3(.09, height, .12), frame)
		_piece(group, "WindowRail", Vector3(0, side*(height*.5-.045), .09), Vector3(width, .09, .12), frame)
	_piece(group, "WindowMullion", Vector3(0, 0, .09), Vector3(.055, height-.16, .09), frame)
	_piece(group, "WindowSill", Vector3(0, -height*.5-.025, .12), Vector3(width+.12, .07, .28), frame)
	return group

static func _piece(parent: Node3D, label: String, point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	result.mesh = mesh
	result.position = point
	result.material_override = material
	parent.add_child(result)
	return result
