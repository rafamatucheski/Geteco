extends RefCounted
## Local, forward-only terminal maneuver. Lane geometry supplies parking poses;
## live physics supplies the hull, door/cot clearance and the walking corridor.
const SAFETY = preload("res://cars/VehicleMotionSafety.gd")
const TURN_RADIUS := 70.0
const TEAM_RADIUS := 34.0 # 25px handle offset + 8px adult capsule extent + margin.

static func _team_radius(unit: CharacterBody2D) -> float:
	# The coroner's agents carry separate narrow carts, not the ambulance's
	# three-abreast formation. Keep the ambulance's full corridor unchanged.
	return 18.0 if unit.get("type") == 3 else TEAM_RADIUS
var target_id := 0
var target_point := Vector2.INF
var candidates: Array[Dictionary] = []
var trajectory := PackedVector2Array()
var headings := PackedFloat32Array()
var remaining_lengths := PackedFloat32Array()
var cursor := 1
var retry := 0.0
var parking_pose := Transform2D.IDENTITY
var walk_route: Array[Vector2] = []
var blocked_time := 0.0
var road_surfaces: Array[PackedVector2Array] = []
var junctions: Array[Dictionary] = []
var max_plan_usec := 0
var candidates_checked := 0
var rejections := {}
var _walk_search: RefCounted
var _walk_goal_index := 0
var _walk_pending := false
var _access_wait := 0.0
var _best_access_distance := INF

func _clear_walk_search() -> void:
	if _walk_search: _walk_search.dispose()
	_walk_search = null
	_walk_goal_index = 0
	_walk_pending = false
var last_rejection_detail := ""
var reverse_remaining := 0.0
var recovery_attempts := 0
var reservation: Node

func _reject(reason: String) -> bool:
	rejections[reason] = int(rejections.get(reason,0))+1
	return false

func reset() -> void:
	if is_instance_valid(reservation): reservation.cancel()
	reservation = null
	_clear_walk_search()
	target_id = 0
	target_point = Vector2.INF
	candidates.clear()
	trajectory.clear()
	headings.clear()
	remaining_lengths.clear()
	walk_route.clear()
	cursor = 1
	retry = 0
	blocked_time = 0
	road_surfaces.clear()
	junctions.clear()
	max_plan_usec = 0
	candidates_checked = 0
	rejections.clear()
	reverse_remaining = 0
	recovery_attempts = 0
	_access_wait = 0.0
	_best_access_distance = INF

