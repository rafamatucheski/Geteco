extends RefCounted
## Casco opaco autorado, uma superfície por perfil. Capô e porta-malas ficam abaixo
## do teto; a altura acompanha a carroceria em vez de preencher toda a AABB do Body.
## Base: passenger original-inventory/production.json (11/10/2026), com as mudanças
## autoradas em tools/fleet_refresh_20261019/build_current.gd aplicadas ao criar o
## recurso compartilhado. Os limites atuais são conferidos; ainda exige A/B visual.
## Linhas: z, meia largura inferior, y da cintura, meia largura do teto, y do topo, y do fundo.
const PROFILE_IDS := ["aurora_executive", "union_sedan", "sedan_classic"]
const PROFILES := {
	"aurora_executive": {
		"bounds": AABB(Vector3(-1.10504, .205, -2.685), Vector3(2.21008, 1.1439, 5.385)),
		"rows": [
			[-2.63, .88, .55, .88, .55, .27],
			[-2.48, .97, .76, .91, .78, .25],
			[-.98, .99, .87, .91, .89, .205],
			[-.43, .99, .87, .72, 1.435, .205],
			[1.10, .99, .87, .72, 1.435, .205],
			[1.46, .98, .87, .91, .89, .205],
			[2.48, .95, .76, .89, .78, .25],
			[2.60, .88, .55, .88, .55, .27],
		],
	},
	"union_sedan": {
		"bounds": AABB(Vector3(-.98784, .18, -2.38), Vector3(1.97568, 1.20, 4.78)),
		"rows": [
			[-2.32, .85, .48, .85, .48, .29],
			[-2.25, .88, .78, .84, .80, .26],
			[-.98, .89, .80, .78, .82, .18],
			[-.68, .89, .80, .68, 1.38, .18],
			[.92, .89, .80, .68, 1.38, .18],
			[1.20, .88, .81, .78, .83, .18],
			[2.25, .87, .81, .82, .83, .26],
			[2.32, .85, .48, .85, .48, .29],
		],
	},
	"sedan_classic": {
		"bounds": AABB(Vector3(-.98784, .18, -2.1784), Vector3(1.97568, 1.284, 4.3704)),
		"rows": [
			[-2.32, .85, .48, .85, .48, .29],
			[-2.25, .88, .78, .84, .80, .26],
			[-.98, .89, .80, .78, .82, .18],
			[-.68, .89, .80, .68, 1.38, .18],
			[.92, .89, .80, .68, 1.38, .18],
			[1.20, .88, .81, .78, .83, .18],
			[2.25, .87, .81, .82, .83, .26],
			[2.32, .85, .48, .85, .48, .29],
		],
	},
}
static var _meshes: Dictionary = {}
static var _material: StandardMaterial3D

static func profile_id(archetype: String) -> String:
	return archetype

static func supports(archetype: String) -> bool:
	return archetype in PROFILE_IDS

static func accepts_bounds(archetype: String, box: AABB) -> bool:
	if not supports(archetype) or not box.position.is_finite() or not box.size.is_finite(): return false
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0: return false
	var expected: AABB = PROFILES[profile_id(archetype)].bounds
	# Aceita pequenos arredondamentos/acabamentos. Uma carroceria remodelada exige
	# atualizar e validar o perfil, sem esticar um casco antigo sobre ela.
	return _within(box.position, expected.position, .12) and _within(box.end, expected.end, .12)

static func _within(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return absf(a.x-b.x) <= tolerance and absf(a.y-b.y) <= tolerance and absf(a.z-b.z) <= tolerance

static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.resource_name = "vehicle_shadow_shell"
		_material.roughness = 1.0
	return _material

static func mesh_for(archetype: String) -> ArrayMesh:
	if not supports(archetype): return null
	var key := profile_id(archetype)
	if _meshes.has(key): return _meshes[key] as ArrayMesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var rows: Array = PROFILES[key].rows
	var outward_faces := [Vector3.DOWN, Vector3.RIGHT, Vector3(1,1,0), Vector3.UP, Vector3(-1,1,0), Vector3.LEFT]
	var previous := _ring(rows[0], key)
	_cap(vertices, normals, previous, Vector3.FORWARD)
	for i in range(1, rows.size()):
		var current := _ring(rows[i], key)
		for edge in previous.size():
			var next := (edge + 1) % previous.size()
			# O anel é anti-horário visto de +Z. A face frontal no Godot é horária;
			# a emissão abaixo orienta os triângulos contra seu produto vetorial.
			var outward: Vector3 = outward_faces[edge]
			_triangle(vertices, normals, previous[edge], previous[next], current[next], outward)
			_triangle(vertices, normals, previous[edge], current[next], current[edge], outward)
		previous = current
	_cap(vertices, normals, previous, Vector3.BACK)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.resource_name = "VehicleShadowShell_" + key
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh

static func _ring(row: Array, profile: String) -> PackedVector3Array:
	var z := float(row[0])
	var width := float(row[1])
	var belt := float(row[2])
	var roof_width := float(row[3])
	var top := float(row[4])
	var bottom := float(row[5])
	var ring := PackedVector3Array([Vector3(-width,bottom,z), Vector3(width,bottom,z),
		Vector3(width,belt,z), Vector3(roof_width,top,z), Vector3(-roof_width,top,z), Vector3(-width,belt,z)])
	for i in ring.size(): ring[i] = _fleet_point(ring[i], profile)
	return ring

static func _fleet_point(point: Vector3, profile: String) -> Vector3:
	# Mesmo ajuste autorado da frota instalada em 19/10/2026. Executa só ao montar
	# o recurso de cada perfil no pré-aquecimento, sem ler a malha nem custo por quadro.
	var result := point
	if profile == "sedan_classic":
		if absf(result.z) > 1.75: result.z = signf(result.z) * (1.75 + (absf(result.z) - 1.75) * .68)
		if result.y > .78: result.y = .78 + (result.y - .78) * 1.14
	elif profile == "union_sedan":
		if result.y > .80 and result.z > .28:
			result.z += .12 * clampf((result.y - .80) / .58, 0, 1) * clampf((result.z - .28) / .50, 0, 1)
	elif profile == "aurora_executive" and result.y > .82:
		var height := clampf((result.y - .82) / .62, 0, 1)
		result.y = .82 + (result.y - .82) * .86
		if result.z > .30: result.z += .15 * height * clampf((result.z - .30) / .5, 0, 1)
	return result

static func _cap(vertices: PackedVector3Array, normals: PackedVector3Array, ring: PackedVector3Array, outward: Vector3) -> void:
	for i in range(1, ring.size()-1): _triangle(vertices, normals, ring[0], ring[i], ring[i+1], outward)

static func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var cross := (b-a).cross(c-a)
	if cross.length_squared() < .00000001: return
	if cross.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	var normal := -(b-a).cross(c-a).normalized()
	vertices.append_array(PackedVector3Array([a,b,c]))
	normals.append_array(PackedVector3Array([normal,normal,normal]))
