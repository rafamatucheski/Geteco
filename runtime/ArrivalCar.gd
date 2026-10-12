extends "res://scripts/Vehicle.gd"
## Original native M8 geometry with inherited swept driving and full hull.
var model: Node3D
var _last_distance := 0.0
var _progress_anchor := Vector3.INF
var _no_progress_seconds := 0.0
var tour_route: Curve3D
var road_router
var search := preload("res://runtime/ArrivalPathSearch.gd").new()
var recovery_path: Array[Dictionary] = []
var recovery_index := 1
var recovery_count := 0
var _search_retry := 0.0
var _failed_searches := 0
var _path_stall := 0.0
var _path_anchor := Vector3.INF

func configure_journey(authored: Curve3D, graph) -> void:
	tour_route = authored
	search.searching = false
	recovery_path.clear()
	_progress_anchor = Vector3.INF
	_no_progress_seconds = 0.0
	road_router = preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	road_router.configure(graph)

func tour_progress() -> float:
	return tour_route.get_closest_offset(global_position) if tour_route != null else route_distance

func recovering_path() -> bool:
	return search.searching or not recovery_path.is_empty()

func _drive_traffic(delta: float) -> void:
	_search_retry = maxf(0.0,_search_retry-delta)
	if road_router != null: road_router.advance(delta)
	if search.searching:
		speed = move_toward(speed,0.0,12.0*delta)
		search.tick()
		if not search.searching:
			if search.result.is_empty():
				_failed_searches += 1
				if _failed_searches >= 2: _change_street_route()
				_search_retry = 1.0
			else:
				recovery_path = search.result.duplicate()
				recovery_index = 1
				_path_anchor = global_position
				_path_stall = 0.0
				recovery_count += 1
				print("MACIOTA_PATH_READY maneuvers=",recovery_path.size()," expanded=",search.expanded," goal=",search.goal)
		return
	if not recovery_path.is_empty():
		_follow_recovery(delta)
		return
	super._drive_traffic(delta)
	if route == null: return
	# The front sensor can alternate clear/blocked at braking distance. Its
	# blocked_time then resets every few frames although the car never moves.
	# Measure real displacement instead, while preserving signal waits and the
	# intentional stop at the workshop.
	if not _progress_anchor.is_finite() or global_position.distance_to(_progress_anchor) > 1.5 or route_distance >= route.get_baked_length()-1.5:
		_progress_anchor = global_position
		_no_progress_seconds = 0.0
		return
	_no_progress_seconds += delta
	if _no_progress_seconds > 4.0 and _search_retry <= 0.0 and absf(speed)<.6 and (not junction_wait or _no_progress_seconds>30.0):
		_start_search()

func _start_search() -> void:
	_end_bypass()
	backoff_time = 0.0
	unjam_time = 0.0
	var length := route.get_baked_length()
	var goal_offset := minf(length,route.get_closest_offset(global_position)+24.0+float(_failed_searches%2)*12.0)
	var goal := route.sample_baked(goal_offset,true)
	var direction := route.sample_baked(minf(length,goal_offset+.3),true)-route.sample_baked(maxf(0.0,goal_offset-.3),true)
	search.begin(self,goal,atan2(-direction.x,-direction.z))
	print("MACIOTA_PATH_SEARCH start=",global_position," goal=",goal)

func _change_street_route() -> void:
	if road_router == null or tour_route == null: return
	var entrance_offset := tour_route.get_closest_offset(tour_route.get_meta("court_access_start",tour_route.get_point_position(tour_route.point_count-1)))
	var goal := tour_route.sample_baked(maxf(0.0,entrance_offset-8.0),true)
	road_router.block_edge_near(global_position-global_basis.z*6.0,45.0,-global_basis.z)
	var plan: Dictionary = road_router.plan(global_position,goal,-global_basis.z)
	if not plan.get("ok",false): return
	var changed: Curve3D = plan.curve
	var tail := tour_route.get_closest_offset(plan.end)
	while tail<tour_route.get_baked_length():
		changed.add_point(tour_route.sample_baked(tail,true))
		tail += 1.0
	changed.add_point(tour_route.get_point_position(tour_route.point_count-1))
	route = changed
	route_distance = 0.0
	_failed_searches = 0
	_no_progress_seconds = 5.0
	print("MACIOTA_ROUTE_CHANGED length=",route.get_baked_length()," native_search=",road_router._native!=null)

