extends RefCounted
## Matacões facetados e gastos pelo tempo. Silhueta com semente; sem apresentação de cubo primitivo.
## Os limites ficam dentro da área existente, com um volume de bloqueio explícito.
static func rock(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var seed_value := absi(int(at.x*71+at.z*133+size.x*913))
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	var rings: Array[PackedVector3Array]=[]
	for level in 4:
		var ring := PackedVector3Array()
		var height: float=[-.45,-.22,.22,.44][level]
		var radius: float=[.64,1.0,.83,.39][level]
		for side in 8:
			var angle := float(side)*TAU/8+.11*float(level)
			var r := radius*rng.randf_range(.83,1.0)
			ring.append(Vector3(cos(angle)*r*size.x*.5,(height+rng.randf_range(-.025,.025))*size.y,sin(angle)*r*size.z*.5))
		rings.append(ring)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for level in 3:
		for side in 8:
			var next := (side+1)%8
			_triangle(vertices,normals,colors,rings[level][side],rings[level+1][side],rings[level+1][next],color,level)
			_triangle(vertices,normals,colors,rings[level][side],rings[level+1][next],rings[level][next],color,level)
	for side in 8:
		_triangle(vertices,normals,colors,rings[3][side],Vector3(0,size.y*.46,0),rings[3][(side+1)%8],color,3)
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.vertex_color_is_srgb=true
	material.roughness=.98
	var node := MeshInstance3D.new()
	node.name=label
	node.position=at
	node.mesh=mesh
	node.material_override=material
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer=1
		body.collision_mask=0
		var shape := CollisionShape3D.new()
		# A carcaça convexa segue a silhueta afunilada visível em vez de uma caixa invisível.
		# Pontos da CPU (a física calcula o casco, como o clean de create_convex_shape): sem ler a malha da GPU.
		var hull := ConvexPolygonShape3D.new()
		hull.points=vertices
		shape.shape=hull
		body.add_child(shape)
		node.add_child(body)
	return node

static func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color, level: int) -> void:
	var normal := (b-a).cross(c-a).normalized()
	var tone := color*(.85+float(level)*.055)
	tone.a=1.0
	vertices.append_array(PackedVector3Array([a,c,b]))
	for i in 3:
		normals.append(normal)
		colors.append(tone)
