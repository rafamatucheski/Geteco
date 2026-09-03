@tool
class_name RailLevelCrossing2D
extends Node2D

## One automatically discovered at-grade road/rail intersection. Its immutable
## address is {road_id, road_t, rail_t}; position and orientation are derived.

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
const BARRIER_LAYER := 1
const RUBBER_COLOR := Color("#292e31")
const MAST_COLOR := Color("#ddd8c6")
const RED := Color("#e4433b")
const RED_DARK := Color("#661817")

var crossing_id: StringName = &""
var road_id: StringName = &""
var road_t := 0.0
var rail_t := 0.0
var road_width := 96.0
var rail_tangent_local := Vector2.DOWN
var transition_seconds := 1.35
var gate_state := GateState.OPEN

var _gate_ratio := 0.0
var _target_closed := false
var _blink_clock := 0.0
var _barrier_shapes: Array[CollisionShape2D] = []


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
	road_t = clampf(float(data.get("road_t", 0.0)), 0.0, 1.0)
	rail_t = clampf(float(data.get("rail_t", 0.0)), 0.0, 1.0)
	road_width = maxf(32.0, float(data.get("road_width", 96.0)))
	var road_tangent: Vector2 = data.get("road_tangent", Vector2.RIGHT)
	var rail_tangent: Vector2 = data.get("rail_tangent", Vector2.DOWN)
	if road_tangent.is_zero_approx():
		road_tangent = Vector2.RIGHT
	if rail_tangent.is_zero_approx():
		rail_tangent = road_tangent.orthogonal()
	position = data.get("position", Vector2.ZERO)
	rotation = road_tangent.angle()
	rail_tangent_local = rail_tangent.rotated(-rotation).normalized()
	set_meta("crossing_id", crossing_id)
	set_meta("road_id", road_id)
	set_meta("t", road_t)
	set_meta("road_t", road_t)
	set_meta("rail_t", rail_t)
	set_meta("crossing_type", "rail_level")
	set_meta("stop_required", should_stop_vehicle())
	if is_inside_tree():
		_ensure_runtime_nodes()
		queue_redraw()


func set_train_approaching(active: bool) -> void:
	if _target_closed == active:
		return
	_target_closed = active
	var old_required := should_stop_vehicle()
	gate_state = GateState.CLOSING if active else GateState.OPENING
	state_changed.emit(crossing_id, gate_state)
	set_meta("stop_required", should_stop_vehicle())
	if old_required != should_stop_vehicle():
		stop_requirement_changed.emit(crossing_id, should_stop_vehicle())
	queue_redraw()


func should_stop_vehicle(_vehicle: Node = null) -> bool:
	return _target_closed or gate_state != GateState.OPEN or _gate_ratio > 0.01


func contains_world_point(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	return Rect2(Vector2(-150.0, -road_width * 0.5), Vector2(300.0, road_width)).has_point(local_point)


func get_crossing_data() -> Dictionary:
	return {
		"id": crossing_id,
		"road_id": road_id,
		"road_t": road_t,
		"rail_t": rail_t,
		"position": global_position,
		"road_tangent": Vector2.RIGHT.rotated(global_rotation),
		"rail_tangent": rail_tangent_local.rotated(global_rotation),
		"road_width": road_width,
		"gate_state": gate_state,
		"gate_ratio": _gate_ratio,
		"stop_required": should_stop_vehicle(),
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
	detector_shape.size = Vector2(300.0, road_width)
	detector_collision.shape = detector_shape

	var blockers := get_node_or_null("ClosedGateBarriers") as Node2D
	if blockers == null:
		blockers = Node2D.new()
		blockers.name = "ClosedGateBarriers"
		add_child(blockers)
	_barrier_shapes.clear()
	for approach in [-1.0, 1.0]:
		var blocker_name := "Approach%s" % ("A" if approach < 0.0 else "B")
		var body := blockers.get_node_or_null(blocker_name) as StaticBody2D
		if body == null:
			body = StaticBody2D.new()
			body.name = blocker_name
			body.collision_layer = BARRIER_LAYER
			body.collision_mask = 0
			body.position = Vector2(approach * 58.0, 0.0)
			blockers.add_child(body)
		var barrier := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if barrier == null:
			barrier = CollisionShape2D.new()
			barrier.name = "CollisionShape2D"
			body.add_child(barrier)
		var shape := RectangleShape2D.new()
		shape.size = Vector2(12.0, maxf(24.0, road_width - 8.0))
		barrier.shape = shape
		barrier.disabled = true
		_barrier_shapes.append(barrier)


func _update_physical_barriers() -> void:
	var enabled := _gate_ratio >= 0.72
	for barrier in _barrier_shapes:
		if is_instance_valid(barrier) and barrier.disabled == enabled:
			barrier.set_deferred("disabled", not enabled)


func _draw() -> void:
	# Rubber infill follows the live rail tangent while the whole node follows
	# the live road tangent, so skewed crossings still fit both geometries.
	var rail_normal := rail_tangent_local.orthogonal().normalized()
	for step in range(-2, 3):
		var center := rail_tangent_local * float(step) * 11.0
		draw_line(center - rail_normal * 25.0, center + rail_normal * 25.0, RUBBER_COLOR, 10.0, true)

	var half_road := road_width * 0.5
	for approach in [-1.0, 1.0]:
		var side := -1.0 if approach < 0.0 else 1.0
		var mast := Vector2(approach * 58.0, side * (half_road + 13.0))
		draw_circle(mast + Vector2(4.0, 5.0), 9.0, Color(0.02, 0.025, 0.03, 0.35))
		draw_circle(mast, 8.0, Color("#272d31"))
		draw_circle(mast, 5.0, MAST_COLOR)
		var lamp_on := should_stop_vehicle() and int(_blink_clock * 3.2 + (1.0 if approach > 0.0 else 0.0)) % 2 == 0
		draw_circle(mast + Vector2(-5.0, 0.0), 3.7, RED if lamp_on else RED_DARK)
		draw_circle(mast + Vector2(5.0, 0.0), 3.7, RED if not lamp_on and should_stop_vehicle() else RED_DARK)

		# Open arm is parallel to traffic; closed arm rotates across the lane.
		var open_direction := Vector2(-approach, 0.0)
		var closed_direction := Vector2(0.0, -side)
		var arm_direction := open_direction.slerp(closed_direction, _gate_ratio).normalized()
		var arm_end := mast + arm_direction * maxf(42.0, half_road + 5.0)
		draw_line(mast, arm_end, MAST_COLOR, 7.0, true)
		for stripe in range(5):
			if stripe % 2 == 0:
				var a := mast.lerp(arm_end, float(stripe) / 5.0)
				var b := mast.lerp(arm_end, float(stripe + 1) / 5.0)
				draw_line(a, b, RED, 7.0, true)
