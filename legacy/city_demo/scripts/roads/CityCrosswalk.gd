@tool
class_name CityCrosswalk
extends Node2D

enum Orientation {
	HORIZONTAL,
	VERTICAL
}

@export var orientation: int = Orientation.HORIZONTAL:
	set(o):
		orientation = o
		queue_redraw()

@export var crossing_width: float = 96.0:
	set(w):
		crossing_width = maxf(w, 24.0)
		queue_redraw()

@export var crossing_depth: float = 24.0:
	set(d):
		crossing_depth = maxf(d, 8.0)
		queue_redraw()

@export_range(3, 24, 1) var stripe_count: int = 8:
	set(sc):
		stripe_count = sc
		queue_redraw()

@export var stripe_color: Color = Color("f1f5f9"):
	set(c):
		stripe_color = c
		queue_redraw()

@export var asphalt_background: bool = true:
	set(val):
		asphalt_background = val
		queue_redraw()

@export var asphalt_color: Color = Color("2d3139"):
	set(c):
		asphalt_color = c
		queue_redraw()

@export var has_stop_line: bool = true:
	set(val):
		has_stop_line = val
		queue_redraw()

@export var stop_line_offset: float = 16.0:
	set(off):
		stop_line_offset = off
		queue_redraw()

@export var has_tactile_paving: bool = true:
	set(val):
		has_tactile_paving = val
		queue_redraw()

func _ready() -> void:
	add_to_group("city_crosswalk")
	queue_redraw()

func _draw() -> void:
	var is_horiz := orientation == Orientation.HORIZONTAL
	var half_w := crossing_width * 0.5
	var half_d := crossing_depth * 0.5

	# 1. Background Asphalt
	if asphalt_background:
		if is_horiz:
			draw_rect(Rect2(-half_w, -half_d, crossing_width, crossing_depth), asphalt_color)
		else:
			draw_rect(Rect2(-half_d, -half_w, crossing_depth, crossing_width), asphalt_color)

	# 2. Zebra Stripes
	var start_pos := Vector2(-half_w * 0.85, 0.0) if is_horiz else Vector2(0.0, -half_w * 0.85)
	var end_pos := Vector2(half_w * 0.85, 0.0) if is_horiz else Vector2(0.0, half_w * 0.85)

	for i in range(stripe_count):
		var t := float(i) / float(stripe_count - 1) if stripe_count > 1 else 0.5
		var center := start_pos.lerp(end_pos, t)
		if is_horiz:
			var sw := minf(crossing_width / float(stripe_count * 2.0), 10.0)
			draw_rect(Rect2(center.x - sw * 0.5, -half_d * 0.85, sw, crossing_depth * 0.85), stripe_color)
		else:
			var sh := minf(crossing_width / float(stripe_count * 2.0), 10.0)
			draw_rect(Rect2(-half_d * 0.85, center.y - sh * 0.5, crossing_depth * 0.85, sh), stripe_color)

	# 3. Stop Line
	if has_stop_line:
		if is_horiz:
			draw_line(Vector2(0, -half_d - stop_line_offset), Vector2(half_w * 0.9, -half_d - stop_line_offset), stripe_color, 3.5)
		else:
			draw_line(Vector2(-half_d - stop_line_offset, -half_w * 0.9), Vector2(-half_d - stop_line_offset, 0), stripe_color, 3.5)

	# 4. Tactile Pedestrian Curb Warning Pads
	if has_tactile_paving:
		var pad_w := 14.0
		var pad_col := Color("eab308")
		if is_horiz:
			# Left sidewalk pad
			draw_rect(Rect2(-half_w - pad_w, -half_d, pad_w, crossing_depth), pad_col)
			# Right sidewalk pad
			draw_rect(Rect2(half_w, -half_d, pad_w, crossing_depth), pad_col)
		else:
			# Top sidewalk pad
			draw_rect(Rect2(-half_d, -half_w - pad_w, crossing_depth, pad_w), pad_col)
			# Bottom sidewalk pad
			draw_rect(Rect2(-half_d, half_w, crossing_depth, pad_w), pad_col)
