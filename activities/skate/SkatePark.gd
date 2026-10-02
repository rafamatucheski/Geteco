extends Node3D
const LAYOUT := preload("res://activities/skate/SkateParkLayout.gd")
static var _concrete: StandardMaterial3D

func _ready() -> void:
	add_to_group("skate_park")
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in 28:
		for z in 34:
			var a := LAYOUT.FOOTPRINT.position + Vector2(x, z) * .5
			var b := a + Vector2(.5, 0)
			var c := a + Vector2(0, .5)
			var d := a + Vector2(.5, .5)
			for p: Vector2 in [a, b, c, b, d, c]:
				surface.set_uv(p * .5)
				surface.add_vertex(Vector3(p.x, LAYOUT.height_at(p), p.y))
	surface.index()
	surface.generate_normals()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "BowlConcrete"
	floor_mesh.mesh = surface.commit()
	var concrete := _concrete_material()
	floor_mesh.material_override = concrete
	add_child(floor_mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = floor_mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 128:
		var points: Array[Vector3] = []
		for angle in [TAU * i / 128.0, TAU * (i + 1) / 128.0]:
			var edge := LAYOUT.lip(angle)
			var outward := (edge - Vector2(LAYOUT.CENTER.x, LAYOUT.CENTER.z)).normalized()
			for width in [-.04, .04]:
				var p: Vector2 = edge + outward * float(width)
				points.append(Vector3(p.x, .057, p.y))
		for index in [0, 1, 2, 1, 3, 2]: rim.add_vertex(points[index])
	rim.generate_normals()
	var coping := MeshInstance3D.new()
	coping.mesh = rim.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("939895")
	mat.metallic = .6
	mat.roughness = .45
	coping.material_override = mat
	add_child(coping)
	_build_street_section(concrete)
	_build_rest_area()

static func _concrete_material() -> StandardMaterial3D:
	if _concrete != null: return _concrete
	# Poured skate concrete: fine aggregate and wear, without the port slab grid.
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 8173
	noise.frequency = .045
	for y in 128:
		for x in 128:
			var wear := noise.get_noise_2d(x, y) * .07
			var grit := noise.get_noise_2d(x * 9.0, y * 9.0) * .025
			image.set_pixel(x, y, Color(.66 + wear + grit, .65 + wear + grit, .61 + wear + grit))
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_texture = ImageTexture.create_from_image(image)
	_concrete.roughness = .94
	_concrete.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _concrete

func _box(at: Vector3, dimensions: Vector3, color: Color, solid := false) -> void:
	var art := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	art.mesh = mesh
	art.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .8
	art.material_override = mat
	add_child(art)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var hull := BoxShape3D.new()
		hull.size = dimensions
		shape.shape = hull
		body.position = at
		body.add_child(shape)
		add_child(body)

func _build_street_section(concrete: Material) -> void:
	# Small bank with a broad landing, not a freestanding triangular wall.
	var bank := SurfaceTool.new()
	bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := [Vector3(63, .025, 85.6), Vector3(65.6, .025, 85.6), Vector3(63, .60, 87), Vector3(65.6, .60, 87), Vector3(63, .025, 88.1), Vector3(65.6, .025, 88.1)]
	for index in [0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4, 0, 2, 4, 1, 5, 3]:
		bank.add_vertex(vertices[index])
	bank.generate_normals()
	var mesh := bank.commit()
	var art := MeshInstance3D.new()
	art.mesh = mesh
	art.material_override = concrete
	add_child(art)
	var body := StaticBody3D.new()
	var hull := CollisionShape3D.new()
	hull.shape = mesh.create_trimesh_shape()
	body.add_child(hull)
	add_child(body)
	# Grind ledge and flat rail, both occupy physical space. Tricks remain simple.
	_box(Vector3(72.6, .27, 99.3), Vector3(.55, .49, 2.2), Color("a6a69c"), true)
	_box(Vector3(72.6, .53, 99.3), Vector3(.59, .035, 2.24), Color("616966"))
	_box(Vector3(72.65, .5, 91), Vector3(.065, .065, 2.5), Color("656d70"), true)
	for z in [90.1, 91.9]:
		_box(Vector3(72.65, .26, z), Vector3(.065, .48, .065), Color("656d70"), true)
		_box(Vector3(72.65, .05, z), Vector3(.35, .05, .12), Color("515957"))

func _build_rest_area() -> void:
	# Bench on the dry deck, away from the approach and bowl transition.
	for z in [101.3, 101.5, 101.7]:
		_box(Vector3(62, .46, z), Vector3(2.3, .07, .16), Color("8b7053"))
	for x in [61.15, 62.85]:
		_box(Vector3(x, .24, 101.5), Vector3(.12, .44, .55), Color("555e5b"))
	# Reserve the entire bench footprint, rather than allowing passage through the seat.
	var bench_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.3, .5, .65)
	shape.shape = hull
	bench_body.position = Vector3(62, .25, 101.5)
	bench_body.add_child(shape)
	add_child(bench_body)
