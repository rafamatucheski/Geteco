extends RefCounted
## Complete open trips with a physically checked turn, then resume the opposite
## lane. Never teleport, turn inside a junction, or reuse a yield manoeuvre.
var _cursor := 0

func update(production) -> void:
	var cars: Array = production.vehicles
	if cars.is_empty(): return
	# At most one geometric plan per population tick; waiting cars keep braking.
	for step in cars.size():
		_cursor = posmod(_cursor, cars.size())
		var car = cars[_cursor]
		_cursor += 1
		if not production._is_ambient_traffic(car) or not car.traffic or car.health <= 0 or car.controlled: continue
		if car.traffic_escape!=null and (car.traffic_escape.active or car.traffic_escape.retiring): continue
		if car.get_meta("traffic_escape_state","")=="waiting": continue
		if car.route == null or not car.route.get_meta("traffic_open",false): continue
		if car.get_meta("traffic_yield_state", "") != "" or car.bypass_side != 0: continue
		var remaining: float = car.route.get_baked_length()-car.route_distance
		if car.has_meta("ambient_next_route"):
			if remaining < 3.0:
				car.route = car.get_meta("ambient_next_route")
				car.remove_meta("ambient_next_route")
				car.route_distance = car.route.get_closest_offset(car.global_position)
			return
		if remaining > 13.0: continue
		var now := Time.get_ticks_msec()
		if now < int(car.get_meta("ambient_trip_retry",0)): continue
		car.set_meta("ambient_trip_retry", now+2000)
		var graph = production.ambient_traffic_routes
		var lane: int = car.route.get_meta("lane_index",0)
		var heading: Vector3 = -car.global_basis.z
		var following = graph.route_near(car.global_position,lane,heading)
		if following != null:
			var offset: float = following.get_closest_offset(car.global_position)
			if following.get_baked_length()-offset > remaining+15 and production.PORT_POLICY.route_is_ambient_safe(following):
				car.route = following
				car.route_distance = offset
				return
		var turn := turnaround(car,graph)
		if turn.is_empty():
			# An impossible end is a genuine stall, eligible for unseen cleanup.
			if remaining < 2 and absf(car.speed)<.2: car.stuck_time += 2.0
			return
		car.set_meta("ambient_next_route",turn.next)
		car.route = turn.curve
		car.route_distance = 0
		return

func turnaround(car: CharacterBody3D, graph: RefCounted) -> Dictionary:
	var nodes: Array = car.route.get_meta("traffic_nodes",[])
	if nodes.size()<2: return {}
	var end: int = nodes[-1]
	# Only a true two-way terminal, not a route truncated at a live junction.
	if graph.edges[end].size()!=1: return {}
	var edge: Dictionary = graph.edges[end][0]
	if edge.one_way or edge.width < 8.5: return {}
	var forward: Vector3 = graph.vertices[end]-graph.vertices[nodes[-2]]
	forward.y = 0
	forward = forward.normalized()
	if forward.dot(-car.global_basis.z)<.9: return {}
	var right := forward.cross(Vector3.UP)
	var radius: float = edge.width*.25
	var center: Vector3 = car.global_position-right*radius
	var terminal: Vector3 = graph.vertices[end]
	if (terminal-center).dot(forward)<radius+car.half_length+1: return {}
	var curve := Curve3D.new()
	curve.bake_interval = .2
	for i in 25:
		var angle := PI*float(i)/24
		curve.add_point(center+right*(radius*cos(angle))+forward*(radius*sin(angle)))
	var finish := curve.get_point_position(curve.point_count-1)
	var next = graph.route_near(finish,0,-forward)
	if next == null or next.get_baked_length()-next.get_closest_offset(finish)<16: return {}
	# Leave enough tail to merge before the open turn curve brakes at its end.
	curve.add_point(finish-forward*6)
	curve.set_meta("traffic_open",true)
	if not curve_clear(car,curve): return {}
	return {"curve":curve,"next":next}

static func curve_clear(car: CharacterBody3D, curve: Curve3D) -> bool:
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = car.rotation_shape
	query.collision_mask = 7
	query.exclude = [car.get_rid()]
	var length := curve.get_baked_length()
	for i in range(ceili(length)+1):
		var offset := minf(float(i),length)
		var point := curve.sample_baked(offset,true)
		var direction := curve.sample_baked(minf(offset+.3,length),true)-curve.sample_baked(maxf(offset-.3,0),true)
		query.transform = Transform3D(Basis(Vector3.UP,atan2(-direction.x,-direction.z)),point+Vector3.UP*car.shape.position.y)
		if not space.intersect_shape(query,1).is_empty(): return false
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1))
		if ground.is_empty() or absf(ground.position.y-point.y)>.35: return false
	return true
