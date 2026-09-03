extends SceneTree

const DISTRICT_SCENE := preload("res://district/borough_one/DistrictOneComplete.tscn")
const SAFETY_SCRIPT := preload("res://district/roads/safety/DistrictRoadSafetySystem2D.gd")


func _initialize() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var district := DISTRICT_SCENE.instantiate()
	root.add_child(district)
	for _frame in 3:
		await process_frame
	var safety := SAFETY_SCRIPT.new() as DistrictRoadSafetySystem2D
	safety.name = "DistrictRoadSafetySystem"
	district.add_child(safety)
	for _frame in 4:
		await process_frame
	safety.rebuild_from_sources()
	await process_frame
	var data := safety.get_safety_data()
	var graph_data: Dictionary = district.get_node("UnifiedRoadNetwork").get_graph_data()
	for road in graph_data.roads:
		if String(road.id) in ["Bairro1Expansion/gateway_spine", "Bairro1Expansion/north_link"]:
			print("  ROAD_GEOMETRY: %s control=%s first=%s last=%s bounds=%s" % [road.id, road.control, road.points[0], road.points[-1], _bounds(road.points)])
	print("ROAD_SAFETY_AUDIT: %s" % safety.get_validation_summary())
	for crossing in data.rail_level_crossings:
		print("  LEVEL: %s road=%s road_t=%.4f rail_t=%.4f position=%s" % [crossing.id, crossing.road_id, crossing.road_t, crossing.rail_t, crossing.position])
	for crossing in data.grade_separated_rail_crossings:
		print("  GRADE_SEPARATED: %s road=%s position=%s" % [crossing.id, crossing.road_id, crossing.position])
	for warning in data.validation_warnings:
		print("  WARNING: %s" % warning)
	if not data.validation_errors.is_empty():
		for error in data.validation_errors:
			print("  ERROR: %s" % error)
			push_error("ROAD_SAFETY_AUDIT: %s" % error)
		quit(1)
		return
	print("ROAD_SAFETY_AUDIT_OK")
	quit(0)


func _bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(point)
	return result