func _follow_recovery(delta: float) -> void:
	route_distance = _traffic_route_offset(global_position)
	if recovery_index>=recovery_path.size():
		recovery_path.clear()
		_no_progress_seconds = 0.0
		_failed_searches = 0
		return
	var target: Dictionary = recovery_path[recovery_index]
	var offset: Vector3 = target.p-global_position
	offset.y = 0.0
	if offset.length()<.45:
		recovery_index += 1
		return
	var gear := int(target.gear)
	junction_wait = _junction_gate(route.get_baked_length(),true)
	if gear>0 and junction_wait and junction_gap<.5:
		speed = move_toward(speed,0.0,12.0*delta)
		_path_stall = 0.0
		return
	if speed*gear<-.05:
		speed = move_toward(speed,0.0,10.0*delta)
		return
	var desired_yaw := atan2(-offset.x*gear,-offset.z*gear)
	var yaw := rotate_toward(rotation.y,desired_yaw,delta*1.2)
	var safe := can_rotate(yaw)
	if safe: rotation.y = yaw
	steering = clampf(angle_difference(rotation.y,desired_yaw)*gear,-.48,.48)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = 7
	query.exclude = [get_rid()]
	query.transform = Transform3D(global_basis,to_global(shape.position))
	query.motion = -global_basis.z*gear*(.35+speed*speed/12.0)
	var space := get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	var clear := safe and space.intersect_shape(query,1).is_empty() and fractions.size()==2 and fractions[0]>=1.0
	var rise: float = float(target.p.y)-global_position.y
	if not clear and safe and rise>.04 and rise<.23:
		query.transform.origin += Vector3.UP*rise
		fractions = space.cast_motion(query)
		if space.intersect_shape(query,1).is_empty() and fractions.size()==2 and fractions[0]>=1.0:
			move_and_collide(Vector3.UP*rise)
			clear = true
	blocked = not clear
	var desired := float(gear)*minf(2.8,maxf(.7,offset.length()*2.0)) if clear else 0.0
	if gear>0 and junction_wait: desired = minf(desired,sqrt(7.0*maxf(0.0,junction_gap-.4)))
	speed = move_toward(speed,desired,delta*(3.0 if clear else 12.0))
	if global_position.distance_to(_path_anchor)>.6:
		_path_anchor = global_position
		_path_stall = 0.0
	else: _path_stall += delta
	if _path_stall>2.5:
		recovery_path.clear()
		_no_progress_seconds = 5.0
		_failed_searches += 1
		_search_retry = .25

func _try_bypass() -> bool:
	if not super._try_bypass(): return false
	if absf(speed) < .3 and _rear_clear():
		# Braking can leave the long M8 too close to turn its full hull.
		# Make room physically, only with a clear rear corridor.
		backoff_time = 2.4
	return true

func _rear_clear() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.transform = Transform3D(global_basis, to_global(shape.position))
	query.motion = global_basis.z * 4.2
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	var fractions := space.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 1.0
func _ready() -> void:
	super._ready()
	remove_from_group("drivable")
	visual.queue_free()
	wheels.clear()
	steer_pivots.clear()
	model = preload("res://assets/gameplay/MaciotaM8SedanModel.gd").new()
	add_child(model)
	visual = model
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var relative: Transform3D = model.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = relative * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	shape.shape = BoxShape3D.new()
	shape.shape.size = bounds.size
	shape.position = bounds.get_center()
	half_width = maxf(absf(bounds.position.x), absf(bounds.end.x))
	half_length = maxf(absf(bounds.position.z), absf(bounds.end.z))
	# Match the native vehicle's floor clearance: the full visual hull includes
	# the tyres touching the road. Using it for horizontal clearance queries
	# reports the supporting pavement as an obstacle in every adjacent lane.
	rotation_shape.size = bounds.size - Vector3(0, .15, 0)
	sensor_shape.size = Vector3(bounds.size.x + .07, 1.2, 1)
	external_input = true
	max_forward_speed = 4

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	model.roll(distance_travelled - _last_distance)
	model.steer(steering)
	_last_distance = distance_travelled

func door_point(side: int) -> Vector3:
	return to_global(Vector3(side * (half_width + .62), .04, -.2))

func show_occupants(value: bool) -> void:
	for person in model.occupants: person.visible = value
