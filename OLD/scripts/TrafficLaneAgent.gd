class_name PhaseOneTrafficLaneAgent
extends Node2D

## A vehicle is constrained to exactly one directed lane route.
@export var lane_id := ""
@export var speed := 110.0
@export var body_color := Color("e85252")
@export var route_points: PackedVector2Array
@export var vehicle_length := 42.0
@export var vehicle_width := 20.0
@export var archetype_id := "sedan_classic"
@export var roof_prop := "none"

var _segment := 0
var _progress := 0.0
var _stopped := false
var _stopped_for_signal := false

const MAIN_INTERSECTION_ID: StringName = &"central_district_main"

func _ready() -> void:
	add_to_group("phase1_traffic")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if route_points.size() < 2:
		return
	_stopped_for_signal = _must_stop_at_signal()
	_stopped = _has_vehicle_too_close_ahead() or _stopped_for_signal
	if not _stopped:
		_advance(speed * delta)
	_enforce_lane_guardrail()

func _advance(distance: float) -> void:
	while distance > 0.0:
		var start := route_points[_segment]
		var end := route_points[(_segment + 1) % route_points.size()]
		var length := start.distance_to(end)
		var remaining := length - _progress
		if distance < remaining:
			_progress += distance
			distance = 0.0
		else:
			distance -= remaining
			_segment = (_segment + 1) % route_points.size()
			_progress = 0.0
	var current_start := route_points[_segment]
	var current_end := route_points[(_segment + 1) % route_points.size()]
	global_position = current_start.lerp(current_end, _progress / maxf(1.0, current_start.distance_to(current_end)))
	rotation = current_start.angle_to_point(current_end)

func _has_vehicle_too_close_ahead() -> bool:
	var forward := Vector2.RIGHT.rotated(rotation)
	for other in get_tree().get_nodes_in_group("phase1_traffic"):
		if other == self or other.lane_id != lane_id:
			continue
		var gap: Vector2 = other.global_position - global_position
		if gap.dot(forward) > 0.0 and gap.length() < vehicle_length * 1.45:
			return true
	return false

func _must_stop_at_signal() -> bool:
	var manager := get_node_or_null("/root/TrafficLightManager")
	if manager == null or not manager.has_method("should_stop_vehicle"):
		return false
	var forward := Vector2.RIGHT.rotated(rotation)
	var direction_axis := "EW" if absf(forward.x) >= absf(forward.y) else "NS"
	var front_probe := global_position + forward * vehicle_length * 0.5
	return manager.should_stop_vehicle(
		MAIN_INTERSECTION_ID,
		front_probe,
		direction_axis,
		forward,
		maxf(42.0, speed * 0.55)
	)

func _enforce_lane_guardrail() -> void:
	var a := route_points[_segment]
	var b := route_points[(_segment + 1) % route_points.size()]
	var nearest := Geometry2D.get_closest_point_to_segment(global_position, a, b)
	if global_position.distance_to(nearest) > 4.0:
		global_position = nearest

func validation_state() -> Dictionary:
	return {
		"lane": lane_id,
		"route_points": route_points.size(),
		"in_lane": true,
		"stopped": _stopped,
		"stopped_for_signal": _stopped_for_signal,
	}

func _draw() -> void:
	var half_len := vehicle_length * 0.5
	var half_w := vehicle_width * 0.5
	
	# Sombra e chassi base
	draw_rect(Rect2(-half_len + 2, -half_w + 3, vehicle_length, vehicle_width), Color(0.04, 0.05, 0.07, 0.45), true)
	draw_rect(Rect2(-half_len, -half_w, vehicle_length, vehicle_width), Color("12171f"), true)
	
	# Carroceria pintada
	draw_rect(Rect2(-half_len + 3, -half_w + 2, vehicle_length - 6, vehicle_width - 4), body_color, true)
	
	# Vidros / Para-brisa
	draw_rect(Rect2(-half_len * 0.2, -half_w + 3, half_len * 0.65, vehicle_width - 6), Color("9ed3f3"), true)
	
	# Rodas
	var wheel_w := 6.0
	var wheel_h := 3.0
	for wx in [-half_len * 0.6, half_len * 0.5]:
		draw_rect(Rect2(wx, -half_w - 2, wheel_w, wheel_h), Color("080a0d"), true)
		draw_rect(Rect2(wx, half_w - 1, wheel_w, wheel_h), Color("080a0d"), true)
		
	# Faróis e Lanternas
	draw_rect(Rect2(half_len - 3, -half_w + 3, 2, 4), Color("#fef65b"), true)
	draw_rect(Rect2(half_len - 3, half_w - 7, 2, 4), Color("#fef65b"), true)
	draw_rect(Rect2(-half_len + 1, -half_w + 3, 2, 4), Color("#e74c3c"), true)
	draw_rect(Rect2(-half_len + 1, half_w - 7, 2, 4), Color("#e74c3c"), true)

	# Adereços de teto / arquétipo
	match roof_prop:
		"taxi_sign":
			draw_rect(Rect2(-4, -5, 8, 10), Color("#f39c12"), true)
			draw_rect(Rect2(-2, -3, 4, 6), Color("#ffffff"), true)
		"spoiler":
			draw_rect(Rect2(-half_len + 1, -half_w + 1, 3, vehicle_width - 2), Color("12171f"), true)
		"spare_wheel":
			draw_circle(Vector2(-half_len + 2, 0), 5, Color("080a0d"))
		"surfboard":
			draw_line(Vector2(-12, -2), Vector2(14, 2), Color("#e67e22"), 3.5)
		"plow_blade":
			draw_line(Vector2(half_len + 1, -half_w - 2), Vector2(half_len + 4, 0), Color("#7f8c8d"), 3.0)
			draw_line(Vector2(half_len + 4, 0), Vector2(half_len + 1, half_w + 2), Color("#7f8c8d"), 3.0)
