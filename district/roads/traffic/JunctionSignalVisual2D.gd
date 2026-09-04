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
const SIDEWALK_CLEARANCE := 10.0
const POLE_ARM_LENGTH := 12.0
const HOUSING_LENGTH := 29.0
const HOUSING_WIDTH := 11.0

var junction_id: StringName = &""
var junction_radius := 48.0
var approaches: Array = []
var road_states: Dictionary = {}


func _ready() -> void:
	add_to_group("junction_signal_visual")


func configure(id: StringName, radius: float, source_approaches: Array) -> void:
	junction_id = id
	junction_radius = maxf(24.0, radius)
	approaches = source_approaches.duplicate(true)
	queue_redraw()


func set_road_states(states: Dictionary) -> void:
	road_states = states.duplicate()
	queue_redraw()


func _draw() -> void:
	for layout_value in get_signal_layout():
		var layout := layout_value as Dictionary
		var pole_base: Vector2 = layout.pole_base
		var head_center: Vector2 = layout.head_center
		var housing_axis: Vector2 = layout.housing_axis
		var housing_normal := housing_axis.orthogonal()
		# A grounded mast and cantilever make the symbol read as roadside
		# equipment rather than a floating lamp in the asphalt.
		draw_circle(pole_base + Vector2(2.0, 2.0), 5.0, Color(0.02, 0.025, 0.03, 0.35))
		draw_circle(pole_base, 4.2, POLE_COLOR.darkened(0.18))
		draw_circle(pole_base, 2.4, POLE_COLOR.lightened(0.18))
		draw_line(pole_base, head_center, POLE_COLOR, 3.0, true)

		var housing := _oriented_rectangle(head_center, housing_axis, HOUSING_LENGTH, HOUSING_WIDTH)
		draw_colored_polygon(housing, HOUSING_COLOR)
		var housing_outline := housing.duplicate()
		housing_outline.append(housing[0])
		draw_polyline(housing_outline, POLE_COLOR.darkened(0.35), 1.5, true)

		var state := int(road_states.get(int(layout.road_index), 0))
		var lens_colors := [LAMP_OFF, LAMP_OFF, LAMP_OFF]
		lens_colors[clampi(state, 0, 2)] = [RED_ON, YELLOW_ON, GREEN_ON][clampi(state, 0, 2)]
		for lens_index in range(3):
			var lens_center := head_center + housing_axis * (float(lens_index) - 1.0) * 8.0
			draw_circle(lens_center + housing_normal * 0.4, 3.1, lens_colors[lens_index])
			draw_arc(lens_center, 3.6, 0.0, TAU, 12, Color("0d1115"), 1.0, true)


func get_signal_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for approach_value in approaches:
		var approach := approach_value as Dictionary
		var road_index := int(approach.get("road_index", -1))
		if road_index < 0:
			continue
		var tangent := _approach_tangent(approach)
		if tangent.is_zero_approx():
			continue
		var outward := -tangent
		# In Godot's y-down top view, +90 degrees is the driver's right.
		var driver_right := tangent.rotated(PI * 0.5).normalized()
		var road_width := maxf(24.0, float(approach.get("road_width", 96.0)))
		var lateral_distance := road_width * 0.5 + SIDEWALK_CLEARANCE
		var longitudinal_distance := junction_radius + maxf(8.0, road_width * 0.08)
		var pole_base := outward * longitudinal_distance + driver_right * lateral_distance
		# The housing reaches back only to the kerb edge; the mast remains fully
		# on the sidewalk and cannot land in a live lane.
		var head_center := pole_base - driver_right * POLE_ARM_LENGTH
		result.append({
			"road_index": road_index,
			"road_width": road_width,
			"entry_tangent": tangent,
			"driver_right": driver_right,
			"pole_base": pole_base,
			"head_center": head_center,
			"housing_axis": outward,
			"lateral_distance": lateral_distance,
		})
	return result


func _oriented_rectangle(center: Vector2, axis: Vector2, length: float, width: float) -> PackedVector2Array:
	var forward := axis.normalized() * length * 0.5
	var lateral := axis.normalized().orthogonal() * width * 0.5
	return PackedVector2Array([
		center - forward - lateral,
		center + forward - lateral,
		center + forward + lateral,
		center - forward + lateral,
	])


func _approach_tangent(approach: Dictionary) -> Vector2:
	# UnifiedRoadNetwork already publishes entry_tangent = base_tangent *
	# direction. Consuming it directly avoids reversing reverse approaches twice.
	var tangent: Vector2 = approach.get("entry_tangent", approach.get("tangent", Vector2.ZERO))
	if tangent.is_zero_approx() and approach.has("angle"):
		tangent = Vector2.RIGHT.rotated(float(approach.angle))
	return tangent.normalized()
