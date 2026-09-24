extends RefCounted

static func rock(parent: Node3D, point: Vector3, size: Vector3, seed_value: int, color: Color) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for j in 5:
		var ring := PackedVector3Array()
		var y := float(j)/4.0
		for i in 9:
			var a := TAU*float(i)/9.0
			var r := sin(PI*(0.12+y*0.76))*rng.randf_range(0.78,1.12)
			ring.append(Vector3(cos(a)*r*0.5,y-0.5,sin(a)*r*0.5)*size)
		rings.append(ring)
	for j in 4:
		for i in 9:
			var k := (i+1)%9
			var shade := color.darkened(rng.randf_range(0.0,0.24))
			for v in [rings[j][i],rings[j+1][i],rings[j+1][k],rings[j][i],rings[j+1][k],rings[j][k]]:
				surface.set_color(shade)
				surface.add_vertex(v)
	for i in 9:
		var k := (i+1)%9
		for v in [rings[4][i],Vector3(0,size.y*0.53,0),rings[4][k],rings[0][k],Vector3(0,-size.y*0.51,0),rings[0][i]]:
			surface.set_color(color.darkened(rng.randf_range(0.0,0.15)))
			surface.add_vertex(v)
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh=surface.commit()
	node.position=point
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = false
	mat.roughness=0.96
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	node.material_override=mat
	parent.add_child(node)
	return node
