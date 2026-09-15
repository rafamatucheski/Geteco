extends RefCounted
## A temporary, swept lane departure and merge. The road router retains the
## original destination; traffic is never removed, shoved or teleported.
const ROUTE := preload("res://world/shared/traffic/EmergencyRoadManeuver.gd")
var route: RefCounted
var lane: Path2D
var retry := 0.0
var stalled := 0.0
var candidate := 0
var offsets := [-65.0,65.0,-95.0,95.0]
var blocker: WeakRef
var state := "idle"
var completed := 0
var horn_clock := 0.0
var joining := false
var join_option := 0

func reset() -> void:
	route = null
	lane = null
	blocker = null
	state = "idle"
	retry = 0
	stalled = 0
	candidate = 0
	joining = false

func tick(unit: CharacterBody2D, delta: float) -> bool:
	if state == "idle" and unit.get("is_heading_to_cemetery") == true and unit.global_position.distance_to(unit._cemetery_target_position)<330:
		return false # Do not start a passing maneuver beyond the funeral stop.
	if not unit.has_emergency_priority() and not (unit.get("type") == 3 and unit.get("is_heading_to_cemetery") == true):
		if state == "idle": return false
		# Finish an already committed merge even if the siren stops midway.
	retry = maxf(0,retry-delta)
	horn_clock = maxf(0,horn_clock-delta)
	if state == "idle":
		if retry > 0: return false
		retry = .5
		if not unit._ambulance_approach.trajectory.is_empty(): return false
		if _join_lane(unit): return true
		var obstacle := _obstacle(unit)
		if obstacle == null: return false
		if horn_clock <= 0:
			horn_clock = 3
			var horn := unit.get_node_or_null("PassageHorn") as AudioStreamPlayer2D
			if horn == null:
				horn = AudioStreamPlayer2D.new()
				horn.name = "PassageHorn"
				horn.stream = ProceduralAudio.get_horn_stream()
				horn.bus = "SFX"
				horn.volume_db = -15
				horn.max_distance = 700
				unit.add_child(horn)
			horn.play()
		lane = _lane(unit)
		if lane == null: return false
		blocker = weakref(obstacle)
		candidate = 0
		if not _plan(unit): return false
	if state == "planning":
		unit.current_speed = 0
		unit.velocity = Vector2.ZERO
		route.advance_plan()
		if route.pending: return true
		if not route.valid:
			if joining:
				reset()
				retry = .5
				return false
			candidate += 1
			if candidate < offsets.size() and _plan(unit): return true
			state = "idle"
			retry = .8
			unit.set_meta("emergency_passage_state","waiting_for_space")
			return false
		state = "passing"
		unit.set_meta("emergency_passage_state",state)
	if state == "passing":
		unit.is_reversing = false
		unit.stuck_despawn_timer = 0
		unit.current_speed = move_toward(unit.current_speed,100,120*delta)
		var next: Transform2D = route.next(minf(4,unit.current_speed*delta))
		if not route.clear(unit.global_transform,next) or not unit._ambulance_approach._move_to(unit,next.origin,next.get_rotation(),delta):
			unit.current_speed = 0
			unit.velocity = Vector2.ZERO
			stalled += delta
			unit.set_meta("emergency_passage_state","waiting_for_space")
			if stalled > 2:
				reset()
				retry = .5
			return true
		stalled = 0
		if route.finished():
			if not joining: completed += 1
			reset()
			unit._lane_router.reset()
			unit._ambulance_approach.reset()
			unit.set_meta("emergency_passage_state","rejoined")
			retry = .5
		return true
	return false

func _join_lane(unit: CharacterBody2D) -> bool:
	if unit.is_returning_to_base and unit.global_position.distance_to(unit.home_return_position)<250: return false
	var goal: Vector2 = unit.home_return_position if unit.is_returning_to_base else (unit.target.global_position if is_instance_valid(unit.target) else unit.global_position)
	if unit.get("is_heading_to_cemetery") == true: goal = unit._cemetery_target_position
	var best := INF
	var selected: Path2D
	var offset := 0.0
	for node in unit.get_tree().get_nodes_in_group("unified_traffic_lane"):
		var path := node as Path2D
		if path == null or not path.can_process() or path.curve == null or path.get_meta("mountain_traffic",false): continue
		var at := path.curve.get_closest_offset(path.to_local(unit.global_position))
		var pose := path.global_transform*path.curve.sample_baked_with_rotation(at,true)
		var distance := pose.origin.distance_to(unit.global_position)
		if distance > 110 or pose.x.dot(unit.global_transform.x)<-.1 or pose.x.dot(unit.global_position.direction_to(goal))<-.2: continue
		var cost := distance+absf(angle_difference(unit.global_rotation,pose.get_rotation()))*15
		if cost < best:
			best = cost
			selected = path
			offset = at
	if selected == null: return false
	var base := selected.global_transform*selected.curve.sample_baked_with_rotation(offset,true)
	if base.origin.distance_to(unit.global_position)<8 and absf(angle_difference(unit.global_rotation,base.get_rotation()))<.2: return false
	var lookahead: float = [140.0,200.0,260.0][join_option%3]
	join_option += 1
	if offset+lookahead > selected.curve.get_baked_length()-50: return false
	var end := selected.global_transform*selected.curve.sample_baked_with_rotation(offset+lookahead,true)
	var poses: Array[Transform2D] = ROUTE.connection(unit.global_transform,end,70)
	if poses.is_empty(): return false
	lane = selected
	route = ROUTE.new()
	route.configure(unit,lane,poses)
	joining = true
	state = "planning"
	return true

