extends RefCounted
## Configuration-space search: two actual medic bodies plus the projected cot.
## Translation and rotation are swept separately; no sliding/teleport correction.
const CELL := 12.0
const TURN := PI / 8.0
const MAX_CELLS := 1800
const SLICE_USEC := 700
const HANDLE := 25.0
var path: Array[Vector3] = []
var failed := false
var searching := false
var expansions := 0
var replans := 0
var _origin := Vector3.ZERO
var _goal := Vector3.INF
var _open: Array[Vector3i] = []
var _cost := {}
var _parent := {}
var _closed := {}
var _retry := 0.0
var _cot: CharacterBody2D
var _crew: Array = []
var _excluded: Array[RID] = []
var _space: PhysicsDirectSpaceState2D

func configure(cot: CharacterBody2D, medics: Array) -> void:
	_cot = cot
	_crew = medics

func reset() -> void:
	path.clear()
	searching = false
	failed = false
	_goal = Vector3.INF
	_retry = 0.0
	replans += 1

func _refresh_space() -> void:
	_space = _cot.get_world_2d().direct_space_state
	_excluded.assign([_cot.get_rid()])
	for medic in _crew: _excluded.append(medic.get_rid())
	for exception in _cot.get_collision_exceptions():
		if is_instance_valid(exception): _excluded.append(exception.get_rid())

func pose() -> Vector3:
	return Vector3(_cot.global_position.x, _cot.global_position.y, _cot.heading)

func handles(at: Vector3, index: int) -> Vector2:
	return Vector2(at.x, at.y) + Vector2.from_angle(at.z) * (HANDLE if index == 0 else -HANDLE)

func _polygons(at: Vector3, team: bool) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = [_cot.floor_polygon(at.z)]
	if team:
		for i in _crew.size():
			# Circumscribe the actual capsule, not its rectangle: a rectangular
			# corner can overlap a pole even when the medic has clear contact.
			var shape: CollisionShape2D = _crew[i].collision_shape
			var rect := shape.shape.get_rect()
			var offset := handles(at, i) - Vector2(at.x, at.y)
			var points := PackedVector2Array()
			if shape.shape is CapsuleShape2D:
				var capsule: CapsuleShape2D = shape.shape
				for vertex in 24:
					var p := Vector2.from_angle(vertex*TAU/24)*(capsule.radius/cos(PI/24))
					p.y += signf(p.y)*(capsule.height*.5-capsule.radius)
					points.append(offset + shape.transform*p)
			else:
				for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
					points.append(offset + shape.transform * p)
			polygons.append(points)
	return polygons

func clear_motion(from: Vector3, to: Vector3, team := true) -> bool:
	_refresh_space()
	var angle := angle_difference(from.z, to.z)
	# Convex hull between successive orientations encloses every corner arc
	# with a sagitta allowance. cast_motion covers all translation, even large dt.
	var count := maxi(1, ceili(absf(angle) / .08))
	for step in count:
		var a := from.lerp(to, float(step) / count)
		var b := from.lerp(to, float(step+1) / count)
		a.z = from.z + angle * float(step) / count
		b.z = from.z + angle * float(step+1) / count
		var start_polys := _polygons(a, team)
		var end_polys := _polygons(b, team)
		for i in start_polys.size():
			var vertices := start_polys[i].duplicate()
			vertices.append_array(end_polys[i])
			var shape := ConvexPolygonShape2D.new()
			shape.points = Geometry2D.convex_hull(vertices)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform.origin = Vector2(a.x, a.y)
			# Plan each body with the mask used by its physical movement. Medics
			# also collide with people; ignoring that layer made the search keep
			# offering a straight step that test_move could never execute.
			query.collision_mask = _cot.collision_mask if i == 0 else _crew[i-1].collision_mask
			query.exclude = _excluded
			var contact_margin := .005 if _distance(from,pose()) < .001 else .12
			query.margin = contact_margin + 34.0 * (1.0-cos(absf(angle)/count*.5))
			if not _space.intersect_shape(query, 1).is_empty(): return false
			query.motion = Vector2(b.x-a.x,b.y-a.y)
			if not query.motion.is_zero_approx() and _space.cast_motion(query)[0] < 1.0: return false
	return true