func tick(unit: CharacterBody2D, patient: Node2D, delta: float) -> bool:
	if target_id != patient.get_instance_id() or target_point.distance_to(patient.global_position) > 40:
		reset()
		target_id = patient.get_instance_id()
		target_point = patient.global_position
	if unit.global_position.distance_to(patient.global_position) > 620 and trajectory.is_empty(): return false
	# Failed parking must not hold a casualty forever. Backing up or circling
	# does not reset progress: only a new closest approach earns more time.
	var access_distance := unit.global_position.distance_to(patient.global_position)
	_access_wait += delta
	if access_distance < _best_access_distance-4:
		_best_access_distance = access_distance
		_access_wait = 0.0
	if _access_wait >= 45 and unit.current_speed < 1:
		unit.get_node("/root/NPCMedicalCare").defer_inaccessible(patient,unit,"parking_access_blocked")
		unit.set_meta("medical_abort_reason","parking_access_blocked")
		unit.set_meta("medical_abort_phase","parking")
		unit.set_meta("medical_phase","parking_access_blocked")
		unit.target = null
		unit.is_acting = false
		unit.is_returning_to_base = true
		unit.velocity = Vector2.ZERO
		unit._lane_router.reset()
		unit._notify_return_started()
		reset()
		return true
	unit.stuck_despawn_timer = 0
	unit.is_reversing = false
	if reverse_remaining > 0:
		var step := minf(reverse_remaining,30*delta)
		if _move_to(unit,unit.global_position-unit.global_transform.x*step,unit.global_rotation,delta):
			reverse_remaining -= step
			unit.current_speed = 30
		else: reverse_remaining = 0
		if reverse_remaining < .01:
			reverse_remaining = 0
			unit.current_speed = 0
			unit.velocity = Vector2.ZERO
			retry = 0
		return true
	if not trajectory.is_empty():
		_drive(unit, patient, delta)
		return true
	# Candidate work is distributed over physics ticks; no all-city shape scan
	# or navigation search runs in the ordinary per-frame driving loop.
	retry -= delta
	if candidates.is_empty() and retry > 0:
		# A short straight reverse can restore turning clearance when a bus
		# leaves too little room to begin the forward curve. No pivot or side
		# translation is permitted, and recovery is finite rather than oscillating.
		if recovery_attempts < 2 and unit.current_speed < 1:
			recovery_attempts += 1
			reverse_remaining = 70
			return true
		unit.current_speed = move_toward(unit.current_speed,0,520*delta)
		_move_forward(unit,unit.global_rotation,unit.current_speed*delta,delta)
		return true
	var planning_started := Time.get_ticks_usec()
	if candidates.is_empty() and retry <= 0:
		_collect(unit, patient)
		retry = 2.0
	if not candidates.is_empty():
		candidates_checked += 1
		var candidate: Dictionary = candidates.pop_front()
		var pose: Transform2D = candidate.pose
		var stationary: bool = pose.origin.distance_to(unit.global_position) < .01 and unit.current_speed < 1
		if service_clear(unit, patient, pose) and (stationary or _build_trajectory(unit, pose)):
			parking_pose = pose
			unit.set_meta("ambulance_parking_goal", pose.origin)
			unit.set_meta("ambulance_parking_exceptional", candidate.exceptional)
			if not stationary:
				if is_instance_valid(reservation): reservation.cancel()
				reservation = preload("res://emergency/AmbulanceManeuverReservation.gd").new()
				unit.get_parent().add_child(reservation)
				reservation.configure(unit)
				reservation.follow(trajectory,headings,cursor)
			max_plan_usec = maxi(max_plan_usec,Time.get_ticks_usec()-planning_started)
			if stationary:
				unit.set_meta("ambulance_walk_route",walk_route.duplicate())
				unit._begin_response()
			return true
		if _walk_pending: candidates.push_front(candidate)
	max_plan_usec = maxi(max_plan_usec,Time.get_ticks_usec()-planning_started)
	# Wait with the wheels straight while a bounded planner searches. Braking
	# still moves along the vehicle axis, and cannot slide against a collider.
	unit.current_speed = move_toward(unit.current_speed, 0.0, 520.0 * delta)
	_move_forward(unit, unit.global_rotation, unit.current_speed * delta, delta)
	return true

