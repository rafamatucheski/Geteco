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
	return subtract_exact(pieces,cover)

## Mandatory ownership clipping, also used by water where the diagnostic
## ground-stack switch must never put the ocean back under dry land.
static func subtract_exact(pieces: Array[PackedVector2Array], cover: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if cover.is_empty(): return pieces
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
			var part_bounds := bounds(part)
			if not part_bounds.intersects(cover_bounds[index],true):
				next.append(part)
				continue
			var cuts := Geometry2D.clip_polygons(part, cover[index])
			var hole := PackedVector2Array()
			for cut in cuts:
				if Geometry2D.is_polygon_clockwise(cut):
					hole = cut
					break
			if hole.is_empty():
				for cut in cuts:
					if cut.size() >= 3: next.append(cut)
				continue
			# Only the current remainder and current cutter need reopening.
			# Restarting every cover on the original polygon grew exponentially
			# in planted courts containing many enclosed paths/corner discs.
			var single_cover: Array[PackedVector2Array] = [cover[index]]
			var single_bounds: Array[Rect2] = [cover_bounds[index]]
			if depth < MAX_SPLIT and maxf(part_bounds.size.x,part_bounds.size.y) > MIN_PIECE*2.0:
				for half in _halves(part,part_bounds,bounds(hole).get_center()):
					_subtract_piece(half,single_cover,single_bounds,depth+1,next)
			else:
				next.append_array(_convex_difference(part,single_cover,single_bounds))
		remaining = next
		if remaining.is_empty(): return
	result.append_array(remaining)

static func _halves(piece: PackedVector2Array, piece_bounds: Rect2, split_at: Vector2) -> Array[PackedVector2Array]:
	var halves: Array[PackedVector2Array] = []
	var first := piece_bounds
	var second := piece_bounds
	if piece_bounds.size.x >= piece_bounds.size.y:
		first.size.x = clampf(split_at.x-piece_bounds.position.x,0.00001,piece_bounds.size.x-0.00001)
		second.position.x += first.size.x
		second.size.x -= first.size.x
	else:
		first.size.y = clampf(split_at.y-piece_bounds.position.y,0.00001,piece_bounds.size.y-0.00001)
		second.position.y += first.size.y
		second.size.y -= first.size.y
	for side in [first, second]:
		for part in Geometry2D.intersect_polygons(piece, rect_polygon(side)):
			if part.size() >= 3 and not Geometry2D.is_polygon_clockwise(part): halves.append(part)
	return halves


static func _convex_difference(piece: PackedVector2Array, cover: Array[PackedVector2Array], cover_bounds: Array[Rect2]) -> Array[PackedVector2Array]:
	var remaining: Array[PackedVector2Array] = []
	var indices := Geometry2D.triangulate_polygon(piece)
	for index in range(0,indices.size(),3):
		remaining.append(counter_clockwise(PackedVector2Array([piece[indices[index]],piece[indices[index+1]],piece[indices[index+2]]])))
	var piece_bounds := bounds(piece)
	for cover_index in cover.size():
		if not piece_bounds.intersects(cover_bounds[cover_index],true): continue
		var polygon := cover[cover_index]
		var triangles := Geometry2D.triangulate_polygon(polygon)
		for index in range(0,triangles.size(),3):
			var triangle := counter_clockwise(PackedVector2Array([polygon[triangles[index]],polygon[triangles[index+1]],polygon[triangles[index+2]]]))
			var triangle_bounds := bounds(triangle)
			var next: Array[PackedVector2Array] = []
			for subject in remaining:
				if not bounds(subject).intersects(triangle_bounds,true):
					next.append(subject)
					continue
				var inside := subject
				for edge in 3:
					var outside := _half_plane(inside,triangle[edge],triangle[(edge+1)%3],false)
					if outside.size() >= 3: next.append(outside)
					inside = _half_plane(inside,triangle[edge],triangle[(edge+1)%3],true)
					if inside.size() < 3: break
			remaining = next
			if remaining.is_empty(): return remaining
	return remaining


static func _half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2, positive: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var previous_distance := (b-a).cross(previous-a)
	var previous_inside := previous_distance >= 0.0 if positive else previous_distance <= 0.0
	for point in polygon:
		var distance := (b-a).cross(point-a)
		var is_inside := distance >= 0.0 if positive else distance <= 0.0
		if is_inside != previous_inside:
			result.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
		if is_inside: result.append(point)
		previous = point
		previous_distance = distance
		previous_inside = is_inside
	# A vertex exactly on the plane can be emitted both as an intersection
	# and as an inside point. Remove only coincident neighbours before meshing.
	var clean := PackedVector2Array()
	for point in result:
		if clean.is_empty() or clean[-1].distance_squared_to(point) > 1e-12: clean.append(point)
	if clean.size() > 1 and clean[0].distance_squared_to(clean[-1]) <= 1e-12: clean.resize(clean.size()-1)
	# Boundary-only polygons belong to neither surface area. Retaining a
	# collinear fragment lets subsequent triangle cuts duplicate it repeatedly.
	var twice_area := 0.0
	for index in clean.size(): twice_area += clean[index].cross(clean[(index+1)%clean.size()])
	if absf(twice_area) < 1e-10: return PackedVector2Array()
	return clean

## Malha plana em `y` com normais para cima e UV de mundo dividido por `uv_scale`.
static func flat_mesh(polygons: Array[PackedVector2Array], y: float, uv_scale: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for polygon in polygons:
		var triangles := Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			# Global clipping followed by a local inverse transform can leave
			# micrometre-wide backtracking spikes. Remove only degenerate edges,
			# never replace a concave outline with its convex hull.
			polygon = _without_degenerate_edges(polygon)
			triangles = Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			failed_triangulations += 1
			failed_area += bounds(polygon).get_area()
			if OS.get_environment("GETECO_DIAG_GROUND_POLYGON") == "1":
				print("GROUND_TRIANGULATION_FAILURE polygon=",JSON.stringify(polygon)," y=",y," stack=",get_stack())
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


static func _without_degenerate_edges(polygon: PackedVector2Array) -> PackedVector2Array:
	var clean := polygon.duplicate()
	const EDGE_EPS := 0.00005
	var changed := true
	while changed and clean.size() > 3:
		changed = false
		for index in clean.size():
			var previous := clean[(index+clean.size()-1)%clean.size()]
			var point := clean[index]
			var after := clean[(index+1)%clean.size()]
			var axis := after-previous
			var distance := absf(axis.cross(point-previous))/maxf(axis.length(),EDGE_EPS)
			if point.distance_to(previous) <= EDGE_EPS or distance <= EDGE_EPS:
				clean.remove_at(index)
				changed = true
				break
	return clean
