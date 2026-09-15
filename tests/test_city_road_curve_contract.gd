extends SceneTree

const CITY_ROAD_CURVE_SCRIPT := preload("res://legacy/city_demo/scripts/roads/CityRoadCurve.gd")
const UNIFIED_ROAD_NETWORK_SCRIPT := preload("res://geodata/roads/UnifiedRoadNetwork2D.gd")

var _failures: Array[String] = []


class CrossRoadProvider:
	extends Node2D

	func get_road_graph_definitions() -> Array[Dictionary]:
		return [{
			"id": "cross_road",
			"points": PackedVector2Array([Vector2(0.0, -400.0), Vector2(0.0, 600.0)]),
			"width": 96.0,
			"open_start": true,
			"open_end": true,
		}]


func _initialize() -> void:
	call_deferred("_run_contract")


func _run_contract() -> void:
	var fixture := Node2D.new()
	fixture.name = "CityRoadCurveContractFixture"
	root.add_child(fixture)

	var road_curve := CITY_ROAD_CURVE_SCRIPT.new() as CityRoadCurve
	road_curve.name = "SCurve"
	road_curve.open_start = true
	road_curve.open_end = true
	fixture.add_child(road_curve)
	await process_frame

	var control_points := road_curve.get_node_or_null("ControlPoints") as Node2D
	_check(control_points != null, "CityRoadCurve did not create ControlPoints")
	if control_points == null:
		_finish(fixture)
		return
	var point_0 := control_points.get_node_or_null("Point_0") as Marker2D
	var point_1 := control_points.get_node_or_null("Point_1") as Marker2D
	var point_2 := control_points.get_node_or_null("Point_2") as Marker2D
	_check(point_0 != null and point_1 != null and point_2 != null, "default Point_0..Point_2 markers are missing")
	if point_0 == null or point_1 == null or point_2 == null:
		_finish(fixture)
		return
	point_0.position = Vector2(-300.0, 0.0)
	point_1.position = Vector2(0.0, 160.0)
	point_2.position = Vector2(300.0, -160.0)

	var definitions: Array[Dictionary] = road_curve.get_road_graph_definitions()
	_check(definitions.size() == 1, "provider must return exactly one road definition")
	if definitions.is_empty():
		_finish(fixture)
		return
	var definition := definitions[0]
	_check(_has_required_contract(definition), "road definition fields or types do not match UnifiedRoadNetwork2D")
	var source_points: PackedVector2Array = definition.get("points", PackedVector2Array())
	_check(source_points.size() == 3, "road definition must publish the three default control points")
	if source_points.size() == 3:
		var first_leg := source_points[1] - source_points[0]
		var second_leg := source_points[2] - source_points[1]
		_check(not is_zero_approx(first_leg.cross(second_leg)), "S-curve fixture control points must be non-collinear")
	_check((definition.get("lanes", []) as Array).size() == 2, "curve must publish forward and reverse lanes")

	var cross_road := CrossRoadProvider.new()
	cross_road.name = "CrossRoad"
	fixture.add_child(cross_road)

	var network := UNIFIED_ROAD_NETWORK_SCRIPT.new() as UnifiedRoadNetwork2D
	network.name = "UnifiedRoadNetwork"
	network.provider_paths = [NodePath("../SCurve"), NodePath("../CrossRoad")]
	fixture.add_child(network)
	for _frame in range(3):
		await process_frame

	var graph_data: Dictionary = network.get_graph_data()
	var curve_road := _find_graph_road(graph_data.get("roads", []) as Array, "SCurve/s_curve")
	_check(not curve_road.is_empty(), "UnifiedRoadNetwork2D did not collect the CityRoadCurve provider")
	if not curve_road.is_empty():
		_check((curve_road.get("control", PackedVector2Array()) as PackedVector2Array).size() == 3, "network lost curve control points")
		_check((curve_road.get("points", PackedVector2Array()) as PackedVector2Array).size() > 3, "network did not bake the control points into a curve")
		_check(is_equal_approx(float(curve_road.get("width", 0.0)), road_curve.road_width), "network did not preserve road width")
		_check((curve_road.get("lanes", []) as Array).size() == 2, "network did not build both curve lanes")
	_check(not (graph_data.get("junctions", []) as Array).is_empty(), "crossing fixture did not produce a real junction")
	_check(not (graph_data.get("lane_connections", []) as Array).is_empty(), "crossing fixture did not produce navigable lane connections")

	var validation_errors: Array[String] = network.get_validation_errors()
	var disconnected_errors: Array[String] = []
	for validation_error in validation_errors:
		if validation_error.begins_with("Disconnected endpoint:"):
			disconnected_errors.append(validation_error)
	_check(disconnected_errors.is_empty(), "open endpoints produced disconnected warnings: %s" % [disconnected_errors])
	_check(validation_errors.is_empty(), "unified curve fixture validation failed: %s" % [validation_errors])

	print("CITY_ROAD_CURVE_CONTRACT: controls=%d baked=%d junctions=%d lanes=%d errors=%d failures=%d" % [
		source_points.size(),
		(curve_road.get("points", PackedVector2Array()) as PackedVector2Array).size(),
		(graph_data.get("junctions", []) as Array).size(),
		(graph_data.get("lanes", []) as Array).size(),
		validation_errors.size(),
		_failures.size(),
	])
	_finish(fixture)


func _has_required_contract(definition: Dictionary) -> bool:
	for key in ["id", "points", "width", "lanes", "open_start", "open_end"]:
		if not definition.has(key):
			return false
	if not definition["id"] is String:
		return false
	if not definition["points"] is PackedVector2Array:
		return false
	if typeof(definition["width"]) != TYPE_FLOAT:
		return false
	if not definition["lanes"] is Array:
		return false
	if typeof(definition["open_start"]) != TYPE_BOOL or typeof(definition["open_end"]) != TYPE_BOOL:
		return false
	for lane_value in definition["lanes"]:
		if not lane_value is Dictionary:
			return false
		var lane := lane_value as Dictionary
		if not lane.has("lane_id") or not lane.has("offset") or not lane.has("direction"):
			return false
	return true


func _find_graph_road(roads: Array, road_id: String) -> Dictionary:
	for road_value in roads:
		var road := road_value as Dictionary
		if String(road.get("id", "")) == road_id:
			return road
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(fixture: Node) -> void:
	for failure in _failures:
		push_error("CITY_ROAD_CURVE_CONTRACT: %s" % failure)
	root.remove_child(fixture)
	fixture.free()
	quit(0 if _failures.is_empty() else 1)
