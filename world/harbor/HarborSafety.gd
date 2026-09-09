@tool
extends "res://world/shared/roads/safety/DistrictRoadSafetySystem2D.gd"

## Crosswalks belong to actual incoming junction arms, never a second painted
## coordinate map. Reuses the live game's detection, signals and vehicle yield.
class HarborCrossing extends RoadCrossingArea2D:
	func should_stop_vehicle(vehicle: Node = null) -> bool:
		# A committed turn must clear its EXIT zebra before all-red can grant a
		# pedestrian phase. Stopping its reservation owner there creates a cycle:
		# pedestrians wait for the car, while the car waits for pedestrians.
		# This exemption belongs to one vehicle ID, never the whole road phase.
		if not _pedestrian_permitted and is_instance_valid(vehicle) and is_instance_valid(_signal_controller):
			var state: Dictionary = _signal_controller.get_junction_snapshot(junction_id)
			if int(state.get("reservation_owner", 0)) == vehicle.get_instance_id():
				return false
		return super.should_stop_vehicle(vehicle)


func _init() -> void:
	road_graph_path = NodePath("../RoadNetwork")
	rail_line_path = NodePath("../FreightRail")
	elevated_highway_path = NodePath()


func _build_pedestrian_crossings(road_graph: Node2D, graph_data: Dictionary, roads: Array, junctions: Array) -> void:
	super._build_pedestrian_crossings(road_graph, graph_data, roads, junctions)
	# Keep the production builder's canonical projection and validation intact;
	# replace only its runtime priority policy before the first physics tick.
	for index in _crosswalk_nodes.size():
		var original := _crosswalk_nodes[index]
		var data := original.get_crossing_data()
		data.position = original.position
		data.road_tangent = Vector2.RIGHT.rotated(original.rotation)
		data.sidewalk_reach = original.sidewalk_reach
		data.crossing_depth = original.crossing_depth
		data.approach_depth = original.approach_depth
		var junction_index := int(original.get_meta("junction_index", -1))
		var generated := original.get_parent()
		var crossing := HarborCrossing.new()
		crossing.name = original.name
		crossing.z_index = original.z_index
		generated.remove_child(original)
		original.free()
		generated.add_child(crossing)
		crossing.configure(data)
		crossing.set_meta("junction_index", junction_index)
		crossing.pedestrian_request.connect(_on_crossing_pedestrian_request)
		_crosswalk_nodes[index] = crossing
		_bind_discovered_signal_controller(crossing)


func _collect_pedestrian_references(graph_data: Dictionary) -> Array[Dictionary]:
	var references: Array[Dictionary] = []
	var lengths := {}
	for road in graph_data.get("roads", []):
		# Ashbend's ring splits are topology seams, not four signalized street
		# intersections. Two authored unsignalized crossings replace zebra fans.
		var short_id := String(road.id).get_file()
		if short_id == "cobra_approach" or short_id == "cobra_court_northwest":
			references.append({"id": "ashbend_crossing_" + short_id, "road_id": String(road.id), "t": 0.78 if short_id == "cobra_approach" else 0.90, "crossing_depth": 26.0, "approach_depth": 90.0, "sidewalk_reach": 42.0})
		var points: PackedVector2Array = road.points
		var length := 0.0
		for index in range(points.size() - 1):
			length += points[index].distance_to(points[index + 1])
		lengths[String(road.id)] = length
	for junction in graph_data.get("junctions", []):
		if not bool(junction.get("signalized", false)):
			continue
		for approach in junction.get("approaches", []):
			var road_id := String(approach.road_id)
			var length := float(lengths.get(road_id, 0.0))
			if length <= 0.0:
				continue
			var setback := maxf(24.0, float(junction.radius) - 8.0)
			var road_t := float(approach.road_progress) - float(approach.direction) * setback / length
			references.append({
				"id": "harbor_crossing_%s_%s_%d" % [String(junction.id), _safe_name(road_id), int(approach.direction)],
				"road_id": road_id, "t": road_t,
				"junction_id": String(junction.id), "crossing_depth": 30.0,
				"approach_depth": 150.0, "sidewalk_reach": 42.0,
			})
	return references