func next_pose(goal: Vector2, heading: float, delta: float, speed: float) -> Vector3:
	var at := pose()
	var end := Vector3(goal.x, goal.y, heading if is_finite(heading) else at.z)
	_retry = maxf(0, _retry-delta)
	if Vector2(_goal.x,_goal.y).distance_to(goal) > 2 or (is_finite(heading) and absf(angle_difference(_goal.z,heading)) > .02):
		reset()
		_goal = end
	# A cot can roll sideways/backwards while staying in the same formation.
	# Near a pole this is safer than insisting on a turn in a narrow gap.
	if path.is_empty() and not searching and _retry <= 0:
		if not clear_motion(end,end):
			failed = true
			_retry = 1.0
		elif clear_motion(at,end):
			path.append(end)
		else:
			_begin(at,end)
	if searching: _expand()
	while not path.is_empty() and _distance(at,path[0]) < .08: path.pop_front()
	if path.is_empty(): return at
	var target := path[0]
	var linear := Vector2(target.x-at.x,target.y-at.y).length()
	var angular := absf(angle_difference(at.z,target.z))
	var duration := maxf(linear/speed, angular/1.0)
	var fraction := minf(1, delta/maxf(duration,.00001))
	var result := at.lerp(target,fraction)
	result.z = at.z + angle_difference(at.z,target.z)*fraction
	if not clear_motion(at,result):
		reset()
		_retry = .25
		return at
	return result

func _distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.y-b.y).length()+absf(angle_difference(a.z,b.z))*HANDLE

func _begin(at: Vector3, end: Vector3) -> void:
	_origin = at
	_goal = end
	_open.assign([Vector3i.ZERO])
	_cost = {Vector3i.ZERO:0.0}
	_parent.clear()
	_closed.clear()
	expansions = 0
	searching = true
	failed = false

func _at(cell: Vector3i) -> Vector3:
	return _origin + Vector3(cell.x*CELL,cell.y*CELL,cell.z*TURN)

func _expand() -> void:
	var start := Time.get_ticks_usec()
	while not _open.is_empty() and expansions < MAX_CELLS:
		if Time.get_ticks_usec()-start > SLICE_USEC: return
		var best := 0
		var score := INF
		for i in _open.size():
			var value: float = _cost[_open[i]] + _distance(_at(_open[i]),_goal)*1.8
			if value < score:
				score = value
				best = i
		var cell := _open[best]
		_open.remove_at(best)
		_closed[cell] = true
		expansions += 1
		var here := _at(cell)
		if cell != Vector3i.ZERO and clear_motion(here,_goal):
			path.assign([_goal])
			while cell != Vector3i.ZERO:
				path.push_front(_at(cell))
				cell = _parent[cell]
			searching = false
			return
		for offset in [Vector3i(1,0,0),Vector3i(-1,0,0),Vector3i(0,1,0),Vector3i(0,-1,0),Vector3i(1,1,0),Vector3i(-1,1,0),Vector3i(1,-1,0),Vector3i(-1,-1,0),Vector3i(0,0,1),Vector3i(0,0,-1)]:
			var next: Vector3i = cell + offset
			next.z = posmod(next.z+8,16)-8
			if absi(next.x)>32 or absi(next.y)>32 or _closed.has(next): continue
			var cost: float = _cost[cell] + _distance(here,_at(next))
			if _cost.has(next) and _cost[next] <= cost: continue
			if not clear_motion(here,_at(next)): continue
			_cost[next] = cost
			_parent[next] = cell
			if not _open.has(next): _open.append(next)
	searching = false
	failed = true
	_retry = 1.0
