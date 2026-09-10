extends RefCounted
## Desvio local com memória: conserva o caminho escolhido em vez de sortear
## uma direção a cada colisão. Só busca uma rota quando o trecho direto bloqueia.
const STEP := 24.0
const DIRECTIONS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
var path: Array[Vector2] = []
var destination := Vector2.INF
var retry := 0.0
var stuck_time := 0.0
var last_position := Vector2.INF
var search_budget := 192
var retry_delay := 1.0
var sight_timer := 0.0
var direct_clear := false
var service_goal := Vector2.INF
var service_origin := Vector2.INF
var service_retry := 0.0

func service_position(body: CharacterBody2D, target: Node2D, reach: float, delta: float) -> Vector2:
	service_retry -= delta
	if service_retry > 0.0 and service_origin.distance_to(target.global_position) < 12.0: return service_goal
	service_retry = 0.5
	service_origin = target.global_position
	service_goal = target.global_position
	var best := INF
	var footprint := CircleShape2D.new()
	footprint.radius = 9.0
	var occupancy := PhysicsShapeQueryParameters2D.new()
	occupancy.shape = footprint
	occupancy.collision_mask = 3
	occupancy.exclude = [body.get_rid()]
	# Escolher um posto com acesso ao alvo permite contornar uma parede mesmo
	# quando o socorrista já está perto dela, mas do lado errado.
	for i in 8:
		var point := target.global_position + Vector2.from_angle(float(i) * PI / 4.0) * reach
		occupancy.transform = Transform2D(0.0, point)
		if not body.get_world_2d().direct_space_state.intersect_shape(occupancy, 1).is_empty(): continue
		var query := PhysicsRayQueryParameters2D.create(point, target.global_position, 3, [body.get_rid()])
		query.hit_from_inside = true
		var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != target: continue
		var cost := body.global_position.distance_squared_to(point)
		if cost < best:
			best = cost
			service_goal = point
	return service_goal

func clear_segment(body: CharacterBody2D, start: Vector2, end: Vector2) -> bool:
	var excluded: Array[RID] = [body.get_rid()]
	for exception in body.get_collision_exceptions():
		if is_instance_valid(exception): excluded.append(exception.get_rid())
	var side := start.direction_to(end).orthogonal() * 9.0
	for offset in [Vector2.ZERO, side, -side]:
		var query := PhysicsRayQueryParameters2D.create(start + offset, end + offset, body.collision_mask & 3, excluded)
		query.hit_from_inside = true
		if not body.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): return false
	return true

func movement(body: CharacterBody2D, goal: Vector2, speed: float, delta: float) -> Vector2:
	retry = maxf(0.0, retry - delta)
	sight_timer -= delta
	if body.global_position.distance_to(last_position) < speed * delta * 0.15:
		stuck_time += delta
	else:
		stuck_time = 0.0
	last_position = body.global_position
	if goal.distance_to(destination) > 32.0:
		path.clear()
		retry = 0.0
		destination = goal
		sight_timer = 0.0
	if sight_timer <= 0.0:
		direct_clear = clear_segment(body, body.global_position, goal)
		sight_timer = 0.25
	if direct_clear:
		path.clear()
		return body.global_position.direction_to(goal) * minf(speed, body.global_position.distance_to(goal) / maxf(delta, 0.001))
	if stuck_time > 0.7:
		path.clear()
	while not path.is_empty() and body.global_position.distance_to(path[0]) < 7.0:
		path.pop_front()
	if path.is_empty() and retry <= 0.0:
		path = _plan(body, goal)
		retry = retry_delay
		stuck_time = 0.0
	if path.is_empty(): return Vector2.ZERO
	var next := path[0]
	var step := body.global_position.direction_to(next) * minf(speed * delta, body.global_position.distance_to(next))
	if not clear_segment(body, body.global_position, body.global_position + step):
		path.clear()
		return Vector2.ZERO
	return step / maxf(delta, 0.001)

func _plan(body: CharacterBody2D, goal: Vector2) -> Array[Vector2]:
	var origin := body.global_position
	var open: Array[Vector2i] = [Vector2i.ZERO]
	var costs := {Vector2i.ZERO: 0.0}
	var parents := {}
	var closed := {}
	# Busca limitada para não transformar uma ocorrência sem acesso em pico sem fim.
	for iteration in range(search_budget):
		if open.is_empty(): break
		var best := 0
		for i in range(1, open.size()):
			if float(costs[open[i]]) + (origin + Vector2(open[i]) * STEP).distance_to(goal) < float(costs[open[best]]) + (origin + Vector2(open[best]) * STEP).distance_to(goal): best = i
		var cell := open[best]
		open.remove_at(best)
		closed[cell] = true
		var point := origin + Vector2(cell) * STEP
		if cell != Vector2i.ZERO and clear_segment(body, point, goal):
			var result: Array[Vector2] = [goal]
			while cell != Vector2i.ZERO:
				result.push_front(origin + Vector2(cell) * STEP)
				cell = parents[cell]
			return result
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if closed.has(neighbor) or absi(neighbor.x) > 16 or absi(neighbor.y) > 16: continue
			var next := origin + Vector2(neighbor) * STEP
			var cost := float(costs[cell]) + point.distance_to(next)
			if costs.has(neighbor) and float(costs[neighbor]) <= cost: continue
			if not clear_segment(body, point, next): continue
			costs[neighbor] = cost
			parents[neighbor] = cell
			if not open.has(neighbor): open.append(neighbor)
	return []
