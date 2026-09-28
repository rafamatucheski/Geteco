extends RefCounted
## Local racing decisions, shared by paid opponents and nearby practice riders.
## Planning runs at 8 Hz; steering/inputs interpolate each physics tick. No
## position writes, speed writes, global scans, random crashes or race rewards.
const PLAN_INTERVAL := 0.125
const MAX_NEIGHBORS := 6

static func drive(row: Dictionary, track, nearby: Array, base_pace: float, delta: float) -> void:
	var bike: Variant = row.get("bike")
	if not is_instance_valid(bike) or not is_finite(delta) or delta <= 0.0: return
	if bike.crash_state != "riding":
		bike.drive(0.0, 0.0, true)
		if row.has("pilot_state"): row.pilot_state.clock = 0.0
		return
	if not row.has("pilot_state"): row.pilot_state = _initial_state(row, bike)
	var state: Dictionary = row.pilot_state
	var dt := minf(delta, 0.1)
	state.time = float(state.time) + dt
	state.clock = float(state.clock) - dt
	state.pass_hold = maxf(0.0, float(state.pass_hold) - dt)
	state.cooldown = maxf(0.0, float(state.cooldown) - dt)
	var traveled: Vector3 = bike.global_position - Vector3(state.last_position)
	if traveled.length_squared() > 16.0: state.clock = 0.0
	else: state.distance = float(state.distance) + maxf(0.0, traveled.dot(Vector3(state.road_forward)))
	state.last_position = bike.global_position
	if float(state.clock) <= 0.0:
		_plan(row, bike, track, nearby, base_pace)
		state.clock = PLAN_INTERVAL
	state.lane = move_toward(float(state.lane), float(state.lane_target), dt * (1.75 if int(state.pass_side) != 0 else 0.95))
	var lookahead := clampf(2.4 + absf(bike.speed) * 0.35, 4.0, 8.4)
	var goal: Vector3 = track.pose(float(state.distance) + lookahead, float(state.lane)).origin
	var toward: Vector3 = goal - bike.global_position
	var desired := atan2(-toward.x, -toward.z)
	var error := angle_difference(bike.rotation.y, desired)
	var steer := clampf(error * 2.25, -1.0, 1.0)
	state.steering = move_toward(float(state.steering), steer, dt * 5.0)
	var effective_max := maxf(0.1, bike.max_speed * lerpf(1.0, 0.82, bike.wetness))
	var target := minf(float(state.target_speed), effective_max)
	# Heading corrections also shed speed, preventing an overtaking lane change
	# from carrying a rider straight across the next hairpin.
	target *= lerpf(1.0, 0.62, smoothstep(0.60, 1.15, absf(error)))
	var overspeed: float = bike.speed - target
	var braking: bool = bool(state.emergency) or overspeed > (0.25 if bool(state.braking) else 0.9)
	state.braking = braking
	var throttle := 0.0
	if not braking:
		if bike.speed < target - 0.40: throttle = 1.0
		elif overspeed < 0.10: throttle = clampf(target / effective_max, 0.0, 1.0)
	bike.drive(throttle, float(state.steering), braking)
	state.action = "brake" if braking else ("accelerate" if throttle > 0.98 else ("coast" if throttle < 0.05 else "hold"))
	state.brake_frames = int(state.brake_frames) + (1 if braking else 0)
	state.accelerate_frames = int(state.accelerate_frames) + (1 if throttle > 0.98 else 0)
	state.min_target_speed = minf(float(state.min_target_speed), target)
	state.max_target_speed = maxf(float(state.max_target_speed), target)
	state.lane_min = minf(float(state.lane_min), float(state.lane))
	state.lane_max = maxf(float(state.lane_max), float(state.lane))
	# Existing recovery code can use the current planned lane without knowing
	# anything about the decision state.
	row.lane = float(state.lane)

static func _initial_state(row: Dictionary, bike) -> Dictionary:
	var seed_value := int(row.get("pilot_seed", 0))
	if not row.has("pilot_seed"):
		# Rider identity and authored grid lane are stable across process runs.
		seed_value = 5381
		for character in str(bike.rider_name).to_utf8_buffer(): seed_value = (seed_value * 33 + int(character)) % 65521
		seed_value += int(round(float(row.get("lane", 0.0)) * 37.0))
	var unit := float(posmod(seed_value, 997)) / 996.0
	var lane := float(row.get("lane", 0.0))
	return {"seed": seed_value, "aggression": 0.25 + unit * 0.65, "phase": unit * TAU, "preferred_side": -1 if seed_value % 2 == 0 else 1,
		"time": 0.0, "clock": 0.0, "distance": 0.0, "last_position": bike.global_position, "road_forward": -bike.global_basis.z,
		"lane": lane, "lane_target": lane, "actual_lane": lane, "pass_side": 0, "pass_id": 0, "pass_hold": 0.0, "cooldown": 0.0,
		"target_speed": 0.0, "curvature": 0.0, "braking": false, "emergency": false, "steering": 0.0, "action": "hold",
		"overtake_attempts": 0, "brake_frames": 0, "accelerate_frames": 0, "min_target_speed": INF, "max_target_speed": 0.0, "lane_min": lane, "lane_max": lane}

