extends RefCounted
## Build-time shaping: garments, seams and accessories share the same torso
## deformation, so a fuller abdomen doesn't poke through a flat shirt.
static func profile(y: float, body: int) -> Vector3:
	var belly := exp(-pow((y+.075)/.16,2))
	var hip := exp(-pow((y+.25)/.10,2))
	match body:
		1: return Vector3(1.0-.17*belly,.99-.14*belly,.008*belly)
		2: return Vector3(1.0+.25*belly+.045*hip,1.0+.36*belly,-.027*belly)
		3: return Vector3(1.0-.07*belly,1.0-.07*belly,0)
		4: return Vector3(1.0+.10*belly,1.0+.13*belly,-.009*belly)
	return Vector3(1,1,0)

static func deform_torso(torso: Node3D, body: int) -> void:
	if body==0: return
	var profiles: Dictionary={}
	for part in torso.get_children():
		if not part is MeshInstance3D: continue
		var source: Mesh=part.mesh
		var result:=ArrayMesh.new()
		var local: Transform3D=part.transform
		var inverse:=local.affine_inverse()
		var from_normal:=local.basis.inverse().transposed()
		var to_normal:=local.basis.transposed()
		for surface in source.get_surface_count():
			var arrays:=source.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for i in vertices.size():
				var point:=local*vertices[i]
				var normal: Vector3=from_normal*normals[i]
				if not profiles.has(point.y):
					profiles[point.y]=[profile(point.y,body),(profile(point.y+.001,body)-profile(point.y-.001,body))/.002]
				var shape: Vector3=profiles[point.y][0]
				var derivative: Vector3=profiles[point.y][1]
				var mapped:=Vector3(point.x*shape.x,point.y,point.z*shape.y+shape.z)
				var mapped_normal:=Vector3(normal.x/shape.x,normal.y-point.x*derivative.x*normal.x/shape.x-(point.z*derivative.y+derivative.z)*normal.z/shape.y,normal.z/shape.y)
				vertices[i]=inverse*mapped
				normals[i]=(to_normal*mapped_normal).normalized()
			arrays[Mesh.ARRAY_VERTEX]=vertices
			arrays[Mesh.ARRAY_NORMAL]=normals
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			result.surface_set_material(surface,source.surface_get_material(surface))
		part.mesh=result
