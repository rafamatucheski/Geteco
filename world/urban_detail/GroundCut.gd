extends RefCounted
## Recorte de pisos para manter uma camada só de chão no porto (2026-10-13). Cada piso de baixo perde a
## área que um piso de cima já cobre; quem está em cima não muda. Medido antes: média de 2,23 camadas
## de chão no Harbor, com 26 mil m² em 6 ou mais (tests/measure/measure_harbor_ground_layers.gd).

## Polígono que ficaria inteiro dentro da peça vira buraco, e triangular um buraco o preenche de novo.
## Nesse caso a peça é dividida ao meio (até MAX_SPLIT vezes) até o recorte encostar na borda.
const MAX_SPLIT := 6
## Interruptor para comparar antes/depois e desligar o recorte sem mexer em arquivos:
## `GETECO_GROUND_STACK=1` volta ao chão empilhado (todas as camadas inteiras).
static var enabled := OS.get_environment("GETECO_GROUND_STACK").is_empty()
const MIN_PIECE := 0.05
## Polígonos que triangulate_polygon não conseguiu triangular (diagnóstico da medição).
static var failed_triangulations := 0
static var failed_area := 0.0

static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

## Recortes do Godot só funcionam com as duas entradas no mesmo sentido; peças recortadas ao chunk por
## intersect_polygons podem sair no sentido horário e o clip_polygons seguinte devolvia vazio (faixas
## finas de meio-fio sumiam). Tudo entra no sentido anti-horário.
static func counter_clockwise(points: PackedVector2Array) -> PackedVector2Array:
	if not Geometry2D.is_polygon_clockwise(points): return points
	var reversed := points.duplicate()
	reversed.reverse()
	return reversed

static func bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points: result = result.expand(point)
	return result

## Peças de `pieces` que nenhum polígono de `cover` alcança. Mantém a orientação anti-horária.
static func subtract(pieces: Array[PackedVector2Array], cover: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if cover.is_empty() or not enabled: return pieces
	var oriented: Array[PackedVector2Array] = []
	var cover_bounds: Array[Rect2] = []
	for polygon in cover:
		if polygon.size() < 3: continue
		oriented.append(counter_clockwise(polygon))
		cover_bounds.append(bounds(polygon))
	var result: Array[PackedVector2Array] = []
	for piece in pieces:
		if piece.size() >= 3: _subtract_piece(counter_clockwise(piece), oriented, cover_bounds, 0, result)
	return result

static func _subtract_piece(piece: PackedVector2Array, cover: Array[PackedVector2Array], cover_bounds: Array[Rect2], depth: int, result: Array[PackedVector2Array]) -> void:
	var piece_bounds := bounds(piece)
	var remaining: Array[PackedVector2Array] = [piece]
	for index in cover.size():
		if not piece_bounds.intersects(cover_bounds[index], true): continue
		var next: Array[PackedVector2Array] = []
		for part in remaining:
			for cut in Geometry2D.clip_polygons(part, cover[index]):
				if Geometry2D.is_polygon_clockwise(cut):
					# Buraco: dividir a peça original e recomeçar cada metade.
					if depth < MAX_SPLIT and maxf(piece_bounds.size.x, piece_bounds.size.y) > MIN_PIECE * 2.0:
						for half in _halves(piece, piece_bounds): _subtract_piece(half, cover, cover_bounds, depth + 1, result)
					else:
						result.append(piece)
					return
				if cut.size() >= 3: next.append(cut)
		remaining = next
		if remaining.is_empty(): return
	result.append_array(remaining)

static func _halves(piece: PackedVector2Array, piece_bounds: Rect2) -> Array[PackedVector2Array]:
	var halves: Array[PackedVector2Array] = []
	var first := piece_bounds
	var second := piece_bounds
	if piece_bounds.size.x >= piece_bounds.size.y:
		first.size.x *= 0.5
		second.position.x += first.size.x
		second.size.x -= first.size.x
	else:
		first.size.y *= 0.5
		second.position.y += first.size.y
		second.size.y -= first.size.y
	for side in [first, second]:
		for part in Geometry2D.intersect_polygons(piece, rect_polygon(side.grow(0.0001))):
			if part.size() >= 3 and not Geometry2D.is_polygon_clockwise(part): halves.append(part)
	return halves

## Malha plana em `y` com normais para cima e UV de mundo dividido por `uv_scale`.
static func flat_mesh(polygons: Array[PackedVector2Array], y: float, uv_scale: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for polygon in polygons:
		var triangles := Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			failed_triangulations += 1
			failed_area += bounds(polygon).get_area()
			continue
		var offset := vertices.size()
		for point in polygon:
			vertices.append(Vector3(point.x, y, point.y))
			normals.append(Vector3.UP)
			uvs.append(point / uv_scale)
		for index in triangles: indices.append(offset + index)
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
