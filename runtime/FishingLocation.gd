extends RefCounted
## Reserva externa compartilhada e destino de mapa, independentes dos scripts de cena.
const ANCHOR := Vector3(-500,0,-35)
const ENTRY := ANCHOR+Vector3(0,0,30)
const GROUNDS := Rect2(-538,-62,76,59)
const DRIVEWAY := Rect2(-504,-5,8,3)
# Checkpoints antigos continuam válidos na terra plana original. Deixa o local
# aposentado como campo em vez de gerar um tronco dentro de um pedestre/carro salvo.
const LEGACY_ANCHOR := Vector3(-175,0,-3)
const LEGACY_GROUNDS := Rect2(-213,-30,76,63)
const ROAD_WIDTH := 6.5
const ROAD_POINTS := [Vector2(-340,18),Vector2(-378,21),Vector2(-413,27),
	Vector2(-447,24),Vector2(-477,10),Vector2(-500,-5)]

static func enabled() -> bool:
	return not Engine.get_meta("fishing_baseline",false)

static func road_distance(point: Vector2) -> float:
	var closest := INF
	for index in ROAD_POINTS.size()-1:
		closest = minf(closest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,ROAD_POINTS[index],ROAD_POINTS[index+1])))
	return closest

static func reserved(point: Vector2, margin := 0.0) -> bool:
	if not enabled(): return false
	return GROUNDS.grow(margin).has_point(point) or DRIVEWAY.grow(margin).has_point(point) \
		or LEGACY_GROUNDS.grow(margin).has_point(point) or road_distance(point)<ROAD_WIDTH*.5+margin+.7
