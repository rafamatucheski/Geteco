@tool
class_name RailLevelCrossing2D
extends Node2D

## One automatically discovered at-grade road/rail intersection. Its immutable
## address is {road_id, road_t, rail_t}; position, lanes and orientation are all
## derived from the canonical graphs.
##
## The barriers deliberately close incoming lanes only. A vehicle which has
## already crossed an entry gate always retains an unobstructed escape lane.

signal state_changed(crossing_id: StringName, state: int)
signal stop_requirement_changed(crossing_id: StringName, required: bool)

enum GateState {
	OPEN,
	CLOSING,
	CLOSED,
	OPENING,
}

const SAFETY_AREA_LAYER := 8
const ROAD_BODY_MASK := 2
const BARRIER_LAYER := 16 # Camada propria da cancela. NAO reusar a camada 1
# ("predios/paredes"): o jogador a pe colide com a camada 1, entao uma cancela
# nela prende o jogador entre os dois portoes quando eles fecham (bug real:
# "entrei no trilho do trem e nao consigo mais sair"). Veiculos que devem
# respeitar a cancela precisam incluir a camada 16 na propria collision_mask
# (ver PlayerCar em Main.tscn).
const DEFAULT_RAIL_BALLAST_WIDTH := 54.0
const DEFAULT_TRACK_GAUGE := 22.0
const CONFLICT_MARGIN := 14.0
const GATE_CLEARANCE := 30.0
const APPROACH_LENGTH := 190.0
const BARRIER_THICKNESS := 12.0
const BARRIER_ACTIVATION_RATIO := 0.72
const MIN_CLEARANCE_SPEED := 30.0
const DESIGN_VEHICLE_LENGTH := 58.0
const WARNING_BUFFER_SECONDS := 1.25
const RUBBER_COLOR := Color("#292e31")
const RUBBER_EDGE_COLOR := Color("#11171b")
const RAIL_COLOR := Color("#b9c1c5")
const MAST_COLOR := Color("#ddd8c6")
const RED := Color("#e4433b")
const RED_DARK := Color("#661817")

var crossing_id: StringName = &""
var road_id: StringName = &""
var road_index := -1
var road_t := 0.0
var rail_t := 0.0
var road_width := 96.0
var rail_ballast_width := DEFAULT_RAIL_BALLAST_WIDTH
var track_gauge := DEFAULT_TRACK_GAUGE
var rail_tangent_local := Vector2.DOWN
var transition_seconds := 1.35
var gate_state := GateState.OPEN

var conflict_half_length := 42.0
var gate_offset := 72.0
var lane_controls: Array[Dictionary] = []

var _gate_ratio := 0.0
var _target_closed := false
var _blink_clock := 0.0
var _barrier_shapes: Array[CollisionShape2D] = []
var _barrier_geometry: Array[Dictionary] = []
var _conflict_vehicles: Dictionary = {}


func _ready() -> void:
	add_to_group("rail_level_crossing")
	add_to_group("traffic_control_zone")
	add_to_group("road_crossing")
	_ensure_runtime_nodes()
	set_process(not Engine.is_editor_hint())
	queue_redraw()


func configure(data: Dictionary) -> void:
	crossing_id = StringName(data.get("id", "rail_crossing"))
	road_id = StringName(data.get("road_id", ""))
	road_index = int(data.get("road_index", -1))
	road_t = clampf(float(data.get("road_t", 0.0)), 0.0, 1.0)
	rail_t = clampf(float(data.get("rail_t", 0.0)), 0.0, 1.0)
	road_width = maxf(32.0, float(data.get("road_width", 96.0)))
	rail_ballast_width = maxf(24.0, float(data.get("rail_ballast_width", DEFAULT_RAIL_BALLAST_WIDTH)))
	track_gauge = clampf(float(data.get("track_gauge", DEFAULT_TRACK_GAUGE)), 8.0, rail_ballast_width - 8.0)
	transition_seconds = maxf(0.25, float(data.get("transition_seconds", transition_seconds)))
	var road_tangent: Vector2 = data.get("road_tangent", Vector2.RIGHT)
	var rail_tangent: Vector2 = data.get("rail_tangent", Vector2.DOWN)
	if road_tangent.is_zero_approx():
		road_tangent = Vector2.RIGHT
	if rail_tangent.is_zero_approx():
		rail_tangent = road_tangent.orthogonal()
	position = data.get("position", Vector2.ZERO)
	rotation = road_tangent.angle()
	rail_tangent_local = rail_tangent.rotated(-rotation).normalized()
	lane_controls = _normalise_lane_controls(data.get("lane_controls", []))
	_update_derived_geometry()
	set_meta("crossing_id", crossing_id)
	set_meta("road_id", road_id)
	set_meta("road_index", road_index)
	set_meta("t", road_t)
	set_meta("road_t", road_t)
	set_meta("rail_t", rail_t)
	set_meta("crossing_type", "rail_level")
	set_meta("escape_policy", "incoming_lanes_only")
	set_meta("stop_required", should_stop_vehicle())
	if is_inside_tree():
		_ensure_runtime_nodes()
		queue_redraw()


