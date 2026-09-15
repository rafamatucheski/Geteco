extends RefCounted
## Shared longitudinal rules. Positions and hulls are read live: a render-frame
## PathFollow move must not wait for the physics server to update occupancy.
const STANDSTILL_GAP := 14.0
const TIME_HEADWAY := 1.1
static var _actors_frame := -1
static var _actors_tree := 0
static var _actors: Array[Node] = []
static var _spatial_frame := -1
static var _spatial_tree := 0
static var _spatial_cells: Dictionary = {}
static var _spatial_max_radius := 0.0
const SPATIAL_CELL_SIZE := 256.0
const SPATIAL_REFRESH_FRAMES := 3
# Lane travel is capped at 14 px per render callback. Across three frames,
# two approaching vehicles can close at most 84 px; 96 keeps the broad phase
# conservative while exact distance, lane projection and hull checks stay live.
const SPATIAL_MOTION_MARGIN := 96.0
static var _projection_frame := -1
static var _projections: Dictionary = {}

static func project_offset(curve: Curve2D, point: Vector2) -> float:
	# Multiple vehicles ask about the same live obstacle on the same lane.
	# Cache only exact local points, for one render frame. A move changes the
	# key immediately; editing the curve invalidates its entries synchronously.
	if not point.is_finite(): return curve.get_closest_offset(point)
	var frame := Engine.get_process_frames()
	if _projection_frame != frame:
		_projection_frame = frame
		_projections.clear()
	var id := curve.get_instance_id()
	if not _projections.has(id):
		var invalidate := _invalidate_projection.bind(id)
		if not curve.changed.is_connected(invalidate): curve.changed.connect(invalidate)
		_projections[id] = {}
	var points: Dictionary = _projections[id]
	if not points.has(point): points[point] = curve.get_closest_offset(point)
	return float(points[point])

static func _invalidate_projection(id: int) -> void:
	_projections.erase(id)

static func traffic_actors(actor: Node) -> Array[Node]:
	var tree := actor.get_tree()
	if _actors_frame != Engine.get_process_frames() or _actors_tree != tree.get_instance_id():
		_actors_frame = Engine.get_process_frames()
		_actors_tree = tree.get_instance_id()
		_actors = tree.get_nodes_in_group("vehicle")
	return _actors

static func nearby_traffic_actors(actor: Node2D, radius: float) -> Array[Node]:
	var tree_id := actor.get_tree().get_instance_id()
	var frame := Engine.get_process_frames()
	if _spatial_tree != tree_id or _spatial_frame < 0 or frame - _spatial_frame >= SPATIAL_REFRESH_FRAMES:
		_spatial_frame = frame
		_spatial_tree = tree_id
		_spatial_cells.clear()
		_spatial_max_radius = 0.0
		for candidate in traffic_actors(actor):
			if not is_instance_valid(candidate) or not candidate is Node2D: continue
			var shape := candidate.get_node_or_null("Collision") as CollisionShape2D
			if shape == null or shape.disabled or not shape.shape is RectangleShape2D: continue
			var candidate_radius: float = shape.shape.size.length() * maxf(shape.global_transform.x.length(), shape.global_transform.y.length()) * 0.5
			_spatial_max_radius = maxf(_spatial_max_radius, candidate_radius)
			var cell := Vector2i((shape.global_position / SPATIAL_CELL_SIZE).floor())
			if not _spatial_cells.has(cell): _spatial_cells[cell] = []
			_spatial_cells[cell].append(candidate)
	var reach := Vector2.ONE * (radius + _spatial_max_radius + SPATIAL_MOTION_MARGIN)
	var first := Vector2i(((actor.global_position - reach) / SPATIAL_CELL_SIZE).floor())
	var last := Vector2i(((actor.global_position + reach) / SPATIAL_CELL_SIZE).floor())
	var result: Array[Node] = []
	var included := {}
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for candidate in _spatial_cells.get(Vector2i(x, y), []):
				if not is_instance_valid(candidate): continue
				var candidate_id: int = candidate.get_instance_id()
				if included.has(candidate_id): continue
				included[candidate_id] = true
				result.append(candidate)
	return result

static func bodies(actor: Node2D) -> Array:
	if actor.has_method("get_traffic_bodies"):
		return actor.get_traffic_bodies()
	return [actor]

