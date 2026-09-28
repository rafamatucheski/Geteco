extends RefCounted
## Street portions follow the current directed road graph, including edited roads.
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const DEPOT_ORIGIN := Vector3(-340,0,-80)
static func dock(index: int) -> Vector3:
	return DEPOT_ORIGIN+Vector3(-18+index*18,0,34)

static func append_points(curve: Curve3D, points: PackedVector3Array) -> void:
	for p in points:
		p.y = 0
		if curve.point_count == 0 or curve.get_point_position(curve.point_count-1).distance_to(p) > .05: curve.add_point(p)

static func rounded(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array([points[0]])
	for i in range(1,points.size()-1):
		var radius := minf(5.0,minf(points[i-1].distance_to(points[i]),points[i].distance_to(points[i+1]))*.35)
		var a := points[i].move_toward(points[i-1],radius)
		var b := points[i].move_toward(points[i+1],radius)
		for step in 12:
			var t := float(step)/11
			result.append(a.lerp(points[i],t).lerp(points[i].lerp(b,t),t))
	result.append(points[-1])
	return result

static func journey(graph: RefCounted, start: Vector3, index: int, returning: bool) -> Curve3D:
	var router := ROUTER.new()
	router.configure(graph)
	var street_start := Vector3(-342.25,0,0) if returning else Vector3(240,0,223.1)
	var street_end := Vector3(238,0,226.9) if returning else Vector3(-337.75,0,-2)
	# Use Dock Street instead of sending long vehicles into the tight quay
	# frontage. This is still graph routing, not a straight-line shortcut.
	var via := Vector3(130,0,139.4 if returning else 135.6)
	var street := Curve3D.new()
	var heading := Vector3.BACK if returning else Vector3.LEFT
	var cursor := street_start
	# Memorial South avoids the edited bus tube on Market Street. The police
	# apron clearance below keeps this wider chassis off its raised gutter.
	var checkpoints := [via,street_end] if returning else [via,Vector3(-20,0,140.4),street_end]
	for target in checkpoints:
		var plan := router.plan(cursor,target,heading)
		if not plan.get("ok",false) or float(plan.get("end_gap",INF)) > 8: return null
		var segment: Curve3D = plan.curve
		append_points(street,segment.get_baked_points())
		cursor = street.get_point_position(street.point_count-1)
		heading = cursor-street.get_point_position(street.point_count-2)
	var curve := Curve3D.new()
	curve.bake_interval = .25
	var first := street.get_point_position(0)
	var last := street.get_point_position(street.point_count-1)
	if returning:
		append_points(curve,rounded(PackedVector3Array([start,DEPOT_ORIGIN+Vector3(36,0,34),DEPOT_ORIGIN+Vector3(39,0,50),DEPOT_ORIGIN+Vector3(-3,0,64),DEPOT_ORIGIN+Vector3(-3,0,78),first])))
	else:
		append_points(curve,rounded(PackedVector3Array([start,Vector3(355,0,start.z),Vector3(359,0,216),Vector3(355,0,223.1),first])))
	var street_points := street.get_baked_points()
	if not returning:
		for i in street_points.size():
			var p := street_points[i]
			if p.x > 54 and p.x < 86 and p.z > 135 and p.z < 137:
				# Ramp ends at z134.7; the 2.72m truck needs more clearance
				# than the graph's default inner lane offers. Stay on asphalt.
				var clearance := smoothstep(54.0,61.0,p.x)*(1.0-smoothstep(77.0,86.0,p.x))
				street_points[i].z += .65*clearance
	append_points(curve,street_points)
	if returning:
		var stop := Vector3((4140+590*index+85)/16.0-6+74.0/4.46/16.0,0,208.825)
		append_points(curve,rounded(PackedVector3Array([last,Vector3(243,0,226.9),Vector3(243,0,208.825),stop])))
	else:
		append_points(curve,rounded(PackedVector3Array([last,DEPOT_ORIGIN+Vector3(0,0,64),DEPOT_ORIGIN+Vector3(-37,0,56),DEPOT_ORIGIN+Vector3(-37,0,34),dock(index)])))
	curve.set_meta("traffic_open",true)
	curve.set_meta("port_work_route",true)
	return curve
