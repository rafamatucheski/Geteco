extends "res://tests/measure_game_frame_stability.gd"
## Sustained eastbound Foundry Avenue driving through the real input path.
## Setup is inherited; during the measured route nothing sets position,
## rotation, velocity, collision masks, actor health or simulation activation.
## Use --night --rain --police for pursuit; a blocked/crashed route must fail
## motion coverage instead of being certified as a streaming benchmark.
var _driving := false
var _driven_car: CharacterBody2D
var _last_blocker: Dictionary = {}
const EASTBOUND_LANE_Y := 370.0
var _front_vehicle_detected := false
var _front_min_clearance := INF
var _front_brake_frames := 0
var _traffic_probe := RectangleShape2D.new()

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	_driven_car = car as CharacterBody2D
	_driving = label == "driving"
	if label == "warmup":
		car.global_position = Vector2(700.0, EASTBOUND_LANE_Y)
		car.global_rotation = 0.0
		if car is CharacterBody2D: car.velocity = Vector2.ZERO
		car.reset_physics_interpolation()
		_traffic_probe.size = Vector2(260.0, 44.0)
	if _driving:
		_last_blocker = {}
		_front_vehicle_detected = false
		_front_min_clearance = INF
		_front_brake_frames = 0
	await super._sample(output, label, seconds, car)
	_driving = false
	for action in [&"move_up", &"move_down", &"move_left", &"move_right"]:
		Input.action_release(action)

func _report_render() -> void:
	super._report_render()
	if not _driving or not is_instance_valid(_driven_car): return
	var car := _driven_car
	# Look ahead down the authored eastbound lane. Steering is ordinary input,
	# so traffic impacts, rain, braking and the production handling all apply.
	var target := Vector2(minf(car.global_position.x + 140.0, 6150.0), EASTBOUND_LANE_Y)
	var error := wrapf((target - car.global_position).angle() - car.global_rotation, -PI, PI)
	var steering := clampf(error * 2.5, -1.0, 1.0)
	_set_input(&"move_left", maxf(-steering, 0.0))
	_set_input(&"move_right", maxf(steering, 0.0))
	var desired_speed := 150.0 if absf(error) < 0.6 else 65.0
	desired_speed = minf(desired_speed, _traffic_limited_speed(car))
	var speed := car.velocity.dot(car.global_transform.x)
	_set_input(&"move_up", clampf((desired_speed - speed) / 30.0, 0.0, 1.0))
	_set_input(&"move_down", 1.0 if speed > desired_speed + 25.0 else 0.0)
	if speed < 20.0 and car.get_slide_collision_count() > 0:
		var collision := car.get_slide_collision(car.get_slide_collision_count() - 1)
		var collider := collision.get_collider()
		_last_blocker = {
			"collider": str(collider.get_path()) if collider is Node else str(collider),
			"class": collider.get_class() if collider is Object else "",
			"position": str(collision.get_position()),
			"normal": str(collision.get_normal()),
			"actor": _traffic_actor_state(collider as Node),
		}