static func extent(actor: Node2D, axis: Vector2) -> Vector2:
	var result := Vector2.ZERO # front / rear from the actor's origin
	for body in bodies(actor):
		if not is_instance_valid(body): continue
		var shape := body.get_node_or_null("Collision") as CollisionShape2D
		if shape == null or shape.disabled or not shape.shape is RectangleShape2D:
			continue
		var half: Vector2 = shape.shape.size * 0.5
		var pose := shape.global_transform
		var center := (pose.origin - actor.global_position).dot(axis)
		var radius := absf(pose.x.dot(axis)) * half.x + absf(pose.y.dot(axis)) * half.y
		result.x = maxf(result.x, center + radius)
		result.y = maxf(result.y, radius - center)
	if result.is_zero_approx():
		var length := float(actor.get("target_length")) if "target_length" in actor else 40.0
		result = Vector2.ONE * length * 0.5
	return result

static func following(bumper_gap: float, speed: float, leader_speed: float, braking: float) -> Dictionary:
	var available := maxf(0.0, bumper_gap - STANDSTILL_GAP)
	# Safe speed if the leader brakes, plus a time headway for smooth queues.
	# A stopped leader still allows closing excess space; it does not force a
	# following car to stay stopped forever one reaction-distance behind it.
	var safe_speed := sqrt(maxf(0.0, leader_speed * leader_speed + 2.0 * braking * available))
	var headway_speed := available / TIME_HEADWAY
	return {"target_speed": minf(safe_speed, headway_speed), "allowed_advance": available,
		"desired_gap": STANDSTILL_GAP + maxf(0.0, speed) * TIME_HEADWAY}

static func lane_leader(actor: Node2D, path: Path2D, follow: PathFollow2D, limit := INF) -> Node2D:
	var nearest: Node2D = null
	var distance := limit
	for sibling in path.get_children():
		if sibling == follow or not sibling is PathFollow2D: continue
		var gap: float = sibling.progress - follow.progress
		if follow.loop and bool(path.get_meta("traffic_lane_loop", false)) and path.curve.get_baked_length() > 1.0:
			gap = fposmod(gap, path.curve.get_baked_length())
		if gap <= 0.0 or gap > distance: continue
		for child in sibling.get_children():
			if child is Node2D and (child.is_in_group("vehicle") or "target_length" in child):
				if child == actor: continue
				nearest = child
				distance = gap
				break
	return nearest

static func lane_motion(actor: Node2D, follow: PathFollow2D, speed: float, braking: float) -> Dictionary:
	var path := follow.get_parent() as Path2D
	if path == null or path.curve == null: return {"target_speed": INF, "allowed_advance": INF}
	if path.curve.get_baked_length() <= 1.0: return {"target_speed": 0.0, "allowed_advance": 0.0}
	var own := bodies(actor)
	var front := extent(actor, actor.global_transform.x.normalized()).x
	var leader := lane_leader(actor, path, follow)
	var result := {"target_speed": INF, "allowed_advance": INF}
	if leader != null: result = _follow_leader(follow, leader, front, speed, braking)
	# A tail remains an obstacle after its tractor changes Path2D. Query live
	# physical bodies along this lane, not just siblings of the front vehicle.
	var lookahead := front + STANDSTILL_GAP + speed * TIME_HEADWAY + speed * speed / (2.0 * maxf(braking, 1.0))
	var hull := actor.get_node_or_null("Collision") as CollisionShape2D
	var width: float = hull.shape.size.y * hull.global_transform.y.length() * 0.5 if hull != null and hull.shape is RectangleShape2D else 16.0
	for candidate in nearby_traffic_actors(actor, lookahead):
		# The direct sibling lookup above already applied this leader's exact
		# contract. The spatial pass remains for trailers and cross-lane bodies.
		if not is_instance_valid(candidate) or not candidate is Node2D or candidate == leader or own.has(candidate): continue
		var shape := candidate.get_node_or_null("Collision") as CollisionShape2D
		if shape == null or shape.disabled or not shape.shape is RectangleShape2D: continue
		var radius: float = shape.shape.size.length() * maxf(shape.global_transform.x.length(), shape.global_transform.y.length()) * 0.5
		if actor.global_position.distance_squared_to(candidate.global_position) > pow(lookahead + radius, 2): continue
		var offset := project_offset(path.curve, path.to_local(shape.global_position))
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
		var half: Vector2 = shape.shape.size * 0.5
		var axis := pose.x.normalized()
		var side := pose.y.normalized()
		var lateral := absf(side.dot(shape.global_transform.x)) * half.x + absf(side.dot(shape.global_transform.y)) * half.y
		if absf((shape.global_position - pose.origin).dot(side)) > width + lateral + 1.0: continue
		var gap := offset - follow.progress
		if offset <= 0.01 or offset >= path.curve.get_baked_length() - 0.01:
			gap += (shape.global_position - pose.origin).dot(axis)
		if follow.loop and bool(path.get_meta("traffic_lane_loop", false)): gap = fposmod(gap, path.curve.get_baked_length())
		if gap <= 0.0 or gap > lookahead + radius: continue
		var rear := absf(axis.dot(shape.global_transform.x)) * half.x + absf(axis.dot(shape.global_transform.y)) * half.y
		var forward_speed := 0.0
		if "_lane_motion_speed" in candidate:
			forward_speed = maxf(0.0, float(candidate._lane_motion_speed) * candidate.global_transform.x.normalized().dot(axis))
		var contract := following(gap - front - rear, speed, forward_speed, braking)
		if float(contract.allowed_advance) < float(result.allowed_advance): result["leader"] = candidate
		result.target_speed = minf(result.target_speed, contract.target_speed)
		result.allowed_advance = minf(result.allowed_advance, contract.allowed_advance)
	return result

