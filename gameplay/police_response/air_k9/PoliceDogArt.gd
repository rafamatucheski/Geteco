extends RefCounted
## Eight opaque, shared meshes per rig. Geometry is built once per coat, never per frame.
static var _cache: Dictionary = {}
static var _fur_material: StandardMaterial3D
static var _unit_sphere: SphereMesh

static func variant_scale(variant: int) -> float:
	return [1.0, 0.86, 1.08, 0.94][posmod(variant, 4)]

static func warm() -> void:
	for variant in 4:
		if not _cache.has(variant): _cache[variant] = _sculpt(variant)

static func build(parent: Node3D, variant: int = 0) -> Dictionary:
	variant = posmod(variant, 4)
	if not _cache.has(variant): _cache[variant] = _sculpt(variant)
	var meshes: Dictionary = _cache[variant]
	_attach(parent, "CoatAndHarness", meshes.body)
	var head := _pivot(parent, "Head", Vector3(0, 0.94, -0.53))
	_attach(head, "FaceAndEars", meshes.head)
	var jaw := _pivot(head, "Jaw", Vector3(0, -0.092, -0.13))
	_attach(jaw, "LowerJaw", meshes.jaw)
	var legs: Array[Node3D] = []
	for rear in [false, true]:
		for side in [-1.0, 1.0]:
			var leg := _pivot(parent, "HindLeg" if rear else "ForeLeg", Vector3(side * 0.153, 0.55, 0.35 if rear else -0.31))
			_attach(leg, "LegAndPaw", meshes.rear if rear else meshes.front)
			legs.append(leg)
	var tail := _pivot(parent, "Tail", Vector3(0, 0.70, 0.46))
	_attach(tail, "TailCoat", meshes.tail)
	return {"legs": legs, "head": head, "jaw": jaw, "tail": tail}

