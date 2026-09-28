extends RefCounted
## V1 apron geometry, converted once from authored floor pixels to native metres.
static func point(x: float, z: float) -> Vector3:
	return Vector3((1700+x)/16.0,.12,(1060+z)/16.0)
static func arc(curve: Curve3D, center: Vector2, radius: float, begin: float, end: float) -> void:
	for i in range(1,33):
		var p := center+Vector2.from_angle(lerpf(begin,end,float(i)/32))*radius
		curve.add_point(point(p.x,p.y))
static func apron(kind: String, bay: int) -> Curve3D:
	var x := -141.0+100.0*bay
	var c := Curve3D.new()
	c.bake_interval = .08
	match kind:
		"reversing":
			c.add_point(point(x,-88)); c.add_point(point(x,-10))
			arc(c,Vector2(x-30,-10),30,0,PI/2)
		"departing":
			c.add_point(point(x-30,20)); c.add_point(point(205,20))
			arc(c,Vector2(205,65),45,-PI/2,0)
			# Native traffic drives east on the southern lane (V1 used the
			# opposite offset). Cross the street before turning into that lane.
			c.add_point(point(250,177)); arc(c,Vector2(293,177),43,PI,PI/2)
		"arriving":
			c.add_point(point(-323,220)); c.add_point(point(305,220))
			arc(c,Vector2(305,165),55,PI/2,0)
			c.add_point(point(360,70)); arc(c,Vector2(305,70),55,0,-PI/2)
			c.add_point(point(x+45,15)); arc(c,Vector2(x+45,-30),45,PI/2,PI)
			c.add_point(point(x,-88))
	c.set_meta("traffic_open",true)
	return c

static func street(graph: RefCounted) -> Curve3D:
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(graph)
	var c := Curve3D.new()
	c.bake_interval = .25
	var stops := [point(293,220),point(478,-583),point(-378,-583),point(-323,220)]
	var heading := Vector3.RIGHT
	for i in stops.size()-1:
		var plan: Dictionary = router.plan(stops[i],stops[i+1],heading)
		if not plan.get("ok",false) or float(plan.get("end_gap",INF)) > 10: return null
		var segment: Curve3D = plan.curve
		for p in segment.get_baked_points():
			p.y = .12
			if c.point_count == 0 or c.get_point_position(c.point_count-1).distance_to(p) > .05: c.add_point(p)
		if segment.point_count > 1: heading = segment.get_point_position(segment.point_count-1)-segment.get_point_position(segment.point_count-2)
	c.set_meta("traffic_open",true)
	return c