static func _follow_leader(follow: PathFollow2D, leader: Node2D, actor_front: float, speed: float, braking: float) -> Dictionary:
	var path := follow.get_parent() as Path2D
	var ahead := leader.get_parent() as PathFollow2D
	var gap := ahead.progress - follow.progress
	if follow.loop and bool(path.get_meta("traffic_lane_loop", false)):
		gap = fposmod(gap, path.curve.get_baked_length())
	gap -= actor_front + extent(leader, leader.global_transform.x.normalized()).y
	var leader_speed := float(leader.get("_lane_motion_speed")) if "_lane_motion_speed" in leader else 0.0
	if leader.get("is_broken") == true: leader_speed = 0.0
	var result := following(gap, speed, maxf(0.0, leader_speed), braking)
	result["leader"] = leader
	return result

static func occupies_junction(actor: Node2D, center: Vector2, radius: float) -> bool:
	for body in bodies(actor):
		if not is_instance_valid(body): continue
		var collision := body.get_node_or_null("Collision") as CollisionShape2D
		if collision == null or collision.disabled or not collision.shape is RectangleShape2D: continue
		var half: Vector2 = collision.shape.size * 0.5
		var closest := collision.to_local(center).clamp(-half, half)
		if collision.to_global(closest).distance_to(center) <= radius: return true
	return false

static func exit_blocker(actor: Node2D, path: Path2D, start: float, finish: float, actors: Array[Node]) -> Node2D:
	# Test the receiving corridor, including parked cars and articulated bodies
	# whose head may already be on a different lane. Ignore our own trailers.
	var own := bodies(actor)
	var width := 20.0
	var collision := actor.get_node_or_null("Collision") as CollisionShape2D
	if collision != null and collision.shape is RectangleShape2D:
		width = collision.shape.size.y * collision.global_transform.y.length() * 0.5
	var length := path.curve.get_baked_length()
	var first_pose := path.global_transform * path.curve.sample_baked_with_rotation(clampf(start, 0.0, length), true)
	var region := Rect2(first_pose.origin, Vector2.ZERO)
	var sample_count := maxi(1, ceili((finish - start) / 32.0))
	for i in range(sample_count + 1):
		var offset := lerpf(start, finish, float(i) / sample_count)
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(clampf(offset, 0.0, length), true)
		var point := pose.origin + pose.x.normalized() * maxf(0.0, offset - length)
		region = region.expand(point)
	for candidate in actors:
		if not is_instance_valid(candidate) or not candidate is Node2D or own.has(candidate): continue
		var body := candidate as Node2D
		var shape := body.get_node_or_null("Collision") as CollisionShape2D
		if shape == null or shape.disabled or not shape.shape is RectangleShape2D: continue
		var body_radius: float = shape.shape.size.length() * maxf(shape.global_transform.x.length(), shape.global_transform.y.length()) * 0.5
		if not region.grow(width + body_radius + 2.0).has_point(body.global_position): continue
		var offset := project_offset(path.curve, path.to_local(body.global_position))
		var pose := path.global_transform * path.curve.sample_baked_with_rotation(offset, true)
		var axis := pose.x.normalized()
		var side := pose.y.normalized()
		var center_delta := body.global_position - pose.origin
		# At an open endpoint closest_offset clamps; retain the projected distance.
		if offset <= 0.01 or offset >= length - 0.01: offset += center_delta.dot(axis)
		var half: Vector2 = shape.shape.size * 0.5
		var longitudinal := absf(axis.dot(shape.global_transform.x)) * half.x + absf(axis.dot(shape.global_transform.y)) * half.y
		var lateral := absf(side.dot(shape.global_transform.x)) * half.x + absf(side.dot(shape.global_transform.y)) * half.y
		if absf(center_delta.dot(side)) > width + lateral + 2.0: continue
		if offset + longitudinal > start and offset - longitudinal < finish:
			return body
	return null