static func _pivot(parent: Node3D, label: String, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = label
	node.position = position
	parent.add_child(node)
	return node

static func _attach(parent: Node3D, label: String, mesh: ArrayMesh) -> void:
	if _fur_material == null:
		_fur_material = StandardMaterial3D.new()
		_fur_material.vertex_color_use_as_albedo = true
		_fur_material.vertex_color_is_srgb = true
		_fur_material.roughness = 0.88
		_fur_material.metallic_specular = 0.2
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = _fur_material
	parent.add_child(node)

static func _palette(variant: int) -> Dictionary:
	var colors: Array = [
		["b88349", "332c28", "e1b47a", "2b2825", "986c59", "bb7930", "203132", "baaa78"],
		["c59a57", "916c3d", "e3c28a", "302b29", "976653", "c28c3e", "3c4531", "c6bb87"],
		["40464a", "22292e", "72777b", "20262a", "776365", "a88144", "263a40", "afbbbc"],
		["d6bb87", "b39766", "eee0b7", "65584a", "b38671", "886536", "665239", "d5c49e"]
	][variant]
	return {"fur": Color(colors[0]), "back": Color(colors[1]), "light": Color(colors[2]), "mask": Color(colors[3]), "ear": Color(colors[4]), "eye": Color(colors[5]), "harness": Color(colors[6]), "trim": Color(colors[7]), "variant": variant}

static func _sculpt(variant: int) -> Dictionary:
	var p := _palette(variant)
	var body := _surface()
	# O peito, a cintura recolhida e os quartos arredondados formam uma pele fechada contínua.
	_loft(body, [Vector4(-0.49, 0.65, 0.045, 0.08), Vector4(-0.41, 0.64, 0.15, 0.22), Vector4(-0.27, 0.64, 0.215, 0.275), Vector4(-0.06, 0.67, 0.195, 0.235), Vector4(0.15, 0.675, 0.147, 0.17), Vector4(0.33, 0.64, 0.183, 0.215), Vector4(0.45, 0.635, 0.12, 0.175), Vector4(0.51, 0.65, 0.025, 0.06)], p, "body")
	_loft(body, [Vector4(-0.625, 0.91, 0.085, 0.09), Vector4(-0.55, 0.865, 0.128, 0.18), Vector4(-0.43, 0.77, 0.17, 0.23), Vector4(-0.30, 0.71, 0.18, 0.21), Vector4(-0.23, 0.70, 0.105, 0.14)], p, "neck")
	# Tiras ajustadas envolvem a caixa torácica, com uma sela macia e ferragens pequenas.
	_band(body, -0.235, 0.64, 0.225, 0.282, 0.047, p.harness)
	_band(body, 0.04, 0.674, 0.184, 0.214, 0.042, p.harness)
	_sphere(body, Vector3(0, 0.888, -0.105), Vector3(0.295, 0.057, 0.35), p.harness)
	for side in [-1.0, 1.0]:
		_sphere(body, Vector3(side * 0.214, 0.66, -0.238), Vector3(0.033, 0.065, 0.068), p.trim)
		_sphere(body, Vector3(side * 0.188, 0.748, -0.12), Vector3(0.032, 0.055, 0.18), p.harness)
	_sphere(body, Vector3(0, 0.922, -0.10), Vector3(0.085, 0.019, 0.073), p.trim)
	var head := _surface()
	_loft(head, [Vector4(-0.225, -0.015, 0.065, 0.083), Vector4(-0.15, 0.006, 0.123, 0.132), Vector4(-0.065, 0.035, 0.148, 0.158), Vector4(0.045, 0.035, 0.139, 0.153), Vector4(0.13, 0.005, 0.09, 0.116), Vector4(0.158, -0.015, 0.025, 0.05)], p, "head")
	_loft(head, [Vector4(-0.394, -0.042, 0.049, 0.031), Vector4(-0.355, -0.036, 0.065, 0.042), Vector4(-0.27, -0.023, 0.077, 0.054), Vector4(-0.185, -0.006, 0.094, 0.076), Vector4(-0.12, 0.018, 0.09, 0.075)], p, "muzzle")
	_sphere(head, Vector3(0, -0.047, -0.393), Vector3(0.137, 0.079, 0.073), Color("20262a"))
	_sphere(head, Vector3(0, -0.025, -0.412), Vector3(0.081, 0.018, 0.033), Color("404348"))
	# Um palato escuro fica dentro da boca quando a mandíbula independente abre.
	_sphere(head, Vector3(0, -0.080, -0.275), Vector3(0.117, 0.022, 0.196), Color("332527"))
	for side in [-1.0, 1.0]:
		_ear(head, side, p)
		var eye_position := Vector3(side * 0.125, 0.044, -0.145)
		_sphere(head, eye_position, Vector3(0.038, 0.044, 0.052), p.mask)
		_sphere(head, eye_position + Vector3(side * 0.012, 0, -0.008), Vector3(0.014, 0.025, 0.029), p.eye)
		_sphere(head, eye_position + Vector3(side * 0.018, 0, -0.012), Vector3(0.008, 0.021, 0.016), Color("151b20"))
		_sphere(head, eye_position + Vector3(side * 0.022, 0.007, -0.016), Vector3(0.005, 0.006, 0.006), Color("ece4d3"))
		_sphere(head, eye_position + Vector3(side * -0.006, 0.033, 0.012), Vector3(0.048, 0.027, 0.064), p.light)
		_sphere(head, Vector3(side * 0.078, -0.041, -0.26), Vector3(0.032, 0.037, 0.086), p.mask.lightened(0.055))
	var jaw := _surface()
	_loft(jaw, [Vector4(-0.254, -0.010, 0.035, 0.016), Vector4(-0.212, -0.012, 0.058, 0.028), Vector4(-0.12, -0.016, 0.071, 0.035), Vector4(-0.022, -0.012, 0.078, 0.044), Vector4(0.035, 0.005, 0.035, 0.03)], p, "jaw")
	_sphere(jaw, Vector3(0, 0.018, -0.132), Vector3(0.105, 0.017, 0.19), Color("362329"))
	_sphere(jaw, Vector3(0, 0.029, -0.16), Vector3(0.06, 0.012, 0.087), Color("b97678"))
	for side in [-1.0, 1.0]:
		_sweep(jaw, [Vector3(side * 0.047, 0.006, -0.17), Vector3(side * 0.047, 0.034, -0.168), Vector3(side * 0.046, 0.053, -0.174)], [Vector2(0.012, 0.014), Vector2(0.008, 0.009), Vector2(0.0015, 0.002)], p, "tooth", 2, 8)
	var tail := _surface()
	_sweep(tail, [Vector3(0, -0.02, -0.085), Vector3(0, 0, 0), Vector3(0, -0.065, 0.12), Vector3(0, -0.20, 0.28), Vector3(0, -0.34, 0.40), Vector3(0, -0.37, 0.47)], [Vector2(0.024, 0.03), Vector2(0.072, 0.076), Vector2(0.079, 0.083), Vector2(0.067, 0.075), Vector2(0.042, 0.052), Vector2(0.005, 0.008)], p, "tail")
	return {"body": _finish(body), "head": _finish(head), "jaw": _finish(jaw), "front": _leg(p, false), "rear": _leg(p, true), "tail": _finish(tail)}

static func _leg(p: Dictionary, rear: bool) -> ArrayMesh:
	var surface := _surface()
	# Tampas superiores minúsculas ficam enterradas na caixa torácica. O volume completo de ombro/coxa
	# cresce abaixo delas, então a articulação expõe músculo arredondado em vez de um tubo cortado.
	if rear:
		_sweep(surface, [Vector3(0, 0.125, 0.015), Vector3(0, 0.05, 0.008), Vector3(0, -0.045, -0.025), Vector3(0, -0.18, -0.084), Vector3(0, -0.295, 0.048), Vector3(0, -0.36, 0.06), Vector3(0, -0.467, -0.015)], [Vector2(0.014, 0.021), Vector2(0.083, 0.11), Vector2(0.101, 0.133), Vector2(0.063, 0.079), Vector2(0.04, 0.051), Vector2(0.042, 0.045), Vector2(0.034, 0.037)], p, "leg")
	else:
		_sweep(surface, [Vector3(0, 0.19, 0.016), Vector3(0, 0.075, 0.008), Vector3(0, 0, 0), Vector3(0, -0.17, 0.016), Vector3(0, -0.30, 0.005), Vector3(0, -0.437, -0.006), Vector3(0, -0.474, -0.018)], [Vector2(0.014, 0.02), Vector2(0.066, 0.081), Vector2(0.074, 0.082), Vector2(0.046, 0.052), Vector2(0.034, 0.037), Vector2(0.035, 0.037), Vector2(0.042, 0.05)], p, "leg")
	_sphere(surface, Vector3(0, -0.494, -0.060), Vector3(0.125, 0.108, 0.18), p.fur.lerp(p.light, 0.32))
	# Three subtle toe lobes and small claws read as a paw even in close view.
	for toe in [-1.0, 0.0, 1.0]:
		_sphere(surface, Vector3(toe * 0.035, -0.509, -0.113), Vector3(0.043, 0.067, 0.068), p.fur.lerp(p.light, 0.35))
		_sphere(surface, Vector3(toe * 0.035, -0.512, -0.148), Vector3(0.013, 0.019, 0.023), Color("514c43"))
	return _finish(surface)

static func _finish(surface: SurfaceTool) -> ArrayMesh:
	# Share identical vertices across triangles without changing geometry or normals.
	surface.index()
	return surface.commit()

static func _ear(surface: SurfaceTool, side: float, p: Dictionary) -> void:
	# Orelhas triangulares achatadas e arredondadas com espessura de verdade, não cones.
	var base := Vector3(side * 0.097, 0.126, 0.045)
	var points: Array = [base, base + Vector3(side * 0.004, 0.075, 0.004), base + Vector3(side * 0.012, 0.166, 0.014), base + Vector3(side * 0.019, 0.244, 0.024), base + Vector3(side * 0.02, 0.258, 0.027)]
	_sweep(surface, points, [Vector2(0.068, 0.037), Vector2(0.056, 0.027), Vector2(0.034, 0.018), Vector2(0.008, 0.007), Vector2(0.002, 0.002)], p, "ear")
	var inside := _surface_palette(p.ear)
	_sweep(surface, [base + Vector3(0, 0.038, -0.027), base + Vector3(side * 0.005, 0.088, -0.023), base + Vector3(side * 0.013, 0.162, -0.004), base + Vector3(side * 0.017, 0.215, 0.013)], [Vector2(0.038, 0.009), Vector2(0.037, 0.009), Vector2(0.019, 0.006), Vector2(0.002, 0.002)], inside, "solid", 3, 12)

static func _surface() -> SurfaceTool:
	var result := SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	return result

static func _surface_palette(color: Color) -> Dictionary:
	return {"fur": color}

static func _loft(surface: SurfaceTool, sections: Array, p: Dictionary, kind: String) -> void:
	var points: Array = []
	var radii: Array = []
	for section: Vector4 in sections:
		points.append(Vector3(0, section.y, section.x))
		radii.append(Vector2(section.z, section.w))
	_sweep(surface, points, radii, p, kind)

static func _sweep(surface: SurfaceTool, controls: Array, sizes: Array, p: Dictionary, kind: String, subdivisions: int = 3, sides: int = 16) -> void:
	var centers: Array[Vector3] = []
	var radii: Array[Vector2] = []
	for index in controls.size() - 1:
		for step in subdivisions:
			var t := float(step) / subdivisions
			var a: int = maxi(0, index - 1)
			var b: int = mini(controls.size() - 1, index + 2)
			centers.append(_catmull(controls[a], controls[index], controls[index + 1], controls[b], t))
			var radius := Vector2(_cubic(sizes[a].x, sizes[index].x, sizes[index + 1].x, sizes[b].x, t), _cubic(sizes[a].y, sizes[index].y, sizes[index + 1].y, sizes[b].y, t))
			radii.append(Vector2(maxf(0.001, radius.x), maxf(0.001, radius.y)))
	centers.append(controls[-1])
	radii.append(sizes[-1])
	var rings: Array[PackedVector3Array] = []
	for index in centers.size():
		var tangent: Vector3 = (centers[mini(index + 1, centers.size() - 1)] - centers[maxi(0, index - 1)]).normalized()
		var up: Vector3 = tangent.cross(Vector3.RIGHT).normalized()
		var ring := PackedVector3Array()
		for corner in sides:
			var theta := TAU * float(corner) / sides
			ring.append(centers[index] + Vector3.RIGHT * cos(theta) * radii[index].x + up * sin(theta) * radii[index].y)
		rings.append(ring)
	var normals: Array[PackedVector3Array] = []
	for index in rings.size():
		var ring_normals := PackedVector3Array()
		for corner in sides:
			var across: Vector3 = rings[index][(corner + 1) % sides] - rings[index][posmod(corner - 1, sides)]
			var along: Vector3 = rings[mini(index + 1, rings.size() - 1)][corner] - rings[maxi(0, index - 1)][corner]
			ring_normals.append(across.cross(along).normalized())
		normals.append(ring_normals)
	for index in rings.size() - 1:
		for corner in sides:
			var next := (corner + 1) % sides
			for tri: Array in [[[index, corner], [index + 1, corner], [index + 1, next]], [[index, corner], [index + 1, next], [index, next]]]:
				var vertices: Array[Vector3] = []
				var face_normals: Array[Vector3] = []
				var colors: Array[Color] = []
				for address: Array in tri:
					var ring_index: int = address[0]
					var vertex_index: int = address[1]
					vertices.append(rings[ring_index][vertex_index])
					face_normals.append(normals[ring_index][vertex_index])
					colors.append(_coat(rings[ring_index][vertex_index], sin(TAU * float(vertex_index) / sides), p, kind))
				_triangle(surface, vertices, face_normals, colors)
	# Tampas explícitas deixam todas as partes fechadas, incluindo a boca e as pontas das orelhas.
	for end in [0, rings.size() - 1]:
		var normal: Vector3 = (centers[0] - centers[1]).normalized() if end == 0 else (centers[-1] - centers[-2]).normalized()
		for corner in sides:
			var points: Array[Vector3] = [centers[end], rings[end][corner], rings[end][(corner + 1) % sides]]
			var color := _coat(centers[end], 0.0, p, kind)
			_triangle(surface, points, [normal, normal, normal], [color, color, color])

static func _coat(point: Vector3, top: float, p: Dictionary, kind: String) -> Color:
	var fur: Color = p.fur
	if kind == "solid": return fur
	if kind == "tooth": return Color("eee0bd")
	if kind == "muzzle": return p.mask.lerp(fur, 0.13 * maxf(0, top))
	if kind == "ear": return fur.lerp(p.back, 0.58)
	if kind == "jaw": return fur.lerp(p.mask, smoothstep(-0.012, 0.026, point.y) * 0.9)
	if kind == "leg": return fur.lerp(p.light, smoothstep(-0.22, -0.45, point.y) * 0.26)
	if kind == "tail": return fur.lerp(p.back, smoothstep(-0.45, 0.45, top) * 0.9 + smoothstep(0.32, 0.47, point.z) * 0.08)
	if kind == "head":
		var crown := smoothstep(0.02, 0.14, point.y) * smoothstep(-0.15, 0.025, point.z)
		return fur.lerp(p.back, crown * 0.72).lerp(p.mask, smoothstep(-0.12, -0.225, point.z) * 0.35)
	if kind == "neck": return fur.lerp(p.back, smoothstep(0.1, 0.9, top) * 0.78).lerp(p.light, smoothstep(0.0, -0.65, top) * 0.28)
	var saddle := smoothstep(-0.27, 0.5, top) * smoothstep(-0.43, -0.13, point.z)
	if int(p.variant) in [1, 3]: saddle *= 0.45
	return fur.lerp(p.back, saddle).lerp(p.light, smoothstep(-0.2, -0.85, top) * 0.18)

static func _band(surface: SurfaceTool, z: float, y: float, width: float, height: float, thickness: float, color: Color) -> void:
	_loft(surface, [Vector4(z - thickness * 0.5, y, width, height), Vector4(z + thickness * 0.5, y, width, height)], _surface_palette(color), "solid")

static func _sphere(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 12
		_unit_sphere.rings = 6
	var arrays: Array = _unit_sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for triangle in range(0, indices.size(), 3):
		for corner in 3:
			var index := indices[triangle + corner]
			surface.set_color(color)
			surface.set_normal((normals[index] / size).normalized())
			surface.add_vertex(center + vertices[index] * size)

static func _triangle(surface: SurfaceTool, vertices: Array[Vector3], normals: Array[Vector3], colors: Array[Color]) -> void:
	# No Godot as faces frontais usam enrolamento horário. Normais analíticas nunca dependem
	# da triangulação nem de divisões acidentais de vértice nas fronteiras da pelagem.
	var reverse := (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normals[0] + normals[1] + normals[2]) > 0.0
	for corner in ([0, 2, 1] if reverse else [0, 1, 2]):
		surface.set_color(colors[corner])
		surface.set_normal(normals[corner])
		surface.add_vertex(vertices[corner])

static func _catmull(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)

static func _cubic(a: float, b: float, c: float, d: float, t: float) -> float:
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)
