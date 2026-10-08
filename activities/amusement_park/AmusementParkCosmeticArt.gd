extends RefCounted
## Static, natural-sized souvenirs. No lights, timers or per-frame work.
const SHAPES := preload("res://assets/outfits/OutfitGeometry.gd")

static func accessory(id: String) -> Node3D:
	var result := Node3D.new()
	result.name = id
	match id:
		"star_glasses": _glasses(result, Color("d8b458"), Color("3e214c"), true)
		"amber_glasses": _glasses(result, Color("332820"), Color("ac6c25"), false)
		"ghost_mask": _mask(result, false)
		"fox_mask": _mask(result, true)
	return result

static func pickup(id: String) -> Node3D:
	if id in ["star_glasses", "amber_glasses", "ghost_mask", "fox_mask"]:
		var item := accessory(id)
		item.rotation.x = -.30
		return item
	var result := Node3D.new()
	result.name = id
	var cloth := _material(Color("306875") if id == "lume_jacket" else Color("352842"), .9)
	var trim := _material(Color("d5ac58") if id == "lume_jacket" else Color("a13f59"), .8)
	_box(result, Vector3(0, .035, 0), Vector3(.33, .065, .27), cloth)
	_box(result, Vector3(-.12, .078, .012), Vector3(.09, .04, .22), cloth)
	_box(result, Vector3(.12, .078, .012), Vector3(.09, .04, .22), cloth)
	_box(result, Vector3(0, .071, 0), Vector3(.025, .013, .25), trim)
	return result

static func _glasses(root: Node3D, frame_color: Color, lens_color: Color, stars: bool) -> void:
	var frame := _material(frame_color, .35, .4)
	var lens := _material(lens_color, .16, .45)
	for side in [-1.0, 1.0]:
		var at := Vector3(side * .039, 0, 0)
		if stars:
			_star(root, at, .039, .019, frame)
			_star(root, at + Vector3(0, 0, .006), .027, .014, lens)
		else:
			var outer := SHAPES._make_tapered_limb(.034, .034, .010, frame, at)
			outer.rotation.x = PI * .5
			root.add_child(outer)
			var inner := SHAPES._make_tapered_limb(.027, .027, .012, lens, at + Vector3(0,0,.006))
			inner.rotation.x = PI * .5
			root.add_child(inner)
		_box(root, Vector3(side * .073, .004, -.051), Vector3(.006, .007, .12), frame)
	_box(root, Vector3(0, .004, 0), Vector3(.020, .008, .009), frame)

static func _mask(root: Node3D, fox: bool) -> void:
	var shell := _material(Color("c15d36") if fox else Color("e1d9c1"), .65)
	var light := _material(Color("e4d6b7"), .8)
	var dark := _material(Color("25212b"), .82)
	# A small lower-face shell leaves both eye sockets and eyewear clear.
	root.add_child(SHAPES._make_ellipsoid(Vector3(.166, .085, .070), shell, Vector3(0, -.029, .010)))
	for side in [-1.0, 1.0]:
		if fox:
			var cheek := SHAPES._make_ellipsoid(Vector3(.065, .042, .018), light, Vector3(side*.038, -.033, .040))
			cheek.rotation.z = side * -.25
			root.add_child(cheek)
			var ear := SHAPES._make_tapered_limb(0, .024, .046, shell, Vector3(side*.067, .008, -.010))
			ear.rotation.z = -side * .24
			root.add_child(ear)
		else:
			_box(root, Vector3(side*.024, -.042, .041), Vector3(.018, .014, .008), dark)
	root.add_child(SHAPES._make_ellipsoid(Vector3(.025, .020, .018), dark, Vector3(0, -.017, .043)))
	_box(root, Vector3(0, -.052, .037), Vector3(.036, .006, .007), dark)
	var strap := _material(Color("29232c"), .9)
	for side in [-1.0, 1.0]:
		_box(root, Vector3(side*.080, -.015, -.048), Vector3(.008, .012, .12), strap)

static func _star(root: Node3D, at: Vector3, radius: float, inner: float, material: Material) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for index in 10:
		var angle := PI*.5 + index*TAU/10.0
		var next := PI*.5 + (index+1)*TAU/10.0
		vertices.append(Vector3.ZERO)
		vertices.append(Vector3(cos(angle), sin(angle), 0)*(radius if index%2==0 else inner))
		vertices.append(Vector3(cos(next), sin(next), 0)*(radius if (index+1)%2==0 else inner))
		for vertex in 3: normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	root.add_child(instance)

static func _material(color: Color, roughness: float, metal: float = 0) -> StandardMaterial3D:
	var result := SHAPES._make_mat(color, roughness, metal)
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

static func _box(root: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	root.add_child(SHAPES._make_box(size, material, at))
