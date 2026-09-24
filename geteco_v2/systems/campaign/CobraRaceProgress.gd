extends RefCounted
## Native XZ equivalent of CobraCampaignController._prepare_race/_tick_race.
const UNIT := 1.0/16.0
const CENTER := Vector2(7700,1700)*UNIT
const ROAD_RADIUS := 300.0*UNIT
const LANE_RADIUS := 321.0*UNIT
static func start(vehicle_id: String, point: Vector2) -> Dictionary:
	return {"vehicle_id":vehicle_id,"countdown":3.0,"progress":0.0,"previous_angle":PI,"exit_angle":PI,"was_on_track":true,"initialized":false,"previous":[point.x,point.y],"start":[point.x,point.y],"checkpoint":0}
static func tick(run: Dictionary, delta: float, point: Vector2, vehicle_id: String, alive: bool, elapsed: float, outside: float) -> Dictionary:
	var result := {"failure":"","elapsed":elapsed,"outside":outside,"crossed":-1,"countdown_changed":false}
	if not alive: result.failure="race_vehicle_broken"; return result
	if vehicle_id!=run.vehicle_id: result.failure="race_vehicle_left"; return result
	if run.countdown>0:
		if point.distance_to(Vector2(run.start[0],run.start[1]))>18.0*UNIT:
			result.failure="race_false_start"
			return result
		var old_second := ceili(float(run.countdown))
		run.countdown=maxf(0,float(run.countdown)-delta)
		result.countdown_changed=old_second!=ceili(float(run.countdown))
		if run.countdown==0:
			run.previous_angle=(point-CENTER).angle()
			run.progress=wrapf(float(run.previous_angle)-PI,-PI,PI)
			run.previous=[point.x,point.y]
			run.initialized=true
		return result
	result.elapsed=elapsed+delta
	if run.initialized and point.distance_to(Vector2(run.previous[0],run.previous[1]))>maxf(80.0,delta*900.0)*UNIT:
		result.failure="race_interrupted"
		return result
	run.previous=[point.x,point.y]
	run.initialized=true
	var distance := point.distance_to(CENTER)
	var on_track := absf(distance-ROAD_RADIUS)<=60.0*UNIT
	var angle := (point-CENTER).angle()
	if on_track and run.was_on_track:
		run.progress=float(run.progress)+wrapf(angle-float(run.previous_angle),-PI,PI)
	elif on_track:
		var rejoin := wrapf(angle-float(run.exit_angle),-PI,PI)
		if absf(rejoin)>.3: result.failure="race_shortcut"; return result
		run.progress=float(run.progress)+rejoin
	else:
		if run.was_on_track: run.exit_angle=run.previous_angle
		result.outside=outside+delta
		if result.outside>=4.0 or distance<ROAD_RADIUS*.5: result.failure="race_offtrack"; return result
	if on_track: result.outside=0.0
	run.previous_angle=angle
	run.was_on_track=on_track
	if result.elapsed>=100: result.failure="race_timeout"; return result
	var checkpoint: int=int(run.checkpoint)
	if checkpoint<4:
		var required := float(checkpoint+1)*PI*.5
		var gate := CENTER+Vector2.from_angle(PI+required)*LANE_RADIUS
		if on_track and run.progress>=required and point.distance_to(gate)<85.0*UNIT:
			result.crossed=checkpoint
			run.checkpoint=checkpoint+1
	return result
static func validate(run: Variant) -> bool:
	if not run is Dictionary: return false
	if run.is_empty(): return true
	if not run.get("vehicle_id") is String or run.vehicle_id.is_empty() or run.vehicle_id.length()>128: return false
	for key in ["countdown","progress","previous_angle","exit_angle","checkpoint"]:
		if typeof(run.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(run[key])): return false
	if run.countdown<0 or run.countdown>3 or run.checkpoint<0 or run.checkpoint>4 or run.checkpoint!=floorf(run.checkpoint) or absf(run.progress)>100000: return false
	if not run.get("was_on_track") is bool or not run.get("initialized") is bool: return false
	for key in ["start","previous"]:
		if not run.get(key) is Array or run[key].size()!=2: return false
		for value in run[key]:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>10000: return false
	return true