func set_train_approaching(active: bool) -> void:
	if _target_closed == active:
		return
	var old_required := should_stop_vehicle()
	_target_closed = active
	gate_state = GateState.CLOSING if active else GateState.OPENING
	state_changed.emit(crossing_id, gate_state)
	set_meta("stop_required", should_stop_vehicle())
	if old_required != should_stop_vehicle():
		stop_requirement_changed.emit(crossing_id, should_stop_vehicle())
	queue_redraw()


func should_stop_vehicle(_vehicle: Node = null) -> bool:
	return _target_closed or gate_state != GateState.OPEN or _gate_ratio > 0.01


func should_stop_vehicle_at(world_point: Vector2, vehicle: Node = null) -> bool:
	if not should_stop_vehicle():
		return false
	var local_point := to_local(world_point)
	if absf(local_point.y) > road_width * 0.5 + 6.0:
		return false
	if absf(local_point.x) > gate_offset + APPROACH_LENGTH:
		return false
	# Once the front of a vehicle has passed an entry gate, stopping it is less
	# safe than letting it clear the railway. The opposite lane is physically
	# open at the exit by construction.
	if absf(local_point.x) < gate_offset + BARRIER_THICKNESS * 0.5:
		return false

	var local_velocity := _vehicle_local_velocity(vehicle)
	if not local_velocity.is_zero_approx():
		# Same signs mean motion away from the crossing on either approach.
		if local_velocity.x * local_point.x > 0.0:
			return false
		if local_velocity.x * local_point.x < 0.0:
			return true

	var nearest_lane := _nearest_lane(local_point.y)
	if not nearest_lane.is_empty():
		var direction := int(nearest_lane.get("direction", 1))
		# Forward lanes enter from local -X; reverse lanes enter from +X.
		return float(direction) * local_point.x < 0.0
	return true


