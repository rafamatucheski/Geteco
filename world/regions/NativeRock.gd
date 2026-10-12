extends RefCounted
## Malha de pedra irregular compartilhada (pedras da montanha e copas de árvores).
## Icosfera subdividida e deformada por ruído, com facetas planas e cor por vértice. Antes as pedras
## eram uma SphereMesh 7x3 achatada, de cor chapada, e todas pareciam a mesma bola amassada.
static var _cache := {}
const PHI := 1.618034
## Escala por variante (largura, altura, profundidade) e semente do ruído.
const VARIANTS := [
	{"scale": Vector3(1.0, 0.72, 0.86), "seed": 1.7, "amp": 0.26},
	{"scale": Vector3(1.12, 0.58, 0.80), "seed": 4.1, "amp": 0.30},
	{"scale": Vector3(0.90, 0.86, 0.96), "seed": 7.3, "amp": 0.24},
]
const BASE_FLOOR := 0.55

static func variant_count() -> int:
	return VARIANTS.size()

## Variante estável pela posição: a malha e a colisão concordam sem sorteio extra.
static func variant_for(point: Vector3) -> int:
	return int(floorf(absf(point.x * 7.31 + point.z * 3.17))) % VARIANTS.size()

static func mesh(variant: int, detail: int = 1) -> ArrayMesh:
	variant = posmod(variant, VARIANTS.size())
	var key := "mesh_%d_%d" % [variant, detail]
	if _cache.has(key): return _cache[key]
	var spec: Dictionary = VARIANTS[variant]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	append_blob(st, Vector3.ZERO, spec.scale, float(spec.seed), float(spec.amp), Color(0.56, 0.55, 0.53), Color(1.0, 0.99, 0.96), detail, true)
	st.generate_normals()
	var result := st.commit()
	_cache[key] = result
	return result

## Casco convexo barato (vértices únicos da malha de detalhe 1) para a colisão de pedras sólidas.
static func hull(variant: int) -> PackedVector3Array:
	variant = posmod(variant, VARIANTS.size())
	var key := "hull_%d" % variant
	if _cache.has(key): return _cache[key]
	var spec: Dictionary = VARIANTS[variant]
	var ico := _ico(1)
	var points := PackedVector3Array()
	for unit in ico.verts:
		points.append(_displace(unit, spec.scale, float(spec.seed), float(spec.amp), true))
	_cache[key] = points
	return points

## Acrescenta uma bolha facetada ao SurfaceTool (já em modo de normais planas).
static func append_blob(st: SurfaceTool, center: Vector3, radii: Vector3, seed: float, amp: float, col_lo: Color, col_hi: Color, detail: int = 1, flat_base := false) -> void:
	var ico := _ico(detail)
	var faces: Array = ico.faces
	var verts: Array = ico.verts
	for face_index in faces.size():
		var face: Array = faces[face_index]
		var jitter := (_hash(float(face_index) * 1.37 + seed) - 0.5) * 0.16
		var points: Array[Vector3] = []
		var colors: Array[Color] = []
		for vertex_index in face:
			var unit: Vector3 = verts[vertex_index]
			points.append(center + _displace(unit, radii, seed, amp, flat_base))
			var t := clampf(unit.y * 0.5 + 0.5, 0.0, 1.0)
			var color := col_lo.lerp(col_hi, t)
			colors.append(Color(clampf(color.r + jitter, 0.0, 1.5), clampf(color.g + jitter, 0.0, 1.5), clampf(color.b + jitter, 0.0, 1.5), 1.0))
		# Ordem horária: face frontal do Godot.
		for i in [0, 2, 1]:
			st.set_color(colors[i])
			st.add_vertex(points[i])

static func _displace(unit: Vector3, radii: Vector3, seed: float, amp: float, flat_base: bool) -> Vector3:
	var n := sin(unit.x * 2.3 + seed) * cos(unit.y * 2.9 - seed * 0.7) * 0.5 \
		+ sin(unit.z * 3.4 + seed * 1.7 + unit.x * 1.3) * 0.35 \
		+ sin((unit.x + unit.y + unit.z) * 5.1 + seed) * 0.15
	var p := unit * (1.0 + amp * n) * radii
	if flat_base: p.y = maxf(p.y, -BASE_FLOOR * radii.y)
	return p

static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)

static func _ico(detail: int) -> Dictionary:
	var key := "ico_%d" % detail
	if _cache.has(key): return _cache[key]
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, PHI, 0), Vector3(1, PHI, 0), Vector3(-1, -PHI, 0), Vector3(1, -PHI, 0),
			Vector3(0, -1, PHI), Vector3(0, 1, PHI), Vector3(0, -1, -PHI), Vector3(0, 1, -PHI),
			Vector3(PHI, 0, -1), Vector3(PHI, 0, 1), Vector3(-PHI, 0, -1), Vector3(-PHI, 0, 1)]:
		verts.append(v.normalized())
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
		[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
		[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for _step in detail:
		var midpoints := {}
		var next: Array = []
		for face in faces:
			var ab := _midpoint(verts, midpoints, face[0], face[1])
			var bc := _midpoint(verts, midpoints, face[1], face[2])
			var ca := _midpoint(verts, midpoints, face[2], face[0])
			next.append([face[0], ab, ca])
			next.append([face[1], bc, ab])
			next.append([face[2], ca, bc])
			next.append([ab, bc, ca])
		faces = next
	var result := {"verts": verts, "faces": faces}
	_cache[key] = result
	return result

static func _midpoint(verts: Array[Vector3], midpoints: Dictionary, a: int, b: int) -> int:
	var key := "%d_%d" % [mini(a, b), maxi(a, b)]
	if midpoints.has(key): return midpoints[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	midpoints[key] = verts.size() - 1
	return verts.size() - 1
