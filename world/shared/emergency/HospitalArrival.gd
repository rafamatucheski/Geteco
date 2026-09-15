extends RefCounted
## Hospital parking has a latched arrival, separate from road navigation.
var goal := Vector2.INF
var path := PackedVector2Array()
var angles := PackedFloat32Array()
var cursor := 1
var retry := 0.0
var blocked := 0.0
var planner := preload("res://world/shared/emergency/AmbulanceApproach.gd").new()
var search: RefCounted
var reservation: Node
var arc_path := false

func reset() -> void:
	_release_traffic()
	goal = Vector2.INF
	path.clear()
	angles.clear()
	cursor = 1
	retry = 0
	blocked = 0
	search = null
	arc_path = false

func _release_traffic() -> void:
	if is_instance_valid(reservation): reservation.cancel()
	reservation = null

func arrived(unit: CharacterBody2D, stop: Vector2, heading: float) -> bool:
	# A usable pose within the bay, not convergence to one pixel. Keep the
	# whole body behind the public walkway and the rear extraction corridor.
	var local := (unit.global_position-stop).rotated(-heading)
	return local.x >= -2 and local.x <= 12 and absf(local.y) <= 5 and absf(angle_difference(unit.global_rotation,heading)) <= .035 and clear_pose(unit,unit.global_transform)

static func clear_pose(unit: CharacterBody2D, pose: Transform2D) -> bool:
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.transform = pose*hull.transform
	query.collision_mask = 3
	query.exclude = [unit.get_rid()]
	query.margin = .15
	return unit.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty()

func tick(unit: CharacterBody2D, stop: Vector2, heading: float, delta: float) -> bool:
	unit.is_reversing = false
	unit.stuck_despawn_timer = 0
	if arrived(unit,stop,heading):
		_release_traffic()
		unit.velocity = Vector2.ZERO
		unit.current_speed = 0
		return true
	if goal != stop: reset(); goal = stop
	retry -= delta
	if path.is_empty() and search == null and retry <= 0:
		retry = 1.0
		for offset in [0.0,8.0]:
			var end: Vector2 = stop+Vector2.from_angle(heading)*offset
			for reverse in [true,false]:
				if _curve(unit,unit.global_position,unit.global_rotation,end,heading,reverse): break
			if not path.is_empty(): break
		if path.is_empty():
			search = preload("res://world/shared/emergency/HospitalParkingSearch.gd").new()
			search.configure(unit,stop,heading)
	if search != null:
		search.advance()
		if search.finished:
			path = search.path
			angles = search.headings
			arc_path = true
			cursor = 1
			search = null
			retry = 2
	if path.is_empty():
		unit.velocity = Vector2.ZERO
		unit.current_speed = 0
		blocked += delta
		unit.set_meta("hospital_dock_waiting",true)
		return false
	if not is_instance_valid(reservation):
		reservation = preload("res://world/shared/emergency/AmbulanceManeuverReservation.gd").new()
		reservation.allow_hospital_return = true
		unit.get_parent().add_child(reservation)
		reservation.configure(unit)
	reservation.follow(path,angles,cursor)
	unit.remove_meta("hospital_dock_waiting")
	var budget := 27.0*delta
	var moved := false
	while budget>.001 and cursor<path.size():
		var distance := unit.global_position.distance_to(path[cursor])
		var turn := angle_difference(unit.global_rotation,angles[cursor])
		if arc_path and absf(turn)>.001: distance *= absf(turn/(2*sin(turn*.5)))
		var step := minf(budget,distance)
		var fraction := step/maxf(.001,distance)
		var next := unit.global_position.lerp(path[cursor],fraction)
		if arc_path and fraction<.999 and absf(turn)>.001:
			var direction := signf((path[cursor]-unit.global_position).dot(Vector2.from_angle(unit.global_rotation+turn*.5)))
			var half := turn*fraction*.5
			next = unit.global_position+Vector2.from_angle(unit.global_rotation+half)*direction*step*sin(half)/half
		var before := unit.global_transform
		if not planner._move_to(unit,next,unit.global_rotation+turn*fraction,delta):
			if unit.global_position.distance_to(before.origin)<.001: unit.global_rotation = before.get_rotation()
			break
		moved = true
		budget -= step
		if fraction >= .999: cursor+=1
	blocked = 0 if moved else blocked+delta
	unit.current_speed = 27 if moved else 0
	if not moved: unit.velocity = Vector2.ZERO
	# A crossing pedestrian is a reason to yield, not to discard a valid
	# maneuver every second and start driving the opposite way again.
	var yielding := not moved and blocked>1 and blocked<8 and _pedestrian_crossing(unit)
	if cursor>=path.size() or (blocked>1 and not yielding):
		_release_traffic()
		path.clear()
		retry = .5
	return false

func _pedestrian_crossing(unit: CharacterBody2D) -> bool:
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.transform = hull.global_transform
	query.collision_mask = 4
	query.exclude = [unit.get_rid()]
	query.margin = planner._hull_margin(unit)
	query.motion = (path[cursor]-unit.global_position).limit_length(4) if cursor<path.size() else Vector2.ZERO
	var space := unit.get_world_2d().direct_space_state
	return not space.intersect_shape(query,1).is_empty() or space.cast_motion(query)[0]<1

func _curve(unit: CharacterBody2D, start: Vector2, from_angle: float, end: Vector2, to_angle: float, reverse: bool) -> bool:
	var sign_motion := -1.0 if reverse else 1.0
	var distance := start.distance_to(end)
	if distance<.5: return false
	var a := start+Vector2.from_angle(from_angle)*distance*.4*sign_motion
	var b := end-Vector2.from_angle(to_angle)*distance*.4*sign_motion
	var points := PackedVector2Array([start])
	var headings := PackedFloat32Array([from_angle])
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = hull.shape
	query.collision_mask = unit.collision_mask
	query.exclude = [unit.get_rid()]
	query.margin = planner._hull_margin(unit)+.2
	var space := unit.get_world_2d().direct_space_state
	var steps := maxi(16,ceili(distance/3))
	for i in range(1,steps+1):
		var t := float(i)/steps
		var point := start.bezier_interpolate(a,b,end,t)
		var angle := start.bezier_derivative(a,b,end,t).angle()+(PI if reverse else 0.0)
		var ds := point.distance_to(points[-1])
		if ds<.001 or absf(angle_difference(headings[-1],angle))>ds/70.0: return false
		query.transform = Transform2D(angle,points[-1])*hull.transform
		query.motion = point-points[-1]
		if not space.intersect_shape(query,1).is_empty() or space.cast_motion(query)[0]<1: return false
		points.append(point)
		headings.append(angle)
	path = points
	angles = headings
	arc_path = false
	cursor = 1
	return true
