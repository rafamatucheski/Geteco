extends RefCounted
## Dobra o polegar nas formas de punho do `dante.glb` (FistRight/FistLeft). No
## modelo o punho fecha os dedos mas só encosta o polegar esticado na direção dos
## dedos: no soco ele saía do punho como um ponteiro e lia como "joinha". O modelo
## não tem ossos de dedo, então a correção é na própria forma: os vértices do
## polegar giram em torno da base dele até deitar à frente dos dedos fechados.
## Feito uma vez por execução e compartilhado; a malha importada não muda.
##
## Medidas no espaço da malha (T-pose, palma para baixo, mão direita em x < 0;
## 2026-10-06): pulso em |x| = 0,625; polegar = vértices da frente (z > −0,005)
## entre |x| 0,62 e 0,78, base em |x| ≈ 0,665 e ponta em |x| ≈ 0,75.

const SHAPES := {"FistRight": -1.0, "FistLeft": 1.0}
const THUMB_BASE := Vector3(0.665, 1.25, 0.0)
const THUMB_MIN_Z := -0.005
const THUMB_X := Vector2(0.62, 0.78)
## Ângulo de dobra (em torno do eixo vertical da malha) e trecho em que o peso
## cresce de 0 (base, junto à palma) a 1 (falange).
const FOLD := deg_to_rad(80.0)
const RAMP := Vector2(0.645, 0.68)

static var _cache: Dictionary = {}

static func fixed(mesh: Mesh) -> Mesh:
	if not mesh is ArrayMesh: return mesh
	var key := mesh.get_rid()
	if _cache.has(key): return _cache[key]
	var source := mesh as ArrayMesh
	var targets := {}
	for index in source.get_blend_shape_count():
		var name := String(source.get_blend_shape_name(index))
		if SHAPES.has(name): targets[index] = float(SHAPES[name])
	if targets.is_empty():
		_cache[key] = mesh
		return mesh
	var result := ArrayMesh.new()
	result.blend_shape_mode = source.blend_shape_mode
	for index in source.get_blend_shape_count(): result.add_blend_shape(source.get_blend_shape_name(index))
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var shapes := source.surface_get_blend_shape_arrays(surface)
		for index in targets:
			if int(index) < shapes.size(): shapes[index] = _fold_thumb(arrays, shapes[index], float(targets[index]))
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, shapes, {}, source.surface_get_format(surface))
		result.surface_set_material(surface, source.surface_get_material(surface))
		result.surface_set_name(surface, source.surface_get_name(surface))
	_cache[key] = result
	return result

## `side`: −1 mão direita (x < 0), +1 esquerda. A dobra é espelhada entre as mãos.
static func _fold_thumb(base: Array, shape: Array, side: float) -> Array:
	var points: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	var bent: PackedVector3Array = (shape[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var normals: PackedVector3Array = (shape[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if shape.size() > Mesh.ARRAY_NORMAL and shape[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var pivot := Vector3(THUMB_BASE.x * side, THUMB_BASE.y, THUMB_BASE.z)
	for i in points.size():
		var reach := points[i].x * side
		if reach < THUMB_X.x or reach > THUMB_X.y or points[i].z < THUMB_MIN_Z: continue
		var weight := smoothstep(RAMP.x, RAMP.y, reach)
		if weight <= 0.0: continue
		# Ponta para trás (−z), atravessando a frente dos dedos fechados.
		var turn := Basis(Vector3.UP, -FOLD * weight * -side)
		bent[i] = pivot + turn * (bent[i] - pivot)
		if not normals.is_empty(): normals[i] = turn * normals[i]
	var result := shape.duplicate()
	result[Mesh.ARRAY_VERTEX] = bent
	if not normals.is_empty(): result[Mesh.ARRAY_NORMAL] = normals
	return result
