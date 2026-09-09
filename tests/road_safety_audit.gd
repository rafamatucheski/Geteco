extends SceneTree

const DISTRICT_SCENE := preload("res://legacy/district/borough_one/DistrictOneComplete.tscn")
const SAFETY_SCRIPT := preload("res://world/shared/roads/safety/DistrictRoadSafetySystem2D.gd")


func _initialize() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	var district := DISTRICT_SCENE.instantiate()
	root.add_child(district)
	for _frame in 3:
		await process_frame
	var safety := district.get_node_or_null("DistrictRoadSafetySystem") as DistrictRoadSafetySystem2D
	if safety == null:
		safety = SAFETY_SCRIPT.new() as DistrictRoadSafetySystem2D
		safety.name = "DistrictRoadSafetySystem"
		district.add_child(safety)
	for _frame in 4:
		await process_frame
	safety.rebuild_from_sources()
	await process_frame
	var data := safety.get_safety_data()
	print("ROAD_SAFETY_AUDIT: %s" % safety.get_validation_summary())
	for crossing in data.rail_level_crossings:
		print("  LEVEL: %s road=%s road_t=%.4f rail_t=%.4f position=%s" % [crossing.id, crossing.road_id, crossing.road_t, crossing.rail_t, crossing.position])
	for crossing in data.grade_separated_rail_crossings:
		print("  GRADE_SEPARATED: %s road=%s position=%s" % [crossing.id, crossing.road_id, crossing.position])
	for warning in data.validation_warnings:
		print("  WARNING: %s" % warning)
	var exit_code := 0
	var parked_rail_conflicts := _parked_vehicle_rail_conflicts(district)
	print("  PARKED_RAIL_CONFLICTS: %d" % parked_rail_conflicts.size())
	for conflict in parked_rail_conflicts:
		print("  ERROR: parked vehicle intersects canonical railway: %s" % conflict)
		push_error("ROAD_SAFETY_AUDIT: parked vehicle intersects canonical railway: %s" % conflict)
		exit_code = 1
	if not data.validation_errors.is_empty():
		for error in data.validation_errors:
			print("  ERROR: %s" % error)
			push_error("ROAD_SAFETY_AUDIT: %s" % error)
		exit_code = 1
	else:
		print("ROAD_SAFETY_AUDIT_OK")
	root.remove_child(district)
	district.free()
	await process_frame
	quit(exit_code)


func _parked_vehicle_rail_conflicts(district: Node) -> Array[String]:
	var result: Array[String] = []
	var rail_line := district.get_node_or_null("DistrictRailLine")
	if rail_line == null or not rail_line.has_method("get_rail_graph_data"):
		result.append("rail geodata unavailable")
		return result
	var rail_data := rail_line.call("get_rail_graph_data") as Dictionary
	var rail_points: PackedVector2Array = rail_data.get("global_points", PackedVector2Array())
	var half_width := float(rail_data.get("ballast_width", 54.0)) * 0.5 + 3.0
	var rail_surfaces := Geometry2D.offset_polyline(
		rail_points, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND
	)
	for candidate in get_nodes_in_group("district_one_parked"):
		if not candidate is Node2D or not district.is_ancestor_of(candidate):
			continue
		var footprint := _vehicle_footprint(candidate as Node2D)
		for surface_value in rail_surfaces:
			var surface := surface_value as PackedVector2Array
			if not Geometry2D.intersect_polygons(footprint, surface).is_empty():
				result.append(String(candidate.get_path()))
				break
	return result


func _vehicle_footprint(vehicle: Node2D) -> PackedVector2Array:
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	var rectangle: RectangleShape2D = null
	if collision != null and collision.shape is RectangleShape2D:
		rectangle = collision.shape as RectangleShape2D
	var size := rectangle.size if rectangle != null else Vector2(72.0, 36.0)
	var source := collision as Node2D if collision != null else vehicle
	var half := size * 0.5
	return PackedVector2Array([
		source.to_global(Vector2(-half.x, -half.y)),
		source.to_global(Vector2(half.x, -half.y)),
		source.to_global(Vector2(half.x, half.y)),
		source.to_global(Vector2(-half.x, half.y)),
	])
