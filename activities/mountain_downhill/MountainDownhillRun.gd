extends RefCounted
## Every entrant uses the same physical gate crossings and finish timestamps.
static func start(vehicle_id: String, point: Vector3, course) -> Dictionary:
	return {"vehicle_id":vehicle_id,"previous":point,"start":point,"checkpoint":0,"progress":course.nearest_offset(point),"outside":0.0,"elapsed":0.0,"finish":INF,"failure":""}

static func tick(run: Dictionary, delta: float, point: Vector3, vehicle_id: String, alive: bool, hold: bool, course) -> void:
	if not str(run.failure).is_empty() or is_finite(float(run.finish)): return
	if not alive: run.failure = "race_vehicle_broken"; return
	if vehicle_id != run.vehicle_id: run.failure = "race_vehicle_left"; return
	if not is_finite(delta) or delta <= 0 or not point.is_finite(): run.failure = "race_interrupted"; return
	var previous: Vector3 = run.previous
	if hold:
		if point.distance_to(run.start) > 2.0: run.failure = "race_false_start"
		run.previous = point
		return
	if point.distance_to(previous) > 1.5+delta*65.0: run.failure = "race_interrupted"; return
	var frame_start := float(run.elapsed)
	run.elapsed = frame_start+delta
	if run.elapsed > course.TIME_LIMIT: run.failure = "race_timeout"; return
	var offset: float = course.nearest_offset(point)
	var route_point: Vector3 = course.point(offset)
	var offroad: bool = point.distance_to(route_point) > course.ROAD_HALF_WIDTH+1.1
	run.outside = float(run.outside)+delta if offroad else 0.0
	if float(run.outside) > course.OFFROAD_GRACE: run.failure = "race_offtrack"; return
	var index := int(run.checkpoint)
	if index < course.gate_offsets.size():
		var center: Vector3 = course.gate(index)
		var forward: Vector3 = course.forward(index)
		var before := (previous-center).dot(forward)
		var after := (point-center).dot(forward)
		if before <= 0.0 and after > 0.0:
			var fraction := clampf(-before/(after-before),0.0,1.0)
			var crossing := previous.lerp(point,fraction)
			var lateral := absf((crossing-center).dot(forward.cross(Vector3.UP).normalized()))
			if lateral <= course.HALF_GATE and absf(crossing.y-center.y) < 1.5:
				run.checkpoint = index+1
				if int(run.checkpoint) == course.gate_offsets.size(): run.finish = frame_start+delta*fraction
	var upper: float = course.gate_offsets[mini(int(run.checkpoint),course.gate_offsets.size()-1)]
	var lower: float = course.gate_offsets[int(run.checkpoint)-1] if int(run.checkpoint)>0 else 0.0
	run.progress = clampf(offset,lower,upper)
	run.previous = point

static func ahead(a: Dictionary, b: Dictionary) -> bool:
	var ar: Dictionary = a.run
	var br: Dictionary = b.run
	if is_finite(float(ar.finish)) or is_finite(float(br.finish)):
		if float(ar.finish) != float(br.finish): return float(ar.finish) < float(br.finish)
	if str(ar.failure).is_empty() != str(br.failure).is_empty(): return str(ar.failure).is_empty()
	if int(ar.checkpoint) != int(br.checkpoint): return int(ar.checkpoint)>int(br.checkpoint)
	if not is_equal_approx(float(ar.progress),float(br.progress)): return float(ar.progress)>float(br.progress)
	return int(a.index)<int(b.index)
