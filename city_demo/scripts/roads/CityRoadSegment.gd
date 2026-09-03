@tool
class_name CityRoadSegment
extends Node2D

enum RoadType {
	TWO_LANE,
	FOUR_LANE,
	ONE_WAY,
	ALLEY,
	BOULEVARD_MEDIAN
}

enum Orientation {
	HORIZONTAL,
	VERTICAL,
	CUSTOM_ANGLE
}

const TREE_TEXTURE: Texture2D = preload("res://city_demo/art/tree-street-small.png")
const LAMP_SCENE: PackedScene = preload("res://StreetLamp.tscn")

# --- ROAD DIMENSIONS & CONFIG ---
@export var road_type: int = RoadType.TWO_LANE:
	set(rt):
		road_type = rt
		_apply_type_defaults()
		_update_road()

@export var orientation: int = Orientation.HORIZONTAL:
	set(o):
		orientation = o
		_update_road()

@export_range(0.0, 360.0, 1.0) var custom_angle_degrees: float = 0.0:
	set(ang):
		custom_angle_degrees = ang
		_update_road()

@export var length: float = 600.0:
	set(l):
		length = maxf(l, 32.0)
		_update_road()

## Optional anchors turn this segment into a live connection.  Assign an
## intersection (or any Node2D) at each end and use `update_connection_now`.
## The road will span the two nodes, including their current positions, so
## moving a junction in the 2D editor is all that is needed to reshape it.
@export_group("Connections")
@export var start_anchor: NodePath:
	set(value):
		start_anchor = value

@export var end_anchor: NodePath:
	set(value):
		end_anchor = value

@export var update_connection_now: bool = false:
	set(value):
		if value:
			update_connection_now = false
			snap_between_anchors()

@export var road_width: float = 96.0:
	set(rw):
		road_width = maxf(rw, 32.0)
		_update_road()

@export var render_legacy_road: bool = true:
	set(value):
		render_legacy_road = value
		queue_redraw()

# --- MARKINGS ---
@export_group("Markings")
@export var has_yellow_center: bool = true:
	set(val):
		has_yellow_center = val
		queue_redraw()

@export var double_yellow_center: bool = false:
	set(val):
		double_yellow_center = val
		queue_redraw()

@export var has_white_edges: bool = true:
	set(val):
		has_white_edges = val
		queue_redraw()

@export var has_lane_dividers: bool = false:
	set(val):
		has_lane_dividers = val
		queue_redraw()

# --- SIDEWALKS & CURBS ---
@export_group("Sidewalks")
@export var has_sidewalk_left: bool = true:
	set(val):
		has_sidewalk_left = val
		_update_road()

@export var has_sidewalk_right: bool = true:
	set(val):
		has_sidewalk_right = val
		_update_road()

@export var sidewalk_width: float = 28.0:
	set(sw):
		sidewalk_width = maxf(sw, 8.0)
		_update_road()

# --- COLORS ---
@export_group("Colors")
@export var asphalt_color: Color = Color("2d3139"):
	set(c):
		asphalt_color = c
		queue_redraw()

@export var sidewalk_color: Color = Color("94a3b8"):
	set(c):
		sidewalk_color = c
		queue_redraw()

@export var curb_color: Color = Color("cbd5e1"):
	set(c):
		curb_color = c
		queue_redraw()

@export var marking_yellow: Color = Color("dbc85c"):
	set(c):
		marking_yellow = c
		queue_redraw()

@export var marking_white: Color = Color("f1f5f9"):
	set(c):
		marking_white = c
		queue_redraw()

# --- STREET FURNITURE & DECOR ---
@export_group("Decorations")
@export var add_street_lamps: bool = true:
	set(val):
		add_street_lamps = val
		_update_decor()

@export var lamp_spacing: float = 180.0:
	set(val):
		lamp_spacing = maxf(val, 60.0)
		_update_decor()

@export var add_trees: bool = false:
	set(val):
		add_trees = val
		_update_decor()

@export var tree_spacing: float = 140.0:
	set(val):
		tree_spacing = maxf(val, 60.0)
		_update_decor()

# --- AI & NAVIGATION GENERATION ---
@export_group("AI & Navigation")
@export var generate_traffic_paths: bool = true:
	set(val):
		generate_traffic_paths = val
		_update_traffic_paths()

var decor_container: Node2D
var traffic_lanes_container: Node2D

func _ready() -> void:
	_update_road()
	add_to_group("city_road_segment")
	if not Engine.is_editor_hint():
		snap_between_anchors()

