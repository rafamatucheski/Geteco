extends RefCounted
## Forma do mundo orgânico (plano de 26/10/2026, etapa 0): contorno curvo de cada ilha e o tipo de costa
## em cada trecho (cais, praia, penhasco, pedra). Gerada por tools/world_shape/generate_world_shape.mjs a
## partir da maquete aprovada do mapa da tecla M. Só dados e consultas: nada no jogo lê isto ainda. Os
## contratos (tudo que é jogável fica em terra, as pontes passam sobre água) estão em
## tests/test_world_shape.gd; a prévia de cima sai de tools/world_shape/preview_world_shape.py.
const PATH := "res://world/shape/world_shape.json"
const KINDS := ["quay", "beach", "cliff", "rock"]
static var _islands: Array[Dictionary] = []

## [{id, polygon: PackedVector2Array (x, z), bounds: Rect2, coast: [[índice inicial, tipo], ...]}]
static func islands() -> Array[Dictionary]:
	if not _islands.is_empty(): return _islands
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary: return _islands
	for row in data.get("islands", []):
		var flat: Array = row.points
		var polygon := PackedVector2Array()
		for i in range(0, flat.size(), 2): polygon.append(Vector2(float(flat[i]), float(flat[i + 1])))
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon: bounds = bounds.expand(point)
		_islands.append({"id": str(row.id), "polygon": polygon, "bounds": bounds, "coast": row.coast})
	return _islands

## Id da ilha que contém o ponto, ou "" no mar.
static func island_at(point: Vector2) -> String:
	for island in islands():
		if (island.bounds as Rect2).has_point(point) and Geometry2D.is_point_in_polygon(point, island.polygon): return island.id
	return ""

static func is_land(point: Vector2) -> bool:
	return not island_at(point).is_empty()

## Distância até a costa mais próxima: positiva em terra, negativa no mar.
static func signed_distance(point: Vector2) -> float:
	var nearest := INF
	for island in islands():
		var polygon: PackedVector2Array = island.polygon
		if not (island.bounds as Rect2).grow(minf(nearest, 4000.0)).has_point(point): continue
		for i in polygon.size():
			nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])))
	return nearest if is_land(point) else -nearest

## Tipo de costa do trecho mais próximo do ponto.
static func coast_kind(point: Vector2) -> String:
	var best := INF
	var kind := ""
	for island in islands():
		var polygon: PackedVector2Array = island.polygon
		for i in polygon.size():
			var d := point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()]))
			if d < best:
				best = d
				kind = kind_at(island, i)
	return kind

## Tipo de costa do vértice `index` (a lista guarda só onde o tipo muda).
static func kind_at(island: Dictionary, index: int) -> String:
	var kind := ""
	for run in island.coast:
		if int(run[0]) > index: break
		kind = str(run[1])
	return kind