func _collect(unit: CharacterBody2D, patient: Node2D) -> void:
	var half: Vector2 = _half_size(unit)
	road_surfaces.clear()
	junctions.clear()
	var graphs: Array[Node] = []
	var aligned_here := false
	for node in unit.get_tree().get_nodes_in_group("unified_traffic_lane"):
		var lane := node as Path2D
		if lane == null or not lane.can_process() or lane.curve == null or lane.curve.point_count < 2: continue
		var curve := lane.curve
		var nearest := curve.get_closest_offset(lane.to_local(patient.global_position))
		if lane.to_global(curve.sample_baked(nearest)).distance_to(patient.global_position) > 420: continue
		var parent := lane.get_parent()
		var graph := parent.get_parent() if parent else null
		if graph != null and graph.has_method("get_signal_ground_surfaces") and not graphs.has(graph):
			graphs.append(graph)
			var version: int = graph.get_routing_revision()
			var cache: Dictionary = graph.get_meta("ambulance_emergency_surface_cache",{})
			if cache.get("version",-1) != version:
				# Read only junction geometry; duplicating the complete lane and
				# connection graph here causes an avoidable dispatch-time stall.
				# Emergency turns may use the actually drawn sidewalk apron. The
				# whole hull still sweeps live pedestrians, posts and buildings;
				# this never widens geometry into an unpaved shortcut.
				cache = {"version":version,"surfaces":graph.get_signal_ground_surfaces(graph.SIDEWALK_MARGIN*2),"junctions":graph.get("_junctions")}
				graph.set_meta("ambulance_emergency_surface_cache",cache)
			for local_polygon in cache.surfaces:
				var polygon: PackedVector2Array = graph.global_transform * local_polygon
				var bounds := Rect2(polygon[0],Vector2.ZERO)
				for vertex in polygon: bounds = bounds.expand(vertex)
				if bounds.grow(700).has_point(unit.global_position): road_surfaces.append(polygon)
			for junction in cache.junctions:
				var radius := 0.0
				for approach in junction.get("approaches",[]): radius = maxf(radius,float(approach.road_width)*.5)
				junctions.append({"point":graph.to_global(junction.position),"radius":radius+half.x+45})
		var length := curve.get_baked_length()
		var here := curve.get_closest_offset(lane.to_local(unit.global_position))
		var here_point := lane.to_global(curve.sample_baked(here,true))
		var here_tangent := (lane.to_global(curve.sample_baked(minf(length,here+8),true))-lane.to_global(curve.sample_baked(maxf(0,here-8),true))).normalized()
		if here_point.distance_to(unit.global_position)<8 and absf(here_tangent.dot(unit.global_transform.x))>.98: aligned_here = true
		for offset_delta in [0.0, -80.0, 80.0, -160.0, 160.0, -240.0, 240.0, -320.0, 320.0, -400.0, 400.0]:
			var offset := clampf(nearest + offset_delta, 0, length)
			var point := lane.to_global(curve.sample_baked(offset, true))
			var tangent := (lane.to_global(curve.sample_baked(minf(length, offset+8), true)) - lane.to_global(curve.sample_baked(maxf(0, offset-8), true))).normalized()
			if tangent.is_zero_approx(): continue
			if point.distance_to(patient.global_position) > 440: continue
			# Prefer stopping outside connector/crosswalk ends. Short lanes and
			# exceptional emergency stops remain eligible with a score penalty.
			var exceptional := offset < half.x + 60 or length-offset < half.x + 60
			for junction in junctions:
				if point.distance_to(junction.point) < float(junction.radius): exceptional = true
			var travel := point-unit.global_position
			if travel.dot(unit.global_transform.x) < 20 or travel.length() < 45: continue
			var cost := point.distance_to(patient.global_position) + travel.length() * .15 + (300 if exceptional else 0)
			candidates.append({"pose": Transform2D(tangent.angle(), point), "cost": cost, "exceptional": exceptional})
			# If traffic prevents reaching the regular bay, an emergency unit
			# already facing against this lane can stop upstream without a U-turn.
			# This costs more than every ordinary nearby pose and still requires
			# the complete hull/door/cot checks and a traversable patient route.
			if tangent.dot(unit.global_transform.x) < -.7:
				candidates.append({"pose":Transform2D((-tangent).angle(),point),"cost":cost+600,"exceptional":true})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.cost < b.cost)
	if candidates.size() > 96: candidates.resize(96)
	# A gridlock can leave no forward maneuver at all. The existing aligned
	# pose is an emergency last resort only if unloading and patient access
	# independently pass; proximity by itself never authorizes deployment.
	if aligned_here and unit.current_speed < 1 and unit.global_position.distance_to(patient.global_position) < 520:
		candidates.append({"pose":unit.global_transform,"cost":2000,"exceptional":true})

static func _half_size(unit: CharacterBody2D) -> Vector2:
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var physical := hull.shape.get_rect().size * hull.global_scale.abs() * .5
	var visual: Vector2 = unit.get_meta("emergency_visual_half_size",physical)
	return Vector2(maxf(physical.x,visual.x),maxf(physical.y,visual.y))

static func _hull_margin(unit: CharacterBody2D) -> float:
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var growth := _half_size(unit)-hull.shape.get_rect().size*hull.global_scale.abs()*.5
	return maxf(3,maxf(growth.x,growth.y)+1)