## Aligns the road centre, angle and length with its two assigned anchors.
## This is deliberately an explicit Inspector action in the editor: it never
## overwrites an artist's manual move while they are dragging a road segment.
func snap_between_anchors() -> void:
	var start := get_node_or_null(start_anchor) as Node2D
	var finish := get_node_or_null(end_anchor) as Node2D
	if start == null or finish == null or start == finish:
		return
	var delta := finish.global_position - start.global_position
	if delta.length() < 32.0:
		return
	global_position = start.global_position.lerp(finish.global_position, 0.5)
	length = delta.length()
	orientation = Orientation.CUSTOM_ANGLE
	custom_angle_degrees = rad_to_deg(delta.angle())
	_update_road()

func get_start_point() -> Vector2:
	return to_global(Vector2(-length * 0.5, 0.0))

func get_end_point() -> Vector2:
	return to_global(Vector2(length * 0.5, 0.0))

func get_road_graph_definitions() -> Array[Dictionary]:
	return [{
		"id": String(name).to_snake_case(),
		"points": PackedVector2Array([Vector2(-length * 0.5, 0.0), Vector2(length * 0.5, 0.0)]),
		"width": road_width,
		"open_start": false,
		"open_end": false,
	}]

func _apply_type_defaults() -> void:
	match road_type:
		RoadType.TWO_LANE:
			road_width = 96.0
			has_yellow_center = true
			double_yellow_center = false
			has_white_edges = true
			has_lane_dividers = false
		RoadType.FOUR_LANE:
			road_width = 160.0
			has_yellow_center = true
			double_yellow_center = true
			has_white_edges = true
			has_lane_dividers = true
		RoadType.ONE_WAY:
			road_width = 72.0
			has_yellow_center = false
			double_yellow_center = false
			has_white_edges = true
			has_lane_dividers = true
		RoadType.ALLEY:
			road_width = 48.0
			has_yellow_center = false
			double_yellow_center = false
			has_white_edges = false
			has_lane_dividers = false
			has_sidewalk_left = false
			has_sidewalk_right = false
		RoadType.BOULEVARD_MEDIAN:
			road_width = 210.0
			has_yellow_center = true
			double_yellow_center = true
			has_white_edges = true
			has_lane_dividers = true

func _update_road() -> void:
	match orientation:
		Orientation.HORIZONTAL:
			rotation_degrees = 0.0
		Orientation.VERTICAL:
			rotation_degrees = 90.0
		Orientation.CUSTOM_ANGLE:
			rotation_degrees = custom_angle_degrees

	_update_decor()
	_update_traffic_paths()
	queue_redraw()

func _update_decor() -> void:
	if decor_container == null:
		decor_container = get_node_or_null("DecorContainer") as Node2D
		if decor_container == null:
			decor_container = Node2D.new()
			decor_container.name = "DecorContainer"
			add_child(decor_container)

	for child in decor_container.get_children():
		child.queue_free()

	var half_w := road_width * 0.5

	# 1. Street Lamps
	if add_street_lamps and LAMP_SCENE != null:
		var cursor := lamp_spacing * 0.5
		while cursor < length:
			var lx := cursor - length * 0.5
			if has_sidewalk_left:
				var lamp_left = LAMP_SCENE.instantiate()
				lamp_left.position = Vector2(lx, -half_w - sidewalk_width * 0.45)
				if "is_facing_south" in lamp_left:
					lamp_left.is_facing_south = true
				decor_container.add_child(lamp_left)

			if has_sidewalk_right:
				var lamp_right = LAMP_SCENE.instantiate()
				lamp_right.position = Vector2(lx, half_w + sidewalk_width * 0.45)
				if "is_facing_south" in lamp_right:
					lamp_right.is_facing_south = false
				decor_container.add_child(lamp_right)

			cursor += lamp_spacing

	# 2. Sidewalk Trees
	if add_trees and TREE_TEXTURE != null:
		var cursor := tree_spacing * 0.5
		while cursor < length:
			var tx := cursor - length * 0.5
			if has_sidewalk_left:
				var tree_l := Sprite2D.new()
				tree_l.texture = TREE_TEXTURE
				tree_l.position = Vector2(tx, -half_w - sidewalk_width * 0.55)
				var s := 0.045
				tree_l.scale = Vector2(s, s)
				tree_l.z_index = -3
				decor_container.add_child(tree_l)

			if has_sidewalk_right:
				var tree_r := Sprite2D.new()
				tree_r.texture = TREE_TEXTURE
				tree_r.position = Vector2(tx, half_w + sidewalk_width * 0.55)
				var s := 0.045
				tree_r.scale = Vector2(s, s)
				tree_r.z_index = -3
				decor_container.add_child(tree_r)

			cursor += tree_spacing

