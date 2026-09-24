extends RefCounted
## Bacia dos lagos de Mountain: quanto o terreno afunda sob cada lago.
##
## O lago alpino era um adesivo plano pintado em cima de chão plano e parecia mal
## encaixado no terreno (relato do jogador em 2026-09-24). Aqui o terreno desce
## DEPTH dentro do contorno da margem da V1, com rampa de RAMP metros a partir da
## borda; NativeLake põe a água abaixo do nível do chão, dentro da bacia.
## Só o lago alpino por enquanto: o glacial ("secret") tem ilha, acampamento e
## barco apoiados na superfície plana e precisa de outro ajuste.

const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const SCALE := 1.0 / 16.0
# Funda e gradual: a linha d'água nasce onde o terreno cruza o nível da água, e o
# shader do lago lê a profundidade real para clarear o raso e escurecer o fundo.
# Fundo acima do mar de Harbor (HarborOcean.WATER_Y = -0,94), que existe por baixo
# de Mountain inteira: mais fundo que isso, o lago mostrava a superfície do mar.
const DEPTH := 0.85
const RAMP := 8.0
## Mesma âncora de NativeRegion (lake "alpine" em (7000,0), coordenada V1 de Mountain).
const ALPINE_ANCHOR := Vector2(7000, 0)

static var _shore := PackedVector2Array()
static var _bounds := Rect2()
static var _loaded := false
static var _roads: Array = []
## Mesma folga de NativeLake.ROAD_CLEARANCE: bacia e água recortadas iguais, senão
## sobra buraco sem água entre o lago e a pista.
const ROAD_CLEARANCE := 3.5

## Chamado por MountainTerrain3D.configure com as estradas da região.
static func configure(roads: Array) -> void:
	_roads = roads
	_loaded = false
	_shore = PackedVector2Array()

static func _load() -> void:
	_loaded = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalLakeData.json"))["alpine"]
	var origin: Vector3 = CATALOG._at(ALPINE_ANCHOR, "mountain")
	for pair in data.lake_shore:
		_shore.append((Vector2(pair[0], pair[1]) + Vector2(-7000, 0)) * SCALE + Vector2(origin.x, origin.z))
	_shore = _smooth(_clear_roads(_shore))
	if _shore.size() < 3: return
	_bounds = Rect2(_shore[0], Vector2.ZERO)
	for point in _shore: _bounds = _bounds.expand(point)

## Profundidade (>= 0) a subtrair da altura do terreno em `point` (XZ de mundo).
static func depth_at(point: Vector2) -> float:
	if not _loaded: _load()
	if _shore.size() < 3 or not _bounds.has_point(point): return 0.0
	if not Geometry2D.is_point_in_polygon(point, _shore): return 0.0
	var edge := INF
	for i in _shore.size():
		edge = minf(edge, point.distance_to(Geometry2D.get_closest_point_to_segment(point, _shore[i], _shore[(i + 1) % _shore.size()])))
	return DEPTH * smoothstep(0.0, RAMP, edge)

## Mesmo arredondamento de NativeLake._smooth, para bacia e água coincidirem.
static func _smooth(polygon: PackedVector2Array, iterations := 2) -> PackedVector2Array:
	var result := polygon
	for n in iterations:
		var next := PackedVector2Array()
		for i in result.size():
			var a := result[i]
			var b := result[(i + 1) % result.size()]
			next.append(a.lerp(b, .25))
			next.append(a.lerp(b, .75))
		result = next
	return result

static func _clear_roads(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := polygon
	var center := Vector2.ZERO
	for point in polygon: center += point / polygon.size()
	for road in _roads:
		var points: PackedVector3Array = road.points
		var half: float = float(road.width) * .5 + ROAD_CLEARANCE
		for i in range(points.size() - 1):
			if result.size() < 3: return result
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			if Geometry2D.get_closest_point_to_segment(center, a, b).distance_to(center) > 120.0: continue
			var along := (b - a).normalized() * half
			var side := along.orthogonal()
			var pieces := Geometry2D.clip_polygons(result, PackedVector2Array([a - along - side, b + along - side, b + along + side, a - along + side]))
			var best := PackedVector2Array()
			var best_area := 0.0
			for piece in pieces:
				var area := 0.0
				for k in piece.size(): area += piece[k].cross(piece[(k + 1) % piece.size()])
				if absf(area) > best_area:
					best_area = absf(area)
					best = piece
			result = best
	return result