static func rear_distance(unit: CharacterBody2D) -> float:
	return maxf(78,_half_size(unit).x+_team_radius(unit)+4)

func _query(unit: CharacterBody2D, shape: Shape2D, pose: Transform2D, mask := 7) -> PhysicsShapeQueryParameters2D:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = pose
	query.collision_mask = mask
	query.exclude = [unit.get_rid()]
	query.margin = 1.0
	return query

func service_clear(unit: CharacterBody2D, patient: Node2D, pose: Transform2D) -> bool:
	var half := _half_size(unit)
	# Full side walkways, front doors and the entire rear extraction/staging
	# volume, derived from the current model hull and the production cot path.
	var rear := rear_distance(unit)+34
	var envelope := RectangleShape2D.new()
	envelope.size = Vector2(half.x+10+rear, (half.y+32)*2)
	var center := pose * Vector2((half.x+10-rear)*.5, 0)
	var query := _query(unit, envelope, Transform2D(pose.get_rotation(),center), 3)
	var occupied := unit.get_world_2d().direct_space_state.intersect_shape(query,1)
	if not occupied.is_empty():
		_clear_walk_search()
		last_rejection_detail = str(occupied[0].collider.get_path())
		return _reject("service_envelope")
	var start := pose * Vector2(-rear_distance(unit),0)
	walk_route = _walking_route(unit, patient, pose, start)
	if not walk_route.is_empty(): return true
	return false if _walk_pending else _reject("walking_route")

func _walking_route(unit: CharacterBody2D, patient: Node2D, pose: Transform2D, start: Vector2) -> Array[Vector2]:
	# A casualty beside a facade may be reachable from the street side only.
	# Choose a real working position around them, not just the nearest point.
	var goals: Array[Vector2] = []
	for i in 8: goals.append(patient.global_position+Vector2.from_angle(i*TAU/8)*28)
	goals.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.distance_squared_to(start)<b.distance_squared_to(start))
	var circle := CircleShape2D.new()
	circle.radius = _team_radius(unit)
	var query := _query(unit,circle,Transform2D.IDENTITY,3)
	if patient is CollisionObject2D: query.exclude.append(patient.get_rid())
	var space := unit.get_world_2d().direct_space_state
	var key := "%s:%s:%s"%[pose,patient.get_instance_id(),patient.global_position]
	if _walk_search and _walk_search.key != key: _clear_walk_search()
	while _walk_goal_index < goals.size():
		var goal := goals[_walk_goal_index]
		query.transform.origin = goal
		if not space.intersect_shape(query,1).is_empty():
			_walk_goal_index += 1
			continue
		var sight := PhysicsRayQueryParameters2D.create(goal,patient.global_position,3,query.exclude)
		if not space.intersect_ray(sight).is_empty():
			_walk_goal_index += 1
			continue
		var route := _walking_route_to(unit,patient,pose,start,goal)
		if not route.is_empty():
			_clear_walk_search()
			return route
		if not _walk_search:
			_walk_search = preload("res://emergency/MedicalParkingRouteSearch.gd").new()
			_walk_search.configure(unit,patient,pose,start,_team_radius(unit),_half_size(unit))
		var path: Array[Vector2] = _walk_search.route(goal)
		_walk_pending = _walk_search._search_pending
		if not path.is_empty():
			var result: Array[Vector2] = [start]
			result.append_array(path)
			_clear_walk_search()
			return result
		if _walk_pending: return []
		_walk_goal_index += 1
	_clear_walk_search()
	return []