static func _plan(row: Dictionary, bike, track, nearby: Array, base_pace: float) -> void:
	var state: Dictionary = row.pilot_state
	var nearest: Dictionary = track.nearest(bike.global_position)
	var distance := float(nearest.distance)
	state.distance = distance
	var road: Transform3D = track.pose(distance)
	var forward := -road.basis.z
	state.road_forward = forward
	var actual_lane: float = (bike.global_position - Vector3(nearest.point)).dot(road.basis.x)
	state.actual_lane = actual_lane
	var limit := maxf(0.8, float(track.HALF_WIDTH) - 1.35)
	var p0: Vector3 = track.sample(distance)
	var p1: Vector3 = track.sample(distance + 6.0)
	var p2: Vector3 = track.sample(distance + 14.0)
	var p3: Vector3 = track.sample(distance + 24.0)
	var near_a := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	var near_b := Vector3(p2.x - p1.x, 0, p2.z - p1.z)
	var far_b := Vector3(p3.x - p2.x, 0, p3.z - p2.z)
	var near_turn := near_a.signed_angle_to(near_b, Vector3.UP)
	var far_turn := near_b.signed_angle_to(far_b, Vector3.UP)
	var near_curve := absf(near_turn) / maxf(2.0, (near_a.length() + near_b.length()) * 0.5)
	var far_curve := absf(far_turn) / maxf(2.0, (near_b.length() + far_b.length()) * 0.5)
	var curvature := maxf(near_curve, far_curve * 0.56)
	state.curvature = curvature
	var aggression := float(state.aggression)
	var grip: float = lerpf(1.0, 0.76, bike.wetness) * clampf(bike.grip_multiplier, 0.8, 1.25)
	var curve_speed := sqrt((6.9 + aggression * 1.8) * grip / maxf(0.005, curvature))
	var straight_speed := minf(bike.max_speed, maxf(3.0, base_pace) * (0.965 + aggression * 0.085))
	var target := minf(straight_speed, maxf(5.8, curve_speed))
	var turn_sign := signf(near_turn if absf(near_turn) > absf(far_turn) * 0.6 else far_turn)
	var approach := clampf((far_curve - near_curve) / maxf(0.015, maxf(near_curve, far_curve)), -1.0, 1.0)
	var line := turn_sign * approach * lerpf(0.85, 1.45, aggression)
	var wander := sin(float(state.time) * 0.38 + float(state.phase)) * 0.35 + sin(distance * 0.041 + float(state.phase)) * 0.24
	var lane_target := clampf(line + wander + float(state.preferred_side) * 0.22, -limit, limit)
	var neighbors: Array[Dictionary] = []
	var lead: Dictionary = {}
	var lead_gap := INF
	for index in mini(nearby.size(), MAX_NEIGHBORS):
		var entry: Variant = nearby[index]
		var other: Variant = entry.get("bike") if entry is Dictionary else entry
		if not is_instance_valid(other) or other == bike or not other is CharacterBody3D: continue
		var relative: Vector3 = other.global_position - bike.global_position
		if relative.length_squared() > 28.0 * 28.0 or absf(relative.y) > 3.0: continue
		var ahead := relative.dot(forward)
		var lateral := actual_lane + relative.dot(road.basis.x)
		var neighbor := {"id": other.get_instance_id(), "ahead": ahead, "lane": lateral, "speed": maxf(0.0, other.speed)}
		neighbors.append(neighbor)
		if ahead > 0.2 and ahead < 18.0 and absf(lateral - actual_lane) < 1.35 and ahead < lead_gap:
			lead = neighbor
			lead_gap = ahead
	state.emergency = false
	if int(state.pass_side) != 0:
		var opponent: Dictionary = {}
		for neighbor in neighbors:
			if int(neighbor.id) == int(state.pass_id): opponent = neighbor; break
		if not opponent.is_empty():
			lane_target = clampf(float(opponent.lane) + float(state.pass_side) * 1.50, -limit, limit)
		if float(state.pass_hold) <= 0.0 and (opponent.is_empty() or float(opponent.ahead) < -2.5 or float(opponent.ahead) > 22.0):
			state.pass_side = 0
			state.pass_id = 0
			state.cooldown = 0.8
		else: target = minf(bike.max_speed, target + 0.55)
	if int(state.pass_side) == 0 and float(state.cooldown) <= 0.0 and not lead.is_empty():
		var can_challenge := target > float(lead.speed) + 0.35 or (lead_gap < 8.5 and aggression > 0.50)
		if can_challenge:
			var left := clampf(float(lead.lane) - 1.50, -limit, limit)
			var right := clampf(float(lead.lane) + 1.50, -limit, limit)
			var left_cost := _lane_cost(left, neighbors, int(lead.id)) + (0.10 if int(state.preferred_side) > 0 else 0.0)
			var right_cost := _lane_cost(right, neighbors, int(lead.id)) + (0.10 if int(state.preferred_side) < 0 else 0.0)
			var side := -1 if left_cost <= right_cost else 1
			var candidate := left if side < 0 else right
			if absf(candidate - float(lead.lane)) > 1.15 and minf(left_cost, right_cost) < 2.0:
				state.pass_side = side
				state.pass_id = int(lead.id)
				state.pass_hold = 2.8 + aggression
				state.overtake_attempts = int(state.overtake_attempts) + 1
				lane_target = candidate
	# A pass starts with a real sideways approach. Until sufficient lateral
	# clearance exists, brake for the lead bike instead of driving through it.
	if not lead.is_empty():
		var closing: float = maxf(0.0, bike.speed - float(lead.speed))
		if lead_gap < 3.0 + closing * 0.65:
			target = minf(target, maxf(2.0, float(lead.speed) + (lead_gap - 2.8) * 0.75))
			state.emergency = lead_gap < 2.0 and closing > 0.7
	state.lane_target = lane_target
	state.target_speed = clampf(target, 0.0, maxf(0.0, bike.max_speed))

static func _lane_cost(lane: float, neighbors: Array[Dictionary], overtaken: int) -> float:
	var cost := absf(lane) * 0.10
	for other in neighbors:
		if int(other.id) == overtaken: continue
		if float(other.ahead) < -3.0 or float(other.ahead) > 13.0: continue
		cost += maxf(0.0, 1.40 - absf(float(other.lane) - lane)) * 2.0
	return cost
