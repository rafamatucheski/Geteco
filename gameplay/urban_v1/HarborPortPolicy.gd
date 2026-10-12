extends RefCounted
## Limites entre a via pública e a área de operação do Porto Sul.
const LAYOUT := preload("res://world/regions/OriginalSouthPortLayout.gd")
const SCALE := 16.0

static func is_private_road(road: Dictionary) -> bool:
	var id := str(road.get("id", ""))
	# Workshop/service access and Neco's dead-end yard are player destinations,
	# not through routes for the ambient population.
	return id.begins_with("south_port_") or id in ["salvage_access", "westgate_service_lane"]

static func ambient_roads(roads: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for road in roads:
		if not road is Dictionary or is_private_road(road): continue
		var points: PackedVector3Array = road.get("points", PackedVector3Array())
		var width := float(road.get("width", 7.5))
		var enters_port := false
		for index in range(points.size() - 1):
			if segment_enters_private_area(points[index], points[index + 1], width * 0.5 + 0.85):
				enters_port = true
				break
		if not enters_port: result.append(road)
	return result

static func contains_private_area(point: Vector3) -> bool:
	if not point.is_finite(): return false
	var authored := Vector2(point.x * SCALE, point.z * SCALE)
	if LAYOUT.LAND.has_point(authored) or LAYOUT.WALKWAY.has_point(authored): return true
	if Geometry2D.is_point_in_polygon(authored, LAYOUT.ship_hull()): return true
	for pier in LAYOUT.PIERS:
		if pier.has_point(authored): return true
	return false

static func segment_enters_private_area(start: Vector3, finish: Vector3, margin: float = 0.0) -> bool:
	var direction := finish - start
	direction.y = 0.0
	var length := direction.length()
	var side := direction.normalized().cross(Vector3.UP) * margin if length > 0.001 else Vector3.ZERO
	var steps := maxi(1, ceili(length / 1.0))
	for index in range(steps + 1):
		var point := start.lerp(finish, float(index) / float(steps))
		if contains_private_area(point): return true
		if margin > 0.0 and (contains_private_area(point + side) or contains_private_area(point - side)): return true
	return false

static func route_is_ambient_safe(route: Curve3D) -> bool:
	if route == null or route.get_baked_length() < 0.1: return false
	var previous := route.sample_baked(0.0, true)
	if contains_private_area(previous): return false
	var steps := maxi(1, ceili(route.get_baked_length() / 1.0))
	for index in range(1, steps + 1):
		var point := route.sample_baked(route.get_baked_length() * float(index) / float(steps), true)
		if segment_enters_private_area(previous, point): return false
		previous = point
	return true
