extends RefCounted
const RULES := preload("res://cars/traffic/TrafficEmergencyYield.gd")
const ROUTE := preload("res://cars/traffic/EmergencyRoadManeuver.gd")
var state := "idle"
var probe := 0.0
var retry := 0.0
var responder: WeakRef
var route: RefCounted
var merging := false
var side_index := 0
var offsets: Array[float] = []

func tick(car: CharacterBody2D, lane: Path2D, follow: PathFollow2D, delta: float) -> bool:
	if car.is_broken or car.is_driven_by_player or car._detached_from_lane:
		state = "idle"
		route = null
		responder = null
		car._emergency_yield_active = false
		return false
	if car.get_traffic_bodies().size()>1: return false
	probe -= delta
	retry = maxf(0,retry-delta)
	if probe <= 0:
		probe = .25
		var incoming := RULES.approaching(car,RULES.responders(car.get_tree()))
		if incoming: responder = weakref(incoming)
	var unit: Node2D = responder.get_ref() if responder else null
	var waiting := is_instance_valid(unit) and RULES.has_priority(unit)
	if waiting:
		var ahead := (car.global_position-unit.global_position).dot(unit.global_transform.x)
		waiting = ahead > -150 and car.global_position.distance_to(unit.global_position)<800
	car._emergency_yield_active = waiting or state != "idle"
	if state == "idle":
		if not waiting or retry > 0: return false
		if lane.is_in_group("unified_lane_connector") or lane.get_meta("mountain_traffic",false): return false
		var zone: Dictionary = car._traffic_control_zone_motion(lane,follow)
		if zone.get("must_clear_rail_crossing",false) or car._last_lane_motion_contract.get("reservation_granted",false) or car._last_lane_motion_contract.get("controlled",false): return false
		if not lane.has_meta("traffic_road_width"): return false
		# The city's sidewalk is explicitly authored, not an arbitrary permission
		# to drive across land. Both sides and the complete curve are checked.
		var edge := float(lane.get_meta("traffic_road_width"))*.5-absf(float(lane.get_meta("traffic_lane_offset",0)))
		var sidewalk := float(lane.get_meta("traffic_sidewalk_width",0))
		# Reserve the corner radius, not just half the width: while steering,
		# the nose swings farther outward than the final parallel parked body.
		var turn_clearance: float = car.collision.shape.get_rect().size.length()*.5+4
		var right := edge+sidewalk-turn_clearance
		var left := -float(lane.get_meta("traffic_road_width"))*.5-absf(float(lane.get_meta("traffic_lane_offset",0)))-sidewalk+turn_clearance
		offsets.assign([right,left])
		side_index = 0
		merging = false
		_begin(car,lane,follow)
	if state == "hold":
		car._lane_motion_speed = 0
		car.velocity = Vector2.ZERO
		if not waiting and retry <= 0:
			merging = true
			offsets.assign([0.0])
			side_index = 0
			_begin(car,lane,follow)
		return true
	if state == "planning":
		car._lane_motion_speed = 0
		car.velocity = Vector2.ZERO
		route.advance_plan()
		if route.pending: return true
		if not route.valid:
			side_index += 1
			if side_index < offsets.size(): _begin(car,lane,follow)
			else:
				state = "hold" if merging else "idle"
				retry = 1.0
				car.set_meta("emergency_yield_state","waiting_for_space")
			return merging
		state = "merge" if merging else "pull_over"
		car.set_meta("emergency_yield_state",state)
		if not merging: car.honk_horn()
	if state in ["pull_over","merge"]:
		var speed := move_toward(car._lane_motion_speed,45.0,65*delta)
		var next: Transform2D = route.next(minf(speed*delta,4))
		if not route.clear(car.global_transform,next):
			car._lane_motion_speed = 0
			car.velocity = Vector2.ZERO
			car.set_meta("emergency_yield_state","waiting_for_space")
			return true
		var previous: Vector2 = car.global_position
		car.move_and_collide(next.origin-previous)
		if car.global_position.distance_to(next.origin) > .01: return true
		# Update the cursor on the SAME lane while preserving the physically
		# reached pose. The later merge starts here, never at an old lane origin.
		follow.progress = lane.curve.get_closest_offset(lane.to_local(next.origin))
		car.global_transform = next
		car.velocity = (next.origin-previous)/maxf(.001,delta)
		car._lane_motion_speed = car.velocity.length()
		car.is_moving_on_lane = car._lane_motion_speed > .1
		if route.finished():
			state = "idle" if merging else "hold"
			car._emergency_yield_active = not merging
			car.set_meta("emergency_yield_state","resumed" if merging else "holding")
			if merging:
				car.rotation = 0
				car.position = Vector2.ZERO
				responder = null
				retry = .5
		return true
	return false

func _begin(car: CharacterBody2D, lane: Path2D, follow: PathFollow2D) -> void:
	var lateral: float = offsets[side_index]-car.position.y
	var length := maxf(95,sqrt(absf(lateral)*6.5*45))
	var zone: Dictionary = car._traffic_control_zone_motion(lane,follow)
	if float(zone.get("allowed_advance",INF)) < length+car.target_length:
		state = "hold" if merging else "idle"
		retry = 1
		return
	var poses: Array[Transform2D] = ROUTE.lane_change(lane,follow.progress,length,car.position.y,offsets[side_index],45)
	if poses.is_empty() or follow.progress+length+car.target_length > lane.curve.get_baked_length():
		state = "hold" if merging else "idle"
		retry = 1
		return
	route = ROUTE.new()
	route.configure(car,lane,poses)
	state = "planning"
