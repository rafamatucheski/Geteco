extends RefCounted
## Extensão rural local. O NativeRegion é dono de apoio/margem/streaming; o runtime
## do local é dono dos props de pesca e dos pescadores. As coordenadas são metros do Harbor.
const LOCATION := preload("res://runtime/FishingLocation.gd")
const ROAD_ID := "sereno_woodland_access"
const EXTENT := Rect2(-585,-128,155,203)
const LAND := [Vector2(-430,-122),Vector2(-465,-128),Vector2(-508,-124),
	Vector2(-546,-109),Vector2(-571,-83),Vector2(-585,-50),Vector2(-584,-10),
	Vector2(-573,23),Vector2(-551,51),Vector2(-520,69),Vector2(-484,75),
	Vector2(-452,63),Vector2(-430,45)]

static func outline() -> PackedVector2Array:
	return PackedVector2Array(LAND)

static func extra_surfaces() -> Array[PackedVector2Array]:
	return [outline()] if LOCATION.enabled() else []

static func road_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in LOCATION.ROAD_POINTS: result.append(Vector3(point.x,0,point.y))
	return result

static func on_extension(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,outline())

static func edge_distance(point: Vector2) -> float:
	var distance := INF
	for index in LAND.size():
		distance = minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,LAND[index],LAND[(index+1)%LAND.size()])))
	return distance

static func tree_available(point: Vector2) -> bool:
	# A margem inteira, as silhuetas de arremesso e a câmera sul do jogo ficam livres.
	return on_extension(point) and edge_distance(point)>5.4 and not LOCATION.GROUNDS.grow(10).has_point(point) \
		and LOCATION.road_distance(point)>LOCATION.ROAD_WIDTH*.5+5.0

static func clipped_land(rect: Rect2) -> Array[PackedVector2Array]:
	if not LOCATION.enabled() or not EXTENT.intersects(rect): return []
	return Geometry2D.intersect_polygons(outline(),PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]))