func _traffic_limited_speed(car: CharacterBody2D) -> float:
	# A broad forward corridor models what a player sees. The production rays can
	# hit a pedestrian/driver first and hide the vehicle behind it; filtering all
	# physical results makes this test driver brake for buses, trailers and bikes.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _traffic_probe
	query.transform = Transform2D(car.global_rotation, car.global_position + car.global_transform.x * 130.0)
	query.collision_mask = 2
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [car.get_rid()]
	var nearest: Node2D = null
	var nearest_forward := INF
	for hit in car.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var candidate := hit.get("collider") as Node2D
		if candidate == null or candidate == car or not candidate.is_in_group("vehicle"): continue
		var relative := candidate.global_position - car.global_position
		var forward := relative.dot(car.global_transform.x)
		if forward <= 0.0 or forward >= nearest_forward: continue
		nearest = candidate
		nearest_forward = forward
	if nearest == null: return INF
	var actor: Node = nearest
	var other_half_length := 20.0
	var other_hull := actor.get_node_or_null("Collision") as CollisionShape2D
	if other_hull != null and other_hull.shape != null:
		other_half_length = other_hull.shape.get_rect().size.x * 0.5
	var clearance := maxf(0.0, nearest_forward - car.target_length * 0.5 - other_half_length)
	_front_vehicle_detected = true
	_front_min_clearance = minf(_front_min_clearance, clearance)
	_front_brake_frames += 1
	var leader_speed := 0.0
	if actor is CharacterBody2D:
		leader_speed = maxf(0.0, actor.velocity.dot(car.global_transform.x))
	if "_lane_motion_speed" in actor:
		leader_speed = maxf(leader_speed, float(actor.get("_lane_motion_speed")))
	# Match the leader near 60 px of bumper clearance; farther away, close the
	# gap gradually. Braking and acceleration still use the production inputs.
	return clampf(leader_speed + maxf(0.0, clearance - 60.0) * 0.6, 0.0, 150.0)

func _set_input(action: StringName, strength: float) -> void:
	if strength > 0.01: Input.action_press(action, strength)
	else: Input.action_release(action)

func _traffic_actor_state(actor: Node) -> Dictionary:
	if actor == null: return {}
	var state := {
		"path": str(actor.get_path()),
		"global_position": str(actor.global_position) if actor is Node2D else "",
		"global_rotation": actor.global_rotation if actor is Node2D else 0.0,
		"local_position": str(actor.position) if actor is Node2D else "",
		"groups": actor.get_groups(),
	}
	if actor is CharacterBody2D: state["velocity"] = str(actor.velocity)
	if actor.is_in_group("vehicle"):
		state["archetype"] = actor.get("active_archetype_id")
		state["is_motorcycle"] = actor.get("is_motorcycle")
		state["detached_from_lane"] = actor.get("_detached_from_lane")
		state["lane_motion_speed"] = actor.get("_lane_motion_speed")
		state["is_moving_on_lane"] = actor.get("is_moving_on_lane")
		state["emergency_yield_active"] = actor.get("_emergency_yield_active")
		state["emergency_yield_state"] = actor.get_meta("emergency_yield_state", "")
		var maneuver = actor.get("_siren_maneuver")
		state["siren_maneuver_state"] = maneuver.state if maneuver != null else ""
		state["avoidance_hold"] = actor.get("_avoidance_hold")
		state["block_wait_timer"] = actor.get("block_wait_timer")
		var hull := actor.get_node_or_null("Collision") as CollisionShape2D
		if hull != null and hull.shape != null:
			state["collision_size"] = str(hull.shape.get_rect().size)
	var follow := actor.get_parent() as PathFollow2D
	if follow != null:
		state["lane_progress"] = follow.progress
		state["follow_position"] = str(follow.position)
		var lane := follow.get_parent() as Path2D
		if lane != null:
			state["lane_path"] = str(lane.get_path())
			state["lane_id"] = lane.get_meta("traffic_lane_id", "")
			state["lane_direction"] = lane.get_meta("traffic_direction_name", "")
			state["lane_offset"] = lane.get_meta("traffic_lane_offset", 0.0)
	return state

func _sample_subject_state(subject: Node2D) -> Dictionary:
	var state := super._sample_subject_state(subject)
	var car := subject as CharacterBody2D
	state["health"] = car.health
	state["is_broken"] = car.is_broken
	state["is_exploding"] = car.is_exploding
	state["is_exploded"] = car.is_exploded
	state["is_driven_by_player"] = car.is_driven_by_player
	state["input_armed"] = car._drive_input_armed
	state["max_speed"] = car.max_speed
	state["last_low_speed_collision"] = _last_blocker
	state["front_vehicle_detected"] = _front_vehicle_detected
	state["front_min_clearance"] = _front_min_clearance if is_finite(_front_min_clearance) else null
	state["front_brake_frames"] = _front_brake_frames
	return state
