extends RefCounted
## Desvio local com memÃƒÆ’Ã‚Â³ria: conserva o caminho escolhido em vez de sortear
## uma direÃƒÆ’Ã‚Â§ÃƒÆ’Ã‚Â£o a cada colisÃƒÆ’Ã‚Â£o. SÃƒÆ’Ã‚Â³ busca uma rota quando o trecho direto bloqueia.
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
var _search_origin := Vector2.INF
var _search_goal := Vector2.INF
var _open: Array[Vector2i] = []
var _costs := {}
var _parents := {}
var _closed := {}
var _search_pending := false
var _recovering_contact := false
const SEARCH_SLICE_USEC := 500
const SEARCH_FRAME_USEC := 1000
const SEARCH_SLICE_CELLS := 16
static var _work_frame := -1
static var _work_tree := 0
static var _work_usec := 0
static var _waiting: Array[WeakRef] = []
var _queued := false
var _requested_frame := -1
var _requested_msec := -1
var point_filter := Callable()
var grid_step := STEP
var preferred_side := Vector2.ZERO
var _stall_replan := 0.0
var _progress_point := Vector2.INF
var _progress_best := INF

func reset_progress() -> void:
	stuck_time = 0.0
	_stall_replan = 0.0
	_progress_point = Vector2.INF
	_progress_best = INF
	last_position = Vector2.INF

func repath() -> void:
	path.clear()
	_search_pending = false
	retry = 0.0
	sight_timer = 0.0
	direct_clear = false

func allows_point(point: Vector2) -> bool:
	return not point_filter.is_valid() or bool(point_filter.call(point))

func _begin_search_work(body: CharacterBody2D) -> bool:
	var frame := Engine.get_process_frames()
	var tree_id := body.get_tree().get_instance_id()
	if _work_tree != tree_id:
		_waiting.clear()
		_work_tree = tree_id
		_work_frame = -1
		_queued = false
	if _work_frame != frame:
		_work_frame = frame
		_work_usec = 0
	_requested_frame = frame
	_requested_msec = Time.get_ticks_msec()
	if not _queued:
		_waiting.append(weakref(self))
		_queued = true
	# A freed, suspended or no-longer-searching actor must not hold the queue.
	while not _waiting.is_empty():
		var candidate = _waiting[0].get_ref()
		# Pedestrians request at 30 Hz, not on every rendered frame. Expiring
		# after one render frame starved later walkers at 60+ FPS indefinitely.
		if candidate != null and candidate._search_pending and _requested_msec - candidate._requested_msec <= 500:
			break
		_waiting.pop_front()
		if candidate != null: candidate._queued = false
	if _work_usec >= SEARCH_FRAME_USEC or _waiting.is_empty() or _waiting[0].get_ref() != self:
		return false
	_waiting.pop_front()
	_queued = false
	return true

func service_position(body: CharacterBody2D, target: Node2D, reach: float, delta: float) -> Vector2:
	service_retry -= delta
	if service_retry > 0.0 and service_origin.distance_to(target.global_position) < 12.0: return service_goal
	service_retry = 0.5
	service_origin = target.global_position
	service_goal = target.global_position
	var best := INF
	var excluded: Array[RID] = [body.get_rid()]
	for exception in body.get_collision_exceptions():
		if is_instance_valid(exception): excluded.append(exception.get_rid())
	# Escolher um posto com acesso ao alvo permite contornar uma parede mesmo
	# quando o socorrista jÃƒÆ’Ã‚Â¡ estÃƒÆ’Ã‚Â¡ perto dela, mas do lado errado.
	for i in 8:
		var point := target.global_position + Vector2.from_angle(float(i) * PI / 4.0) * reach
		# The stretcher is wider than a medic. Use the actual footprint and its
		# collision exceptions, not a generic nine-pixel circle that selects
		# stations the moving body can never occupy next to an ambulance.
		if not clear_segment(body, point, point): continue
		var query := PhysicsRayQueryParameters2D.create(point, target.global_position, 3, excluded)
		query.hit_from_inside = true
		var hit := body.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != target: continue
		var cost := body.global_position.distance_squared_to(point)
		if cost < best:
			best = cost
			service_goal = point
	return service_goal

func clear_segment(body: CharacterBody2D, start: Vector2, end: Vector2) -> bool:
	return _clear_segment(body, start, end, _segment_queries(body))

