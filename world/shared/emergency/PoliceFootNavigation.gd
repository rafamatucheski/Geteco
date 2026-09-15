extends "res://ResponderNavigation.gd"
## Follow pedestrian passage corners before asking the bounded local planner
## to avoid cars/props. Never treat the straight line through a block as a road.
var passage: Array[Vector2] = []
var passage_goal := Vector2.INF
var passage_provider: WeakRef
var passage_retry := 0.0

func _init() -> void:
	grid_step = 12.0

func movement(body: CharacterBody2D, goal: Vector2, speed: float, delta: float) -> Vector2:
	passage_retry -= delta
	var removed := passage_provider != null and not is_instance_valid(passage_provider.get_ref())
	if removed or goal.distance_to(passage_goal) > 24.0 or (passage.is_empty() and passage_retry <= 0.0):
		passage = _passage_route(body, goal)
		passage_goal = goal
		passage_retry = 1.0
	while not passage.is_empty() and body.global_position.distance_to(passage[0]) < 3.0:
		passage.pop_front()
	return super.movement(body, passage[0] if not passage.is_empty() else goal, speed, delta)

func _passage_route(body: CharacterBody2D, goal: Vector2) -> Array[Vector2]:
	passage_provider = null
	var best_route: Array[Vector2] = []
	var best_cost := INF
	for provider: Node2D in body.get_tree().get_nodes_in_group("pedestrian_passages"):
		for definition: Dictionary in provider.get_alley_definitions():
			var points := PackedVector2Array()
			for point: Vector2 in definition.points: points.append(provider.to_global(point))
			if points.size() < 2: continue
			var from := _project(points, body.global_position)
			var to := _project(points, goal)
			var reach := float(definition.width) * 0.5 + 6.0
			var inside_from: bool = from.distance <= reach
			var inside_to: bool = to.distance <= reach
			if not inside_from and not inside_to: continue
			# Enter/leave at a sidewalk endpoint when outside the corridor.
			var starts: Array = [from] if inside_from else [_endpoint(points, false), _endpoint(points, true)]
			var ends: Array = [to] if inside_to else [_endpoint(points, false), _endpoint(points, true)]
			for start: Dictionary in starts:
				for finish: Dictionary in ends:
					var cost := body.global_position.distance_to(start.point) + absf(finish.along - start.along) + goal.distance_to(finish.point)
					if not clear_segment(body, body.global_position, start.point): cost += 300.0
					if cost >= best_cost: continue
					best_cost = cost
					best_route = [start.point]
					var forward: bool = finish.along >= start.along
					var along := 0.0
					var corners: Array[Vector2] = []
					for i in points.size():
						if i > 0: along += points[i - 1].distance_to(points[i])
						if along > minf(start.along, finish.along) and along < maxf(start.along, finish.along): corners.append(points[i])
					if not forward: corners.reverse()
					best_route.append_array(corners)
					best_route.append(finish.point)
					best_route.append(goal)
					passage_provider = weakref(provider)
	return best_route

func _project(points: PackedVector2Array, point: Vector2) -> Dictionary:
	var result := {"point": points[0], "along": 0.0, "distance": INF}
	var along := 0.0
	for i in range(points.size() - 1):
		var closest := Geometry2D.get_closest_point_to_segment(point, points[i], points[i + 1])
		var distance := point.distance_to(closest)
		if distance < result.distance:
			result = {"point": closest, "along": along + points[i].distance_to(closest), "distance": distance}
		along += points[i].distance_to(points[i + 1])
	return result

func _endpoint(points: PackedVector2Array, last: bool) -> Dictionary:
	var along := 0.0
	if last:
		for i in range(points.size() - 1): along += points[i].distance_to(points[i + 1])
	return {"point": points[-1] if last else points[0], "along": along, "distance": 0.0}
