extends RefCounted
## Read-only navigation over the existing directed road graph. No physics queries,
## no invented cross-block links, and no second O(n²) road-intersection builder.
var graph := AStar3D.new()
var signature := ""
var points := PackedVector2Array()
var _last_start := Vector2.INF
var _last_goal := Vector2.INF
var _last_driving := false

func update(routes: RefCounted, revision: String, start: Vector3, goal: Vector3, driving: bool, facing: Vector3) -> bool:
	var key := "%s:%d" % [revision, routes.vertices.size()]
	var changed := signature != key
	if changed:
		signature = key
		graph.clear()
		for i in routes.vertices.size(): graph.add_point(i, routes.vertices[i])
		for from in routes.edges:
			for edge in routes.edges[from]: graph.connect_points(from, edge.to, false)
	var start_2d := Vector2(start.x, start.z)
	var goal_2d := Vector2(goal.x, goal.z)
	if not changed and driving == _last_driving and start_2d.distance_to(_last_start) < 6.0 and goal_2d.distance_to(_last_goal) < .5:
		return false
	_last_start = start_2d
	_last_goal = goal_2d
	_last_driving = driving
	points.clear()
	var first := _nearest(routes, start, facing if driving else Vector3.ZERO)
	var last := _nearest(routes, goal, Vector3.ZERO)
	if first.is_empty() or last.is_empty(): return true
	# Outside the road network, keep a destination bearing rather than fake GPS.
	if first.distance > 18.0 or last.distance > 24.0: return true
	var best_cost := INF
	for departure in _directions(first):
		for arrival in _directions(last):
			var candidate := _path(departure, arrival)
			if candidate.size() < 2: continue
			var cost := 0.0
			for i in candidate.size()-1: cost += candidate[i].distance_to(candidate[i+1])
			var direction: Vector3 = routes.vertices[departure.to] - routes.vertices[departure.from]
			if driving and direction.normalized().dot(facing) < -.2: cost += 16.0
			if cost < best_cost:
				best_cost = cost
				points = candidate
	return true

func _directions(edge: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [edge]
	if graph.are_points_connected(edge.to, edge.from, false):
		result.append({"from": edge.to, "to": edge.from, "point": edge.point, "fraction": 1.0-edge.fraction})
	return result

func _path(first: Dictionary, last: Dictionary) -> PackedVector2Array:
	if first.from == last.from and first.to == last.to and first.fraction <= last.fraction:
		return PackedVector2Array([_xz(first.point), _xz(last.point)])
	var path := graph.get_point_path(first.to, last.from)
	if path.is_empty(): return PackedVector2Array()
	var result := PackedVector2Array([_xz(first.point)])
	for point in path:
		if result[-1].distance_squared_to(_xz(point)) > .01: result.append(_xz(point))
	if result[-1].distance_squared_to(_xz(last.point)) > .01: result.append(_xz(last.point))
	return result

func clear() -> void:
	points.clear()
	_last_goal = Vector2.INF

func _xz(point: Vector3) -> Vector2: return Vector2(point.x, point.z)

func _nearest(routes: RefCounted, point: Vector3, facing: Vector3) -> Dictionary:
	var result := {}
	var best := INF
	for from in routes.edges:
		for edge in routes.edges[from]:
			var a: Vector3 = routes.vertices[from]
			var b: Vector3 = routes.vertices[edge.to]
			var delta := b - a
			if delta.length_squared() < .01: continue
			var fraction := clampf((point-a).dot(delta)/delta.length_squared(), 0, 1)
			var closest := a + delta * fraction
			var distance := point.distance_to(closest)
			var penalty := 4.0 if not facing.is_zero_approx() and delta.normalized().dot(facing) < -.2 else 0.0
			if distance + penalty >= best: continue
			best = distance + penalty
			result = {"from": from, "to": edge.to, "point": closest, "fraction": fraction, "distance": distance}
	return result

func remaining(start: Vector2) -> PackedVector2Array:
	if points.size() < 2: return PackedVector2Array()
	var best := INF
	var index := 0
	var closest := points[0]
	for i in points.size()-1:
		var candidate := Geometry2D.get_closest_point_to_segment(start, points[i], points[i+1])
		var distance := candidate.distance_squared_to(start)
		if distance < best:
			best = distance
			index = i
			closest = candidate
	if best > 18.0 * 18.0: return PackedVector2Array()
	var result := PackedVector2Array([closest])
	for i in range(index+1, points.size()):
		if result[-1].distance_squared_to(points[i]) > .01: result.append(points[i])
	return result

static func instruction(path: PackedVector2Array, destination: Vector2) -> Dictionary:
	if path.size() < 2: return {}
	var distance := 0.0
	var turn_distance := -1.0
	var turn := "↑"
	for i in path.size()-1:
		distance += path[i].distance_to(path[i+1])
		if i+2 < path.size() and turn_distance < 0:
			var incoming := path[i+1]-path[i]
			var outgoing := path[i+2]-path[i+1]
			var angle := incoming.angle_to(outgoing)
			if absf(angle) > .55 and incoming.length() > .2:
				turn_distance = distance
				turn = "↱" if angle > 0 else "↰"
	return {"distance": distance + path[-1].distance_to(destination), "turn_distance": turn_distance, "turn": turn}
