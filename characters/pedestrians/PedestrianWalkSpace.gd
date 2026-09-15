extends RefCounted
const CROSSING_HALF_WIDTH := 28.0
## Static road geometry is shared by a population; each walker selects nearby
## edges only when its authored leg changes. Physics still checks solid props.
var roads: Array[Dictionary] = []

func configure(network: Node2D, graph: Dictionary) -> void:
	for road in graph.roads:
		var points: PackedVector2Array = road.points
		for i in range(1, points.size()):
			var a := network.to_global(points[i - 1])
			var b := network.to_global(points[i])
			roads.append({"a": a, "b": b, "radius": float(road.width) * 0.5 + 11.5,
				"bounds": Rect2(a, Vector2.ZERO).expand(b).grow(float(road.width) * 0.5 + 44.0)})

func near_leg(a: Vector2, b: Vector2, width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(width)
	for road in roads:
		if not bounds.intersects(road.bounds): continue
		var axis: Vector2 = (road.b - road.a).normalized()
		var normal := axis.orthogonal()
		var side_a: float = (a - road.a).dot(normal)
		var side_b: float = (b - road.a).dot(normal)
		# Only an authored perpendicular crossing can enter the carriageway.
		if side_a * side_b < 0.0 and absf(a.direction_to(b).dot(axis)) < 0.3:
			result.append({"crossing": true})
			continue
		result.append(road)
	return result

static func allows(point: Vector2, nearby: Array[Dictionary], origin := Vector2.INF) -> bool:
	for road in nearby:
		if road.get("crossing", false): continue
		var closest := Geometry2D.get_closest_point_to_segment(point, road.a, road.b)
		var radius: float = road.radius
		# Existing spawns/physical pushes may straddle a kerb. Permit motion
		# back out, but never a step deeper into the carriageway.
		if origin.is_finite():
			var old_closest := Geometry2D.get_closest_point_to_segment(origin, road.a, road.b)
			radius = minf(radius, origin.distance_to(old_closest))
		if point.distance_squared_to(closest) + 0.0001 < radius * radius: return false
	return true
