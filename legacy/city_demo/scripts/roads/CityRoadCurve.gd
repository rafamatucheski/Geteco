@tool
class_name CityRoadCurve
extends Node2D

const ROAD_SEGMENT_SCRIPT := preload("res://legacy/city_demo/scripts/roads/CityRoadSegment.gd")
const RoadType = ROAD_SEGMENT_SCRIPT.RoadType

const DEFAULT_LENGTH := 600.0
const GUIDE_LINE_COLOR := Color("dbc85c")
const GUIDE_POINT_COLOR := Color("f1f5f9")
const TRAFFIC_DIRECTION_FORWARD := 1
const TRAFFIC_DIRECTION_REVERSE := -1

@export var road_type: int = RoadType.TWO_LANE:
	set(value):
		road_type = value
		_apply_type_defaults()

@export var road_width: float = 96.0:
	set(value):
		road_width = maxf(value, 32.0)
		queue_redraw()

@export var open_start: bool = false
@export var open_end: bool = false

var _control_points: Node2D


func _ready() -> void:
	_ensure_control_points()
	set_process(Engine.is_editor_hint())
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _ensure_control_points() -> void:
	_control_points = get_node_or_null("ControlPoints") as Node2D
	if _control_points == null:
		_control_points = Node2D.new()
		_control_points.name = "ControlPoints"
		add_child(_control_points)
		_assign_editor_owner(_control_points)

	for index in range(3):
		var point_name := "Point_%d" % index
		var marker := _control_points.get_node_or_null(point_name) as Marker2D
		if marker == null:
			marker = Marker2D.new()
			marker.name = point_name
			marker.position = Vector2((float(index) - 1.0) * DEFAULT_LENGTH * 0.5, 0.0)
			_control_points.add_child(marker)
		_assign_editor_owner(marker)


func add_control_point() -> void:
	_ensure_control_points()
	var points := _get_control_point_markers()
	var marker := Marker2D.new()
	marker.name = "Point_%d" % _next_control_point_index(points)
	if points.size() >= 2:
		var previous := points[points.size() - 2]
		var last := points[points.size() - 1]
		marker.position = last.position + (last.position - previous.position) * 0.5
	elif points.size() == 1:
		marker.position = points[0].position + Vector2(DEFAULT_LENGTH * 0.5, 0.0)
	_control_points.add_child(marker)
	_assign_editor_owner(marker)
	queue_redraw()


func get_road_graph_definitions() -> Array[Dictionary]:
	_ensure_control_points()
	var points := PackedVector2Array()
	for marker in _get_control_point_markers():
		points.append(to_local(marker.global_position))
	var lane_offset := road_width * 0.25
	var lanes := [
		{
			"lane_id": "forward_01",
			"offset": lane_offset,
			"direction": TRAFFIC_DIRECTION_FORWARD,
			"direction_name": "forward",
		},
		{
			"lane_id": "reverse_01",
			"offset": -lane_offset,
			"direction": TRAFFIC_DIRECTION_REVERSE,
			"direction_name": "reverse",
		},
	]
	return [{
		"id": String(name).to_snake_case(),
		"points": points,
		"width": road_width,
		"lanes": lanes,
		"open_start": open_start,
		"open_end": open_end,
	}]


func _get_control_point_markers() -> Array[Marker2D]:
	var points: Array[Marker2D] = []
	if _control_points == null:
		return points
	for child in _control_points.get_children():
		if child is Marker2D and String(child.name).begins_with("Point_"):
			points.append(child as Marker2D)
	points.sort_custom(func(first: Marker2D, second: Marker2D) -> bool:
		return _control_point_index(first) < _control_point_index(second)
	)
	return points


func _control_point_index(marker: Marker2D) -> int:
	return int(String(marker.name).trim_prefix("Point_"))


func _next_control_point_index(points: Array[Marker2D]) -> int:
	if points.is_empty():
		return 0
	return _control_point_index(points[-1]) + 1


func _assign_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var edited_scene_root := get_tree().edited_scene_root
	if edited_scene_root != null and (node == edited_scene_root or edited_scene_root.is_ancestor_of(node)):
		node.owner = edited_scene_root


func _apply_type_defaults() -> void:
	match road_type:
		RoadType.TWO_LANE:
			road_width = 96.0
		RoadType.FOUR_LANE:
			road_width = 160.0
		RoadType.ONE_WAY:
			road_width = 72.0
		RoadType.ALLEY:
			road_width = 48.0
		RoadType.BOULEVARD_MEDIAN:
			road_width = 210.0


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var points := PackedVector2Array()
	for marker in _get_control_point_markers():
		points.append(to_local(marker.global_position))
	if points.size() >= 2:
		draw_polyline(points, GUIDE_LINE_COLOR, 2.0, true)
	for point in points:
		draw_circle(point, 4.0, GUIDE_POINT_COLOR)
