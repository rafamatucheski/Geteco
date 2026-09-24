extends RefCounted

static func material(color: Color, roughness := 0.9, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

static func box(parent: Node3D, label: String, point: Vector3, size: Vector3, mat: Material, angles := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = point
	node.rotation = angles
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, label: String, point: Vector3, bottom: float, top: float, height: float, mat: Material, angles := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = mat
	node.position = point
	node.rotation = angles
	parent.add_child(node)
	return node

static func floor_patch(parent: Node3D, label: String, outline: PackedVector2Array, height: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for index in triangles:
		var point := outline[index]
		st.set_normal(Vector3.UP)
		st.set_uv(point * 0.2)
		st.add_vertex(Vector3(point.x, height, point.y))
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = st.commit()
	node.material_override = mat
	if mat is BaseMaterial3D: mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	parent.add_child(node)
	return node

static func ellipse(center: Vector2, radius: Vector2, count := 18) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var angle := float(i)*TAU/count
		points.append(center + Vector2(cos(angle),sin(angle))*radius*(1.0+sin(angle*5.0)*0.07))
	return points