func _plan(unit: CharacterBody2D) -> bool:
	var other: Node2D = blocker.get_ref() if blocker else null
	if not is_instance_valid(other): return false
	var offset := lane.curve.get_closest_offset(lane.to_local(unit.global_position))
	var on_lane := lane.global_transform*lane.curve.sample_baked_with_rotation(offset,true)
	var lateral := (on_lane.affine_inverse()*unit.global_position).y
	if absf(angle_difference(unit.global_rotation,on_lane.get_rotation())) > .08: return false
	var side: float = offsets[candidate]
	var entry := maxf(150,sqrt(absf(side-lateral)*6.5*70))
	var exit_length := maxf(150,sqrt(absf(side)*6.5*70))
	var other_offset := lane.curve.get_closest_offset(lane.to_local(other.global_position))
	var clear_offset := maxf(offset+entry,other_offset+180)
	# Rejoining behind the next queued car is still a blocked maneuver. Keep
	# the passing corridor until the nearby queue's last complete body clears.
	for actor in unit.get_tree().get_nodes_in_group("vehicle"):
		if actor == unit or not actor is Node2D or not actor.is_visible_in_tree(): continue
		var at := lane.curve.get_closest_offset(lane.to_local(actor.global_position))
		if at < offset or at > offset+650: continue
		var base := lane.global_transform*lane.curve.sample_baked_with_rotation(at,true)
		if absf((base.affine_inverse()*actor.global_position).y)>85: continue
		clear_offset = maxf(clear_offset,at+180)
	if clear_offset+exit_length+60 > lane.curve.get_baked_length(): return false
	var poses: Array[Transform2D] = ROUTE.lane_change(lane,offset,entry,lateral,side,70)
	if poses.is_empty(): return false
	var middle: Array[Transform2D] = ROUTE.lane_change(lane,offset+entry,maxf(2,clear_offset-offset-entry),side,side,70)
	var ending: Array[Transform2D] = ROUTE.lane_change(lane,clear_offset,exit_length,side,0,70)
	if middle.is_empty() or ending.is_empty(): return false
	poses.append_array(middle.slice(1))
	poses.append_array(ending.slice(1))
	route = ROUTE.new()
	route.configure(unit,lane,poses)
	state = "planning"
	return true

func _lane(unit: Node2D) -> Path2D:
	var nearest := 90.0
	var best: Path2D
	for node in unit.get_tree().get_nodes_in_group("unified_traffic_lane"):
		var path := node as Path2D
		if path == null or not path.can_process() or path.curve == null or path.get_meta("mountain_traffic",false): continue
		var offset := path.curve.get_closest_offset(path.to_local(unit.global_position))
		var pose := path.global_transform*path.curve.sample_baked_with_rotation(offset,true)
		if pose.x.dot(unit.global_transform.x)<.9: continue
		var distance := unit.global_position.distance_to(pose.origin)
		if distance < nearest:
			nearest = distance
			best = path
	return best

func _obstacle(unit: CharacterBody2D) -> Node2D:
	var query := PhysicsShapeQueryParameters2D.new()
	var hull: CollisionShape2D = unit.get_node("CollisionShape2D")
	query.shape = hull.shape
	query.transform = hull.global_transform
	query.motion = unit.global_transform.x*340
	query.collision_mask = 2
	query.exclude = [unit.get_rid()]
	query.margin = 4
	var space := unit.get_world_2d().direct_space_state
	var fraction: float = space.cast_motion(query)[0]
	if fraction >= 1: return null
	query.transform.origin += query.motion*minf(1,fraction+.015)
	query.motion = Vector2.ZERO
	for hit in space.intersect_shape(query,4):
		var actor := hit.collider as Node2D
		if actor != null and actor.global_position.distance_to(unit.global_position)>30: return actor
	return null