func _segment_queries(body: CharacterBody2D) -> Array[PhysicsShapeQueryParameters2D]:
	var excluded: Array[RID] = [body.get_rid()]
	for exception in body.get_collision_exceptions():
		if is_instance_valid(exception): excluded.append(exception.get_rid())
	var queries: Array[PhysicsShapeQueryParameters2D] = []
	for child in body.get_children():
		if not child is CollisionShape2D or child.disabled or child.shape == null: continue
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = child.shape
		query.transform = child.global_transform
		query.collision_mask = body.collision_mask & 3
		query.exclude = excluded
		query.margin = body.safe_margin
		queries.append(query)
	return queries

func _clear_segment(body: CharacterBody2D, start: Vector2, end: Vector2, queries: Array[PhysicsShapeQueryParameters2D]) -> bool:
	if not allows_point(end) or not allows_point(start.lerp(end, 0.5)): return false
	# Queries are reused only within one synchronous expansion. Every physics
	# query still reads the live space; no occupancy result survives a call.
	var space := body.get_world_2d().direct_space_state
	for query in queries:
		var relative_pose := query.transform
		query.transform.origin += start - body.global_position
		query.motion = Vector2.ZERO
		var overlapping := not space.intersect_shape(query, 1).is_empty()
		query.transform = relative_pose
		if overlapping:
			# The engine leaves bodies inside their inflated safety margin after
			# contact. A graph that rejects that origin has no outgoing edges.
			# Only a real body's shallow contact may use physical recovery;
			# hypothetical graph positions and deep overlaps remain blocked.
			if start.distance_squared_to(body.global_position) > 0.0001: return false
			var recovery := KinematicCollision2D.new()
			if not body.test_move(body.global_transform, Vector2.ZERO, recovery, body.safe_margin, true): return false
			var correction := recovery.get_travel()
			if correction.length() > body.safe_margin * 2.0 + 0.1: return false
			if (end - start).dot(correction) < -0.0001: return false
			_recovering_contact = true
			return not body.test_move(body.global_transform, end - start, null, body.safe_margin, false)
		query.motion = end - start
		if query.motion.is_zero_approx(): continue
		query.transform.origin += start - body.global_position
		var travel := space.cast_motion(query)
		query.transform = relative_pose
		if travel[0] < 1.0: return false
	return true

func movement(body: CharacterBody2D, goal: Vector2, speed: float, delta: float) -> Vector2:
	retry = maxf(0.0, retry - delta)
	sight_timer -= delta
	# Measure progress towards the committed waypoint, not foot shuffling.
	# Search slices/retries never erase the time spent unable to advance.
	var progress_point := path[0] if not path.is_empty() else goal
	var remaining := body.global_position.distance_to(progress_point)
	if _progress_point != progress_point:
		_progress_point = progress_point
		_progress_best = remaining
	stuck_time += delta
	_stall_replan += delta
	if remaining < _progress_best - 3.0:
		_progress_best = remaining
		stuck_time = 0.0
		_stall_replan = 0.0
	last_position = body.global_position
	if goal.distance_to(destination) > 32.0:
		path.clear()
		_search_pending = false
		retry = 0.0
		destination = goal
		sight_timer = 0.0
	if sight_timer <= 0.0:
		direct_clear = clear_segment(body, body.global_position, goal)
		sight_timer = 0.25
	if direct_clear:
		path.clear()
		_search_pending = false
		return _bounded_motion(body, (goal - body.global_position).limit_length(speed * delta), delta)
	if _stall_replan > 1.2 and not path.is_empty():
		path.clear()
		_stall_replan = 0.0
	# A wide arrival radius cuts across the very obstacle the path avoided,
	# especially after refining a narrow passage to six/three-pixel cells.
	while not path.is_empty() and body.global_position.distance_to(path[0]) < minf(2.0, grid_step * 0.35):
		path.pop_front()
	if path.is_empty() and retry <= 0.0:
		path = _plan(body, goal)
		retry = 0.0 if _search_pending else retry_delay
		# Give a newly computed route its own opportunity to make progress.
		# The total stuck_time deliberately survives this path-local reset.
		if not path.is_empty(): _stall_replan = 0.0
	if path.is_empty(): return Vector2.ZERO
	var next := path[0]
	var step := body.global_position.direction_to(next) * minf(speed * delta, body.global_position.distance_to(next))
	if not clear_segment(body, body.global_position, body.global_position + step):
		path.clear()
		return Vector2.ZERO
	return _bounded_motion(body, step, delta)