func _walking_route_to(unit: CharacterBody2D, patient: Node2D, pose: Transform2D, start: Vector2, goal: Vector2) -> Array[Vector2]:
	# Conservative swept circle contains cot plus both attendants. Keep the
	# planned ambulance footprint even though its live body is still en route.
	var options: Array = [[start,goal]]
	for side in [-1,1]:
		for distance in [90.0,160.0]:
			var elbow: Vector2 = start + pose.y * side * distance
			options.append([start,elbow,Vector2(goal.x,elbow.y),goal])
			options.append([start,elbow,Vector2(elbow.x,goal.y),goal])
	var circle := CircleShape2D.new()
	circle.radius = _team_radius(unit)
	var query := _query(unit,circle,Transform2D.IDENTITY,3)
	if patient is CollisionObject2D: query.exclude.append(patient.get_rid())
	var space := unit.get_world_2d().direct_space_state
	var half := _half_size(unit) + Vector2.ONE*_team_radius(unit)
	var occupied := Rect2(-half,half*2)
	var inverse := pose.affine_inverse()
	for option in options:
		var clear := true
		for i in range(1,option.size()):
			var a: Vector2 = option[i-1]
			var b: Vector2 = option[i]
			if _crosses_box(inverse*a,inverse*b,occupied):
				clear = false
				break
			query.transform.origin = a
			query.motion = b-a
			if not space.intersect_shape(query,1).is_empty() or space.cast_motion(query)[0] < 1.0:
				clear = false
				break
		if clear:
			var result: Array[Vector2] = []
			result.assign(option)
			return result
	return []

static func _crosses_box(a: Vector2,b: Vector2,box: Rect2) -> bool:
	var near := 0.0
	var far := 1.0
	var direction := b-a
	for axis in 2:
		if absf(direction[axis]) < .00001:
			if a[axis] < box.position[axis] or a[axis] > box.end[axis]: return false
		else:
			var first := (box.position[axis]-a[axis])/direction[axis]
			var last := (box.end[axis]-a[axis])/direction[axis]
			near = maxf(near,minf(first,last))
			far = minf(far,maxf(first,last))
			if near > far: return false
	return true

func _build_trajectory(unit: CharacterBody2D, pose: Transform2D) -> bool:
	if _build_trajectory_with_lead(unit,pose,0): return true
	# Remain on the approach street before turning into a perpendicular lane.
	# A single long Bezier otherwise cuts across the outside of the junction.
	var forward_distance := (pose.origin-unit.global_position).dot(unit.global_transform.x)
	for turn_space in [120.0,180.0,240.0]:
		var lead := forward_distance-float(turn_space)
		if lead > 30 and _build_trajectory_with_lead(unit,pose,lead): return true
	return false

func _build_trajectory_with_lead(unit: CharacterBody2D, pose: Transform2D, lead: float) -> bool:
	var origin := unit.global_position
	var start := origin+unit.global_transform.x*lead
	var end := pose.origin
	var length := start.distance_to(end)
	var handle := length * .4
	var a := start + unit.global_transform.x * handle
	var b := end - pose.x * handle
	var points := PackedVector2Array([origin])
	var angles := PackedFloat32Array([unit.global_rotation])
	var steps := maxi(16,ceili(length/3))
	var lead_steps := ceili(lead/3)
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := _query(unit,hull.shape,hull.global_transform)
	query.margin = _hull_margin(unit)
	var space := unit.get_world_2d().direct_space_state
	for i in range(1,lead_steps+steps+1):
		var t := maxf(0,float(i-lead_steps)/steps)
		var point := origin.lerp(start,float(i)/maxi(1,lead_steps)) if i <= lead_steps else start.bezier_interpolate(a,b,end,t)
		var heading := unit.global_rotation if i <= lead_steps else start.bezier_derivative(a,b,end,t).angle()
		# Test the swept model's corners against the same pavement polygons
		# used to draw roads and junctions, including curved junction patches.
		if not road_surfaces.is_empty():
			var half := _half_size(unit)
			for corner in [Vector2(-half.x,-half.y),Vector2(-half.x,half.y),Vector2(half.x,-half.y),Vector2(half.x,half.y)]:
				var on_road := false
				var vertex: Vector2 = Transform2D(heading,point)*corner
				for polygon in road_surfaces:
					if Geometry2D.is_point_in_polygon(vertex,polygon):
						on_road = true
						break
				if not on_road:
					last_rejection_detail = "pavement corner "+str(vertex)
					return _reject("pavement")
		var ds := point.distance_to(points[-1])
		if ds < .001 or absf(angle_difference(angles[-1],heading)) > ds/TURN_RADIUS: return _reject("turn_radius")
		query.transform = Transform2D(heading, points[-1]) * hull.transform
		query.motion = point-points[-1]
		if not space.intersect_shape(query,1).is_empty() or space.cast_motion(query)[0] < 1: return _reject("trajectory_obstacle")
		points.append(point)
		angles.append(heading)
	trajectory = points
	headings = angles
	remaining_lengths.resize(points.size())
	remaining_lengths[-1] = 0
	for i in range(points.size()-2,-1,-1):
		remaining_lengths[i] = remaining_lengths[i+1]+points[i].distance_to(points[i+1])
	cursor = 1
	return true