func contains_world_point(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	return Rect2(
		Vector2(-gate_offset - APPROACH_LENGTH, -road_width * 0.5),
		Vector2((gate_offset + APPROACH_LENGTH) * 2.0, road_width)
	).has_point(local_point)


func is_conflict_world_point(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	return absf(local_point.x) <= conflict_half_length and absf(local_point.y) <= road_width * 0.5


func is_conflict_zone_occupied() -> bool:
	_cleanup_invalid_vehicles()
	return not _conflict_vehicles.is_empty()


func get_conflict_vehicle_count() -> int:
	_cleanup_invalid_vehicles()
	return _conflict_vehicles.size()


func required_warning_seconds(clearance_speed: float = MIN_CLEARANCE_SPEED) -> float:
	# Worst case: a vehicle nose has just crossed its entry gate when the alarm
	# starts. Include its full body before declaring the track conflict clear.
	var clear_distance := gate_offset + conflict_half_length + DESIGN_VEHICLE_LENGTH
	return transition_seconds + clear_distance / maxf(clearance_speed, 1.0) + WARNING_BUFFER_SECONDS


func required_warning_distance(train_speed: float) -> float:
	return absf(train_speed) * required_warning_seconds()


func get_gate_geometry() -> Dictionary:
	return {
		"policy": "incoming_lanes_only",
		"conflict_half_length": conflict_half_length,
		"gate_offset": gate_offset,
		"approach_length": APPROACH_LENGTH,
		"barriers": _barrier_geometry.duplicate(true),
	}


func get_crossing_data() -> Dictionary:
	return {
		"id": crossing_id,
		"crossing_id": crossing_id,
		"road_id": road_id,
		"road_index": road_index,
		"road_t": road_t,
		"rail_t": rail_t,
		"position": global_position,
		"road_tangent": Vector2.RIGHT.rotated(global_rotation),
		"rail_tangent": rail_tangent_local.rotated(global_rotation),
		"road_width": road_width,
		"rail_ballast_width": rail_ballast_width,
		"track_gauge": track_gauge,
		"lane_controls": lane_controls.duplicate(true),
		"conflict_half_length": conflict_half_length,
		"conflict_vehicle_count": get_conflict_vehicle_count(),
		"gate_geometry": get_gate_geometry(),
		"gate_state": gate_state,
		"gate_ratio": _gate_ratio,
		"stop_required": should_stop_vehicle(),
		"warning_seconds": required_warning_seconds(),
	}


func _process(delta: float) -> void:
	_blink_clock += delta
	var previous_state := gate_state
	var previous_required := should_stop_vehicle()
	var target := 1.0 if _target_closed else 0.0
	_gate_ratio = move_toward(_gate_ratio, target, delta / maxf(transition_seconds, 0.05))
	if _target_closed and is_equal_approx(_gate_ratio, 1.0):
		gate_state = GateState.CLOSED
	elif not _target_closed and is_equal_approx(_gate_ratio, 0.0):
		gate_state = GateState.OPEN
	_update_physical_barriers()
	set_meta("stop_required", should_stop_vehicle())
	if gate_state != previous_state:
		state_changed.emit(crossing_id, gate_state)
	if previous_required != should_stop_vehicle():
		stop_requirement_changed.emit(crossing_id, should_stop_vehicle())
	queue_redraw()


func _normalise_lane_controls(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is Array:
		for value in source:
			if not value is Dictionary:
				continue
			var lane := value as Dictionary
			var direction := -1 if int(lane.get("direction", 1)) < 0 else 1
			result.append({
				"lane_id": String(lane.get("lane_id", "lane_%02d" % result.size())),
				"offset": clampf(float(lane.get("offset", 0.0)), -road_width * 0.48, road_width * 0.48),
				"direction": direction,
			})
	if result.is_empty():
		var offset := road_width * 0.25
		result = [
			{"lane_id": "forward_01", "offset": offset, "direction": 1},
			{"lane_id": "reverse_01", "offset": -offset, "direction": -1},
		]
	return result


func _update_derived_geometry() -> void:
	var rail_normal := rail_tangent_local.orthogonal().normalized()
	var road_projection := maxf(absf(Vector2.RIGHT.dot(rail_normal)), 0.28)
	conflict_half_length = clampf(
		(rail_ballast_width * 0.5 + CONFLICT_MARGIN) / road_projection,
		34.0,
		150.0
	)
	gate_offset = conflict_half_length + GATE_CLEARANCE


func _ensure_runtime_nodes() -> void:
	var detector := get_node_or_null("VehicleApproachArea") as Area2D
	if detector == null:
		detector = Area2D.new()
		detector.name = "VehicleApproachArea"
		detector.collision_layer = SAFETY_AREA_LAYER
		detector.collision_mask = ROAD_BODY_MASK
		detector.monitoring = not Engine.is_editor_hint()
		detector.monitorable = true
		add_child(detector)
	var detector_collision := detector.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if detector_collision == null:
		detector_collision = CollisionShape2D.new()
		detector_collision.name = "CollisionShape2D"
		detector.add_child(detector_collision)
	var detector_shape := RectangleShape2D.new()
	detector_shape.size = Vector2((gate_offset + APPROACH_LENGTH) * 2.0, road_width)
	detector_collision.shape = detector_shape

	var conflict := get_node_or_null("TrackConflictZone") as Area2D
	if conflict == null:
		conflict = Area2D.new()
		conflict.name = "TrackConflictZone"
		conflict.collision_layer = SAFETY_AREA_LAYER
		conflict.collision_mask = ROAD_BODY_MASK
		conflict.monitoring = not Engine.is_editor_hint()
		conflict.monitorable = true
		conflict.add_to_group("rail_crossing_conflict_zone")
		add_child(conflict)
		conflict.body_entered.connect(_on_conflict_body_entered)
		conflict.body_exited.connect(_on_conflict_body_exited)
	var conflict_collision := conflict.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if conflict_collision == null:
		conflict_collision = CollisionShape2D.new()
		conflict_collision.name = "CollisionShape2D"
		conflict.add_child(conflict_collision)
	var conflict_shape := RectangleShape2D.new()
	conflict_shape.size = Vector2(conflict_half_length * 2.0, road_width)
	conflict_collision.shape = conflict_shape

	var blockers := get_node_or_null("ClosedGateBarriers") as Node2D
	if blockers == null:
		blockers = Node2D.new()
		blockers.name = "ClosedGateBarriers"
		add_child(blockers)
	for child in blockers.get_children():
		blockers.remove_child(child)
		child.free()
	_barrier_shapes.clear()
	_barrier_geometry.clear()
	var lane_width := _derived_lane_block_width()
	for lane_index in range(lane_controls.size()):
		var lane := lane_controls[lane_index]
		var direction := int(lane.direction)
		var approach := -1.0 if direction > 0 else 1.0
		var body := StaticBody2D.new()
		body.name = "InboundLane_%02d" % lane_index
		body.collision_layer = BARRIER_LAYER
		body.collision_mask = 0
		body.position = Vector2(approach * gate_offset, float(lane.offset))
		body.add_to_group("rail_crossing_barrier")
		body.add_to_group("traffic_hard_blocker")
		body.set_meta("lane_id", String(lane.lane_id))
		body.set_meta("direction", direction)
		body.set_meta("approach", int(approach))
		blockers.add_child(body)
		var barrier := CollisionShape2D.new()
		barrier.name = "CollisionShape2D"
		body.add_child(barrier)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(BARRIER_THICKNESS, lane_width)
		barrier.shape = shape
		barrier.disabled = true
		_barrier_shapes.append(barrier)
		_barrier_geometry.append({
			"lane_id": String(lane.lane_id),
			"direction": direction,
			"approach": int(approach),
			"position": body.position,
			"size": shape.size,
		})


func _derived_lane_block_width() -> float:
	var minimum_spacing := INF
	for first in range(lane_controls.size()):
		for second in range(first + 1, lane_controls.size()):
			var spacing := absf(float(lane_controls[first].offset) - float(lane_controls[second].offset))
			if spacing > 1.0:
				minimum_spacing = minf(minimum_spacing, spacing)
	if minimum_spacing == INF:
		minimum_spacing = road_width / maxf(float(lane_controls.size()), 2.0)
	return clampf(minimum_spacing * 0.72, 18.0, road_width * 0.44)


func _update_physical_barriers() -> void:
	var enabled := _gate_ratio >= BARRIER_ACTIVATION_RATIO
	for barrier in _barrier_shapes:
		if is_instance_valid(barrier) and barrier.disabled == enabled:
			barrier.set_deferred("disabled", not enabled)


func _nearest_lane(local_y: float) -> Dictionary:
	var result: Dictionary = {}
	var nearest := INF
	for lane in lane_controls:
		var distance := absf(local_y - float(lane.offset))
		if distance < nearest:
			nearest = distance
			result = lane
	return result


func _vehicle_local_velocity(vehicle: Node) -> Vector2:
	if vehicle == null:
		return Vector2.ZERO
	var world_velocity := Vector2.ZERO
	if vehicle.has_method("get_velocity"):
		var value: Variant = vehicle.call("get_velocity")
		if value is Vector2:
			world_velocity = value
	else:
		for property in vehicle.get_property_list():
			var property_name := String(property.get("name", ""))
			if property_name in ["velocity", "linear_velocity"]:
				var value: Variant = vehicle.get(property_name)
				if value is Vector2:
					world_velocity = value
				break
	if world_velocity.is_zero_approx():
		return Vector2.ZERO
	return world_velocity.rotated(-global_rotation)


func _on_conflict_body_entered(body: Node2D) -> void:
	if _is_vehicle(body):
		_conflict_vehicles[body.get_instance_id()] = weakref(body)


func _on_conflict_body_exited(body: Node2D) -> void:
	_conflict_vehicles.erase(body.get_instance_id())


func _is_vehicle(body: Node) -> bool:
	return body.is_in_group("vehicle") or body.is_in_group("modern_traffic") or body.is_in_group("district_one_traffic") or body.is_in_group("phase1_traffic")


func _cleanup_invalid_vehicles() -> void:
	for key in _conflict_vehicles.keys():
		var reference: WeakRef = _conflict_vehicles[key]
		if reference.get_ref() == null:
			_conflict_vehicles.erase(key)


func _approach_lane_band(approach: int) -> Dictionary:
	var lane_width := _derived_lane_block_width()
	var minimum_y := INF
	var maximum_y := -INF
	for lane in lane_controls:
		var lane_approach := -1 if int(lane.direction) > 0 else 1
		if lane_approach != approach:
			continue
		minimum_y = minf(minimum_y, float(lane.offset) - lane_width * 0.5)
		maximum_y = maxf(maximum_y, float(lane.offset) + lane_width * 0.5)
	if minimum_y == INF:
		return {}
	return {"minimum_y": minimum_y, "maximum_y": maximum_y}


func _draw() -> void:
	# A complete rubber deck spans the road, then redraws both rails above it.
	# Its orientation comes from the live rail tangent, including skew crossings.
	var rail_normal := rail_tangent_local.orthogonal().normalized()
	var span_projection := maxf(absf(rail_tangent_local.y), 0.25)
	var rail_span := minf((road_width * 0.5 + 5.0) / span_projection, 210.0)
	var rubber_half_width := rail_ballast_width * 0.5 + 3.0
	var deck := PackedVector2Array([
		-rail_tangent_local * rail_span - rail_normal * rubber_half_width,
		rail_tangent_local * rail_span - rail_normal * rubber_half_width,
		rail_tangent_local * rail_span + rail_normal * rubber_half_width,
		-rail_tangent_local * rail_span + rail_normal * rubber_half_width,
	])
	draw_colored_polygon(deck, RUBBER_COLOR)
	draw_polyline(PackedVector2Array([deck[0], deck[1], deck[2], deck[3], deck[0]]), RUBBER_EDGE_COLOR, 2.0, true)
	for rail_side in [-1.0, 1.0]:
		var rail_offset: Vector2 = rail_normal * rail_side * track_gauge * 0.5
		draw_line(-rail_tangent_local * rail_span + rail_offset, rail_tangent_local * rail_span + rail_offset, RAIL_COLOR, 3.5, true)

	for approach in [-1, 1]:
		var band := _approach_lane_band(approach)
		if band.is_empty():
			continue
		var minimum_y := float(band.minimum_y)
		var maximum_y := float(band.maximum_y)
		var center_y := (minimum_y + maximum_y) * 0.5
		var outer_side := 1.0 if center_y >= 0.0 else -1.0
		var outer_y := maximum_y if outer_side > 0.0 else minimum_y
		var inner_y := minimum_y if outer_side > 0.0 else maximum_y
		var mast := Vector2(float(approach) * gate_offset, outer_y + outer_side * 10.0)
		draw_circle(mast + Vector2(4.0, 5.0), 9.0, Color(0.02, 0.025, 0.03, 0.35))
		draw_circle(mast, 8.0, Color("#272d31"))
		draw_circle(mast, 5.0, MAST_COLOR)
		var lamp_on := should_stop_vehicle() and int(_blink_clock * 3.2 + (1.0 if approach > 0 else 0.0)) % 2 == 0
		draw_circle(mast + Vector2(-5.0, 0.0), 3.7, RED if lamp_on else RED_DARK)
		draw_circle(mast + Vector2(5.0, 0.0), 3.7, RED if not lamp_on and should_stop_vehicle() else RED_DARK)

		# One boom covers only the incoming carriageway; the outbound lane on the
		# far side remains physically and visually clear for committed vehicles.
		var open_direction := Vector2(-float(approach), 0.0)
		var closed_direction := Vector2(0.0, -outer_side)
		var arm_direction := open_direction.slerp(closed_direction, _gate_ratio).normalized()
		var arm_length := absf(mast.y - inner_y) + 4.0
		var arm_end := mast + arm_direction * maxf(34.0, arm_length)
		draw_line(mast, arm_end, MAST_COLOR, 7.0, true)
		for stripe in range(5):
			if stripe % 2 == 0:
				var a := mast.lerp(arm_end, float(stripe) / 5.0)
				var b := mast.lerp(arm_end, float(stripe + 1) / 5.0)
				draw_line(a, b, RED, 7.0, true)