func _detect_and_build_rail_crossings(road_graph: Node2D, roads: Array, rail_line: Node2D) -> void:
	var rail_data: Dictionary = rail_line.get_rail_graph_data()
	var rail_points: PackedVector2Array = rail_data.get("global_points", PackedVector2Array())
	if rail_points.size() < 2 or not rail_line.has_method("get_elevated_crossing_data"):
		_validation_errors.append("Harbor railway requires baked geometry and explicit vertical classification")
		return
	var found: Array[Dictionary] = []
	var rail_local_points: PackedVector2Array = rail_data.points_local
	var rail_prefix := _polyline_prefix_lengths(rail_local_points)
	for road in roads:
		var road_points: PackedVector2Array = road.points
		for index in range(road_points.size() - 1):
			var start := road_graph.to_global(road_points[index])
			var end := road_graph.to_global(road_points[index + 1])
			for rail_index in range(rail_points.size() - 1):
				var hit = Geometry2D.segment_intersects_segment(start, end, rail_points[rail_index], rail_points[rail_index + 1])
				if hit == null:
					continue
				var duplicate := false
				for existing in found:
					if String(existing.road_id) == String(road.id) and (existing.position as Vector2).distance_to(hit) < 12.0:
						duplicate = true
				if duplicate:
					continue
				var vertical: Dictionary = rail_line.get_elevated_crossing_data(hit)
				var crossing := {"id": "harbor_rail_%s_%d" % [_safe_name(String(road.id)), found.size()], "position": hit, "road_id": String(road.id), "road_width": float(road.width), "rail_offset": float(vertical.rail_offset), "rail_elevation": float(vertical.elevation), "road_elevation": 0.0, "classification": String(vertical.classification)}
				found.append(crossing)
				if String(vertical.classification) == "at_grade":
					_validation_errors.append("Unexpected at-grade rail conflict on %s" % String(road.id))
				else:
					_grade_separated_intersections.append(crossing)
	# Verify the entire road/sidewalk surface, not just centreline intersections.
		var clearance := float(road.width) * 0.5 + float(rail_data.ballast_width) * 0.5 + 42.0
		for point_index in rail_points.size():
			var rail_point: Vector2 = rail_points[point_index]
			var vertical: Dictionary = rail_line.get_track_state_at_offset(float(rail_prefix[point_index]))
			if not bool(vertical.above_ground) or float(vertical.elevation) >= 48.0:
				continue
			for index in range(road_points.size() - 1):
				var nearest := Geometry2D.get_closest_point_to_segment(rail_point, road_graph.to_global(road_points[index]), road_graph.to_global(road_points[index + 1]))
				if nearest.distance_to(rail_point) < clearance:
					_validation_errors.append("Rail descent overlaps road/sidewalk %s" % String(road.id))
	# Unlike the base district, an elevated RAIL carries no road traffic: do not
	# fabricate highway geometry, gate zones or road-junction exclusions for it.
	rail_line.set_detected_road_crossings(found)
	for rect in rail_line.get_pillar_bounds() + rail_line.get_ground_barrier_bounds():
		for road in roads:
			var points: PackedVector2Array = road.points
			for index in range(points.size() - 1):
				var reserved := Rect2(road_graph.to_global(points[index]), Vector2.ZERO).expand(road_graph.to_global(points[index + 1])).grow(float(road.width) * 0.5 + 42.0)
				if reserved.intersects(Rect2(rail_line.to_global(rect.position), rect.size)):
					_validation_errors.append("Rail support/guard occupies road or sidewalk %s" % String(road.id))


func _validate_rail_handoff(rail_line: Node2D) -> void:
	# No invented District2RailConnection: the preview has a real closed loop.
	if rail_line == null:
		return
	var points: PackedVector2Array = rail_line.get_rail_graph_data().get("global_points", PackedVector2Array())
	if points.size() < 3 or points[0].distance_to(points[-1]) > 1.0:
		_validation_errors.append("Standalone harbor railway must have a closed continuous route")


func _elevated_highway() -> Node2D:
	return null if elevated_highway_path.is_empty() else super._elevated_highway()


func _run_elevated_span_audit(road_graph: Node2D, junctions: Array) -> void:
	if not elevated_highway_path.is_empty():
		super._run_elevated_span_audit(road_graph, junctions)
