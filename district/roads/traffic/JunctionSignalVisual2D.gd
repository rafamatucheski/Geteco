class_name JunctionSignalVisual2D
extends Node2D

## Top-down signal heads anchored exclusively to a canonical junction and its
## graph-provided approaches. No world coordinate is authored in this class.

const HOUSING_COLOR := Color("151a1f")
const POLE_COLOR := Color("667078")
const RED_ON := Color("ff3b30")
const YELLOW_ON := Color("ffd43b")
const GREEN_ON := Color("34d058")
const LAMP_OFF := Color("31383e")

var junction_id: StringName = &""
var junction_radius := 48.0
var approaches: Array = []
var road_states: Dictionary = {}


func configure(id: StringName, radius: float, source_approaches: Array) -> void:
	junction_id = id
	junction_radius = maxf(24.0, radius)
	approaches = source_approaches.duplicate(true)
	queue_redraw()


func set_road_states(states: Dictionary) -> void:
	road_states = states.duplicate()
	queue_redraw()


func _draw() -> void:
	for approach_value in approaches:
		var approach := approach_value as Dictionary
		var road_index := int(approach.get("road_index", -1))
		if road_index < 0:
			continue
		var tangent := _approach_tangent(approach)
		if tangent.is_zero_approx():
			continue
		# The head sits immediately outside the conflict radius, on the driver's
		# right. Both distances are derived from the junction clearance.
		var radial := -tangent.normalized()
		var lateral := radial.rotated(PI * 0.5)
		var pole_base := radial * (junction_radius + 10.0) + lateral * minf(20.0, junction_radius * 0.28)
		var head_center := pole_base - radial * 9.0
		draw_line(pole_base, head_center, POLE_COLOR, 3.0, true)
		draw_circle(head_center, 8.5, HOUSING_COLOR)
		var state := int(road_states.get(road_index, 0))
		var active_color := RED_ON
		if state == 1:
			active_color = YELLOW_ON
		elif state == 2:
			active_color = GREEN_ON
		draw_circle(head_center, 4.5, active_color)
		draw_arc(head_center, 6.3, 0.0, TAU, 16, LAMP_OFF.lightened(0.18), 1.0, true)


func _approach_tangent(approach: Dictionary) -> Vector2:
	var tangent: Vector2 = approach.get("tangent", Vector2.ZERO)
	if tangent.is_zero_approx() and approach.has("angle"):
		tangent = Vector2.RIGHT.rotated(float(approach.angle))
	var direction = approach.get("direction", 1)
	if direction is int or direction is float:
		if int(direction) < 0:
			tangent = -tangent
	elif String(direction).to_lower() in ["reverse", "backward", "inbound_reverse"]:
		tangent = -tangent
	return tangent.normalized()