func _bounded_motion(body: CharacterBody2D, step: Vector2, delta: float) -> Vector2:
	# move_and_slide will apply contact recovery itself. Reserve its displacement
	# from this frame's speed budget instead of moving/teleporting the actor here.
	if _recovering_contact or body.get_slide_collision_count() > 0:
		var recovery := KinematicCollision2D.new()
		_recovering_contact = body.test_move(body.global_transform, Vector2.ZERO, recovery, body.safe_margin, true)
		if _recovering_contact:
			step = step.limit_length(maxf(0.0, step.length() - recovery.get_travel().length()))
	return step / maxf(delta, 0.001)

func _plan(body: CharacterBody2D, goal: Vector2) -> Array[Vector2]:
	# Continue across frames instead of discarding every small crowd search.
	if not _search_pending or _search_goal.distance_to(goal) > 8.0 or _search_origin.distance_to(body.global_position) > 7.0:
		_search_origin = body.global_position
		_search_goal = goal
		_open = [Vector2i.ZERO]
		_costs = {Vector2i.ZERO: 0.0}
		_parents = {}
		_closed = {}
		_search_pending = true
	if not _begin_search_work(body): return []
	var started := Time.get_ticks_usec()
	var result := _expand_plan(body, goal, started)
	_work_usec += Time.get_ticks_usec() - started
	return result

func _expand_plan(body: CharacterBody2D, goal: Vector2, started: int) -> Array[Vector2]:
	var origin := _search_origin
	var open := _open
	var costs := _costs
	var parents := _parents
	var closed := _closed
	var queries := _segment_queries(body)
	# Busca limitada para nÃƒÆ’Ã‚Â£o transformar uma ocorrÃƒÆ’Ã‚Âªncia sem acesso em pico sem fim.
	for iteration in range(mini(search_budget, SEARCH_SLICE_CELLS)):
		# Finish an edge expansion atomically, then yield the remaining search.
		# The shared budget also covers extra physics ticks in a slow frame.
		if iteration > 0 and Time.get_ticks_usec() - started >= SEARCH_SLICE_USEC: break
		if open.is_empty(): break
		var best := 0
		var best_score := _search_score(open[0], origin, goal, costs)
		for i in range(1, open.size()):
			var score := _search_score(open[i], origin, goal, costs)
			if score < best_score:
				best = i
				best_score = score
		var cell := open[best]
		open.remove_at(best)
		closed[cell] = true
		var point := origin + Vector2(cell) * grid_step
		if cell != Vector2i.ZERO and _clear_segment(body, point, goal, queries):
			_search_pending = false
			var result: Array[Vector2] = [goal]
			while cell != Vector2i.ZERO:
				result.push_front(origin + Vector2(cell) * grid_step)
				cell = parents[cell]
			return result
		for direction in DIRECTIONS:
			var neighbor: Vector2i = cell + direction
			if closed.has(neighbor) or absi(neighbor.x) > 16 or absi(neighbor.y) > 16: continue
			var next := origin + Vector2(neighbor) * grid_step
			var cost := float(costs[cell]) + point.distance_to(next)
			if costs.has(neighbor) and float(costs[neighbor]) <= cost: continue
			if not _clear_segment(body, point, next, queries): continue
			costs[neighbor] = cost
			parents[neighbor] = cell
			if not open.has(neighbor): open.append(neighbor)
	_search_pending = not open.is_empty()
	if not _search_pending and not preferred_side.is_zero_approx() and grid_step > 3.0:
		# A body's offset relative to the kerb can put a narrow free lane
		# between all grid columns. Refine only after exhausting the coarse grid.
		grid_step *= 0.5
		_search_origin = Vector2.INF
		_search_pending = true
	return []

func _search_score(cell: Vector2i, origin: Vector2, goal: Vector2, costs: Dictionary) -> float:
	var offset := Vector2(cell) * grid_step
	return float(costs[cell]) + (origin + offset).distance_to(goal) + maxf(0.0, -offset.dot(preferred_side)) * 0.2