func _drive(unit: CharacterBody2D, patient: Node2D, delta: float) -> void:
	if is_instance_valid(reservation): reservation.follow(trajectory,headings,cursor)
	var remaining := unit.global_position.distance_to(trajectory[cursor])+remaining_lengths[cursor]
	var desired := minf(95, sqrt(2*240*remaining))
	unit.current_speed = move_toward(unit.current_speed,desired,240*delta)
	var distance: float = minf(remaining,unit.current_speed*delta)
	var moved := false
	while distance > .001 and cursor < trajectory.size():
		var segment := unit.global_position.distance_to(trajectory[cursor])
		var step := minf(distance,segment)
		var fraction := step/maxf(.001,segment)
		var next := unit.global_position.lerp(trajectory[cursor],fraction)
		var heading := lerp_angle(unit.global_rotation,headings[cursor],fraction)
		if not _move_to(unit,next,heading,delta): break
		moved = true
		distance -= step
		if fraction >= .999:
			if cursor == trajectory.size()-1:
				unit.current_speed = 0
				unit.velocity = Vector2.ZERO
				if service_clear(unit,patient,unit.global_transform):
					unit.set_meta("ambulance_walk_route",walk_route.duplicate())
					unit._begin_response()
				else:
					if is_instance_valid(reservation): reservation.cancel()
					trajectory.clear()
					candidates.clear()
					retry = 0
				return
			cursor += 1
	blocked_time = 0 if moved else blocked_time+delta
	if not moved:
		unit.current_speed = 0
		unit.velocity = Vector2.ZERO
	if blocked_time > 1:
		if is_instance_valid(reservation): reservation.cancel()
		trajectory.clear()
		candidates.clear()
		retry = 0
		blocked_time = 0

func _move_forward(unit: CharacterBody2D, heading: float, distance: float, delta: float) -> void:
	_move_to(unit,unit.global_position+Vector2.from_angle(heading)*distance,heading,delta)

func _move_to(unit: CharacterBody2D, point: Vector2, heading: float, delta: float) -> bool:
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := _query(unit,hull.shape,Transform2D(heading,unit.global_position)*hull.transform)
	query.margin = _hull_margin(unit)
	query.motion = point-unit.global_position
	var space := unit.get_world_2d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		# A neighbour can consume the comfort buffer while this unit brakes.
		# Straight recovery still uses the full physical hull, so it can back
		# away from contact without allowing a pivot or penetration of solids.
		if absf(angle_difference(unit.global_rotation,heading)) > .001: return false
		query.margin = 0
		if not space.intersect_shape(query,1).is_empty(): return false
	if space.cast_motion(query)[0] < 1: return false
	SAFETY.rotate_clear(unit,heading)
	if absf(angle_difference(unit.global_rotation,heading)) > .001: return false
	var displacement := point-unit.global_position
	unit.velocity = displacement/maxf(.001,delta)
	unit.move_and_collide(displacement)
	unit.set_meta("vehicle_safe_position",unit.global_position)
	unit.set_meta("vehicle_safe_transform",unit.global_transform)
	return unit.global_position.distance_to(point) < .01
