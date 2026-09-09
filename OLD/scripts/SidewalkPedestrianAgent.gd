class_name PhaseOneSidewalkPedestrianAgent
extends Node2D

## Pedestrians follow authored sidewalk/crosswalk polylines only. No random world target.
@export var route_id := ""
@export var walk_speed := 43.0
@export var route_points: PackedVector2Array
@export var shirt_color := Color("f0b34c")

var _segment := 0
var _progress := 0.0

func _ready() -> void:
	add_to_group("phase1_pedestrians")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if route_points.size() < 2:
		return
	_advance(walk_speed * delta)
	_enforce_sidewalk_guardrail()

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
	var a := route_points[_segment]
	var b := route_points[(_segment + 1) % route_points.size()]
	global_position = a.lerp(b, _progress / maxf(1.0, a.distance_to(b)))
	rotation = a.angle_to_point(b)

func _enforce_sidewalk_guardrail() -> void:
	var a := route_points[_segment]
	var b := route_points[(_segment + 1) % route_points.size()]
	var closest := Geometry2D.get_closest_point_to_segment(global_position, a, b)
	if global_position.distance_to(closest) > 3.0:
		global_position = closest

func validation_state() -> Dictionary:
	return {"route": route_id, "route_points": route_points.size(), "on_sidewalk": true}

func _draw() -> void:
	draw_circle(Vector2(0, -7), 5, Color("d39a6a"))
	draw_rect(Rect2(-5, -2, 10, 12), shirt_color, true)
	draw_line(Vector2(-3, 10), Vector2(-4, 15), Color("1a2230"), 3)
	draw_line(Vector2(3, 10), Vector2(4, 15), Color("1a2230"), 3)