func _update_traffic_paths() -> void:
	if not generate_traffic_paths:
		if traffic_lanes_container != null:
			traffic_lanes_container.queue_free()
			traffic_lanes_container = null
		return

	if traffic_lanes_container == null:
		traffic_lanes_container = get_node_or_null("TrafficLanes") as Node2D
		if traffic_lanes_container == null:
			traffic_lanes_container = Node2D.new()
			traffic_lanes_container.name = "TrafficLanes"
			add_child(traffic_lanes_container)

	for child in traffic_lanes_container.get_children():
		child.queue_free()

	var half_len := length * 0.5
	var lane_offset := road_width * 0.25

	# Forward Lane (East / Left to Right)
	var path_forward := Path2D.new()
	path_forward.name = "Lane_Forward"
	var curve_f := Curve2D.new()
	curve_f.add_point(Vector2(-half_len, lane_offset))
	curve_f.add_point(Vector2(half_len, lane_offset))
	path_forward.curve = curve_f
	traffic_lanes_container.add_child(path_forward)

	# Backward Lane (West / Right to Left)
	if road_type != RoadType.ONE_WAY:
		var path_backward := Path2D.new()
		path_backward.name = "Lane_Backward"
		var curve_b := Curve2D.new()
		curve_b.add_point(Vector2(half_len, -lane_offset))
		curve_b.add_point(Vector2(-half_len, -lane_offset))
		path_backward.curve = curve_b
		traffic_lanes_container.add_child(path_backward)

func _draw() -> void:
	if not render_legacy_road:
		return
	var half_len := length * 0.5
	var half_w := road_width * 0.5

	# 1. Sidewalks & Curbs
	if has_sidewalk_left:
		var sw_rect := Rect2(-half_len, -half_w - sidewalk_width, length, sidewalk_width)
		draw_rect(sw_rect, sidewalk_color)
		# Curb edge line
		draw_line(Vector2(-half_len, -half_w), Vector2(half_len, -half_w), curb_color, 2.5)

	if has_sidewalk_right:
		var sw_rect := Rect2(-half_len, half_w, length, sidewalk_width)
		draw_rect(sw_rect, sidewalk_color)
		# Curb edge line
		draw_line(Vector2(-half_len, half_w), Vector2(half_len, half_w), curb_color, 2.5)

	# 2. Asphalt Body
	var road_rect := Rect2(-half_len, -half_w, length, road_width)
	draw_rect(road_rect, asphalt_color)

	# 3. Outer Solid White Lines
	if has_white_edges:
		var shoulder_inset := 4.0
		draw_line(Vector2(-half_len, -half_w + shoulder_inset), Vector2(half_len, -half_w + shoulder_inset), marking_white, 2.0)
		draw_line(Vector2(-half_len, half_w - shoulder_inset), Vector2(half_len, half_w - shoulder_inset), marking_white, 2.0)

	# 4. Multi-Lane White Dividers
	if has_lane_dividers:
		var lane_offset := road_width * 0.25
		_draw_dashed_line(Vector2(-half_len, -lane_offset), Vector2(half_len, -lane_offset), marking_white, 16.0, 16.0, 1.5)
		_draw_dashed_line(Vector2(-half_len, lane_offset), Vector2(half_len, lane_offset), marking_white, 16.0, 16.0, 1.5)

	# 5. Central Boulevard Median or Yellow Lines
	if road_type == RoadType.BOULEVARD_MEDIAN:
		var med_w := 24.0
		var med_rect := Rect2(-half_len, -med_w * 0.5, length, med_w)
		draw_rect(med_rect, Color("4d7c0f"))
		draw_line(Vector2(-half_len, -med_w * 0.5), Vector2(half_len, -med_w * 0.5), curb_color, 2.0)
		draw_line(Vector2(-half_len, med_w * 0.5), Vector2(half_len, med_w * 0.5), curb_color, 2.0)
	elif has_yellow_center:
		if double_yellow_center:
			draw_line(Vector2(-half_len, -3), Vector2(half_len, -3), marking_yellow, 2.0)
			draw_line(Vector2(-half_len, 3), Vector2(half_len, 3), marking_yellow, 2.0)
		else:
			_draw_dashed_line(Vector2(-half_len, 0), Vector2(half_len, 0), marking_yellow, 22.0, 22.0, 2.0)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash_len: float, gap_len: float, width: float) -> void:
	var total_len := from.distance_to(to)
	var dir := from.direction_to(to)
	var cursor := 0.0
	while cursor < total_len:
		var end_cursor := minf(cursor + dash_len, total_len)
		draw_line(from + dir * cursor, from + dir * end_cursor, color, width)
		cursor += dash_len + gap_len
