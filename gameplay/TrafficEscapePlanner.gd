extends RefCounted
## Emergency detour for frightened/stalled traffic. Keep solid/vehicle collision;
## pedestrians are handled by the normal impact system rather than the planner.
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const PORT := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
static var _frame := -1
static var _plans := 0

static func plan(car: CharacterBody3D, source: Curve3D) -> Curve3D:
	car.set_meta("traffic_escape_plan_failure","no_route")
	if source==null: return null
	var frame := Engine.get_physics_frames()
	if frame!=_frame: _frame=frame; _plans=0
	if _plans>=1:
		car.set_meta("traffic_escape_plan_failure","deferred")
		return null
	_plans+=1
	var origin := source.get_closest_offset(car.global_position)
	if source.get_baked_length()<15 or (source.get_meta("traffic_open",false) and source.get_baked_length()-origin<25):
		# Yield/turnaround curves can be only a few metres long. Escape is not
		# constrained by that temporary trip; first recover a usable road route.
		var world:=car.get_parent()
		var production: Variant=world.get("production") if is_instance_valid(world) else null
		var replacement: Curve3D
		if is_instance_valid(production): replacement=production.ambient_traffic_routes.route_near(car.global_position,0,-car.global_basis.z)
		if replacement!=null and replacement.get_baked_length()-replacement.get_closest_offset(car.global_position)>25:
			source=replacement
		else:
			source=Curve3D.new()
			source.add_point(car.global_position)
			source.add_point(car.global_position-car.global_basis.z*55)
			source.set_meta("traffic_open",true)
			source.set_meta("traffic_escape_free",true)
	origin = source.get_closest_offset(car.global_position)
	var open: bool=source.get_meta("traffic_open",false)
	var available := source.get_baked_length()-origin-2 if open else 55.0
	if available<15: return null
	var width := 8.0
	var nearest := INF
	for section in source.get_meta("lane_sections",[]):
		var distance: float=Geometry3D.get_closest_point_to_segment(car.global_position,section.a,section.b).distance_squared_to(car.global_position)
		if distance<nearest: nearest=distance; width=float(section.width)
	var shifts: Array[float]=[-width*.5,width*.5,-width*.5-2.5,width*.5+2.5]
	for shift in shifts:
		var ramp := maxf(8.0,absf(shift)*2.2)
		var distance := minf(available,maxf(32.0,ramp*2+10.0))
		if distance<ramp*2+3: continue
		var curve := Curve3D.new()
		curve.bake_interval=.2
		curve.up_vector_enabled=false
		var base := _point(source,origin)
		var initial := car.global_position-base
		for i in range(ceili(distance)+1):
			var travelled := minf(float(i),distance)
			var tangent := _point(source,origin+travelled+.4)-_point(source,origin+travelled-.4)
			tangent.y=0
			if tangent.length_squared()<.001: tangent=-car.global_basis.z
			var blend := smoothstep(0.0,ramp,travelled)*(1-smoothstep(distance-ramp,distance,travelled))
			curve.add_point(_point(source,origin+travelled)+initial*(1-smoothstep(0.0,ramp,travelled))+tangent.normalized().cross(Vector3.UP)*shift*blend)
		var forward := curve.sample_baked(1,true)-car.global_position
		forward.y=0
		if forward.normalized().dot(-car.global_basis.z)<.65: continue
		if not PORT.route_is_ambient_safe(curve) or not _clear_and_ground(car,curve): continue
		curve.set_meta("traffic_escape_until",curve.get_baked_length()-2.0)
		# Carry the rest of the original trip; no forced merge into an occupied lane.
		var cursor := origin+distance+1
		var end := source.get_baked_length() if open else origin+distance+50
		while cursor<end:
			curve.add_point(_point(source,cursor))
			cursor+=2
		curve.add_point(_point(source,end))
		curve.set_meta("traffic_open",true)
		for key in ["lane_sections","lane_index","traffic_nodes","traffic_source_ids"]:
			if source.has_meta(key): curve.set_meta(key,source.get_meta(key))
		curve.set_meta("traffic_escape_shift",shift)
		if source.get_meta("traffic_escape_free",false): curve.set_meta("traffic_escape_free",true)
		car.set_meta("traffic_escape_plan_failure","")
		return curve
	return null

static func _point(source: Curve3D, distance: float) -> Vector3:
	var length := source.get_baked_length()
	return source.sample_baked(clampf(distance,0,length) if source.get_meta("traffic_open",false) else fposmod(distance,length),true)

static func _clear_and_ground(car: CharacterBody3D, curve: Curve3D) -> bool:
	var space := car.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=car.rotation_shape
	query.exclude=[car.get_rid()]
	for i in curve.point_count:
		var point := curve.get_point_position(i)
		var ground: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.5,point-Vector3.UP*2,1))
		if ground.is_empty() or absf(ground.position.y-point.y)>.4:
			car.set_meta("traffic_escape_plan_failure","ground:"+str(i))
			return false
		point.y=ground.position.y+.04
		curve.set_point_position(i,point)
	# Continuous hull sweeps bridge the samples; retain trees, walls and cars.
	for i in range(curve.point_count-1):
		var point := curve.get_point_position(i)
		var next := curve.get_point_position(i+1)
		var direction := next-point
		var yaw := atan2(-direction.x,-direction.z)
		query.transform=Transform3D(Basis(Vector3.UP,yaw),point+Vector3.UP*car.shape.position.y)
		query.motion=Vector3.ZERO
		query.collision_mask=5
		var hits: Array=space.intersect_shape(query,1)
		if not hits.is_empty():
			car.set_meta("traffic_escape_plan_failure","hull:"+str(i)+":"+str(hits[0].collider))
			return false
		query.motion=direction
		if space.cast_motion(query)[0]<1.0:
			car.set_meta("traffic_escape_plan_failure","sweep:"+str(i))
			return false
		query.motion=Vector3.ZERO
		query.collision_mask=2
		for hit in space.intersect_shape(query,8):
			if PROTECTION.is_protected(hit.collider): return false
	return true
