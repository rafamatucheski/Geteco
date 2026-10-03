extends RefCounted
const COURSE := preload("res://gameplay/urban_v1/CobraRaceCourse.gd")
static func start(vehicle_id: String, point: Vector2) -> Dictionary:
	return {"course_version":COURSE.VERSION,"vehicle_id":vehicle_id,"countdown":3.0,"checkpoint":0,"progress":0.0,"previous":[point.x,point.y],"start":[point.x,point.y],"initialized":false,"place":1,"finished":false}

static func tick(run: Dictionary, delta: float, point: Vector2, vehicle_id: String, alive: bool, elapsed: float, outside: float) -> Dictionary:
	var result := {"failure":"","elapsed":elapsed,"outside":outside,"crossed":-1,"countdown_changed":false}
	if not alive: result.failure="race_vehicle_broken"; return result
	if vehicle_id!=run.vehicle_id: result.failure="race_vehicle_left"; return result
	var previous := Vector2(run.previous[0],run.previous[1])
	if run.countdown>0:
		if point.distance_to(Vector2(run.start[0],run.start[1]))>4.0: result.failure="race_false_start"; return result
		var before := ceili(float(run.countdown))
		run.countdown=maxf(0,float(run.countdown)-delta)
		result.countdown_changed=before!=ceili(float(run.countdown))
		run.previous=[point.x,point.y]
		run.initialized=run.countdown==0
		return result
	if point.distance_to(previous)>maxf(6.0,delta*95.0): result.failure="race_interrupted"; return result
	result.elapsed=elapsed+delta
	if result.elapsed>=COURSE.TIME_LIMIT: result.failure="race_timeout"; return result
	var world_point := Vector3(point.x,0,point.y)
	var curve := COURSE.curve()
	var route_point := curve.sample_baked(curve.get_closest_offset(world_point))
	result.outside=outside+delta if route_point.distance_to(world_point)>50 else 0.0
	if result.outside>=COURSE.OFFROAD_GRACE: result.failure="race_offtrack"; return result
	var gate: int=int(run.checkpoint)
	if gate<4:
		var center3 := COURSE.gate(gate)
		var axis3 := COURSE.forward(gate)
		var center := Vector2(center3.x,center3.z)
		var forward := Vector2(axis3.x,axis3.z)
		var before := (previous-center).dot(forward)
		var after := (point-center).dot(forward)
		# Plano varrido: alta velocidade conta, marcha ré e pular portões não.
		if before<=0 and after>0:
			var crossing := previous.lerp(point,clampf(-before/(after-before),0,1))
			if crossing.distance_to(center)<=COURSE.HALF_GATE:
				result.fraction=clampf(-before/(after-before),0,1)
				run.checkpoint=gate+1
				result.crossed=gate
				run.finished=run.checkpoint==4
	run.progress=COURSE.offset(world_point,int(run.checkpoint))
	run.previous=[point.x,point.y]
	return result

static func validate(run: Dictionary) -> bool:
	if run.get("course_version")!=COURSE.VERSION: return false
	if not run.get("vehicle_id") is String or run.vehicle_id.is_empty() or run.vehicle_id.length()>128: return false
	for key in ["countdown","checkpoint","progress","place"]:
		if typeof(run.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(run[key])): return false
	if run.countdown<0 or run.countdown>3 or run.checkpoint<0 or run.checkpoint>4 or run.checkpoint!=floorf(run.checkpoint): return false
	if run.progress<0 or run.progress>COURSE.curve().get_baked_length()+1 or run.place<1 or run.place>6 or run.place!=floorf(run.place): return false
	if not run.get("initialized") is bool or not run.get("finished") is bool or run.finished!=(run.checkpoint==4): return false
	for key in ["start","previous"]:
		if not run.get(key) is Array or run[key].size()!=2: return false
		for value in run[key]:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>10000: return false
	return true
