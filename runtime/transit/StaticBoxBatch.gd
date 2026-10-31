extends RefCounted
## Reuse CPU arrays for ordinary boxes instead of reading every uploaded mesh.
## Other geometry keeps SurfaceTool's original path and format.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static var unit_box: BoxMesh
static var unit_arrays: Array = []

static func append_from(tool: SurfaceTool, mesh: Mesh, surface: int, pose: Transform3D, vertex_offset: int) -> int:
	if not mesh is BoxMesh or mesh.subdivide_width != 0 or mesh.subdivide_height != 0 or mesh.subdivide_depth != 0 or mesh.flip_faces or mesh.add_uv2:
		tool.append_from(mesh,surface,pose)
		# Native Cylinder append already obtained its arrays. Count its vertices from
		# the same generator parameters instead of performing a second GPU readback.
		if mesh is CylinderMesh:
			var cylinder: CylinderMesh = mesh
			var count := (cylinder.rings+2)*(cylinder.radial_segments+1)
			if cylinder.cap_top and cylinder.top_radius > 0.0: count += cylinder.radial_segments+2
			if cylinder.cap_bottom and cylinder.bottom_radius > 0.0: count += cylinder.radial_segments+2
			return vertex_offset+count
		return vertex_offset+MESH_ARRAYS.arrays_of(mesh, surface)[Mesh.ARRAY_VERTEX].size()
	if unit_arrays.is_empty():
		unit_box = BoxMesh.new()
		unit_box.size = Vector3.ONE
		unit_arrays = unit_box.get_mesh_arrays()
	var vertices: PackedVector3Array = unit_arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = unit_arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = unit_arrays[Mesh.ARRAY_TANGENT]
	var uv: PackedVector2Array = unit_arrays[Mesh.ARRAY_TEX_UV]
	var flip := -1.0 if pose.basis.determinant() < 0.0 else 1.0
	for index in vertices.size():
		tool.set_normal(pose.basis*normals[index])
		var tangent := pose.basis*Vector3(tangents[index*4],tangents[index*4+1],tangents[index*4+2])
		tool.set_tangent(Plane(tangent,tangents[index*4+3]*flip))
		tool.set_uv(uv[index])
		tool.add_vertex(pose*(vertices[index]*mesh.size))
	for index in unit_arrays[Mesh.ARRAY_INDEX]: tool.add_index(vertex_offset+index)
	return vertex_offset+vertices.size()
