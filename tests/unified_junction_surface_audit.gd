extends SceneTree

const DISTRICT_SCENE := preload("res://legacy/district/borough_one/DistrictOneComplete.tscn")
const MATERIAL_LAYERS := ["sidewalk", "curb", "road_edge", "asphalt"]
const CRITICAL_HUB_ROADS := [
	["midtown_cross", "west_link"],
	["west_link", "west_local"],
	["south_cross", "west_local"],
	["coastal_exit", "east_arc", "east_link", "midtown_cross"],
	["east_link", "port_service", "south_cross", "southern_ring"],
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var district := DISTRICT_SCENE.instantiate()
	root.add_child(district)
	for _frame in 4:
		await process_frame
	var graph := district.get_node_or_null("UnifiedRoadNetwork")
	_check(graph != null, "DistrictOneComplete has no UnifiedRoadNetwork")
	if graph == null:
		_finish()
		return

	var graph_data := graph.get_graph_data() as Dictionary
	_check((graph_data.validation_errors as Array).is_empty(), "graph validation: %s" % [graph_data.validation_errors])
	var surface_audit := graph.get_surface_topology_audit() as Dictionary
	_check((surface_audit.errors as Array).is_empty(), "surface validation: %s" % [surface_audit.errors])
	_check(
		String(surface_audit.render_policy.hidden_roads_contribute) == "only_at_mixed_visibility_junctions",
		"mixed-visibility render policy is not explicit"
	)
	_check(bool(surface_audit.render_policy.all_hidden_junctions_suppressed), "all-hidden junctions are not suppressed")

	var audits := surface_audit.junctions as Array
	_check(audits.size() == (graph_data.junctions as Array).size(), "not every junction was surface-audited")
	var local_cap_layers := 0
	for audit_value in audits:
		var audit := audit_value as Dictionary
		var layers := audit.layers as Dictionary
		for layer_id in MATERIAL_LAYERS:
			_check(layers.has(layer_id), "%s has no %s audit" % [String(audit.junction_id), layer_id])
			if not layers.has(layer_id):
				continue
			var layer := layers[layer_id] as Dictionary
			_check((layer.errors as Array).is_empty(), "%s/%s: %s" % [String(audit.junction_id), layer_id, layer.errors])
			if bool(audit.patch_required):
				_check(int(layer.component_count) == 1, "%s/%s is not one component" % [String(audit.junction_id), layer_id])
				_check(int(layer.triangle_count) > 0, "%s/%s is not triangulated" % [String(audit.junction_id), layer_id])
				_check(float(layer.maximum_extent) <= float(layer.extent_limit) + 0.5, "%s/%s exceeded miter envelope" % [String(audit.junction_id), layer_id])
				for road_id in audit.rendered_road_ids:
					_check((layer.overlap_road_ids as Array).has(road_id), "%s/%s misses %s" % [String(audit.junction_id), layer_id, road_id])
			else:
				_check(int(layer.point_count) == 0, "%s/%s manufactured an orphan patch" % [String(audit.junction_id), layer_id])
			if String(layer.construction) == "local_cap_hull":
				local_cap_layers += 1

	for required_roads in CRITICAL_HUB_ROADS:
		var matching_audit := _find_hub_audit(audits, required_roads)
		_check(not matching_audit.is_empty(), "critical hub not found: %s" % [required_roads])
		if not matching_audit.is_empty():
			_check(bool(matching_audit.patch_required), "critical hub has no surface patch: %s" % [required_roads])

	_test_hidden_road_policy(graph, graph_data.roads as Array)
	if _failures.is_empty():
		print(
			"UNIFIED_JUNCTION_SURFACE_AUDIT: PASS junctions=%d hubs=%d local_cap_layers=%d" % [
				audits.size(), CRITICAL_HUB_ROADS.size(), local_cap_layers,
			]
		)
	_finish()


func _find_hub_audit(audits: Array, required_roads: Array) -> Dictionary:
	var expected := _short_road_id_set(required_roads)
	for audit_value in audits:
		var audit := audit_value as Dictionary
		if _short_road_id_set(audit.road_ids as Array) == expected:
			return audit
	return {}


func _short_road_id_set(road_ids: Array) -> Dictionary:
	var result := {}
	for road_id_value in road_ids:
		var road_id := String(road_id_value)
		var separator := road_id.rfind("/")
		result[road_id.substr(separator + 1) if separator >= 0 else road_id] = true
	return result


func _test_hidden_road_policy(graph: Node, roads: Array) -> void:
	var hidden_index := -1
	var rendered_index := -1
	for road_index in range(roads.size()):
		if bool((roads[road_index] as Dictionary).render):
			if rendered_index < 0:
				rendered_index = road_index
		else:
			if hidden_index < 0:
				hidden_index = road_index
	_check(hidden_index >= 0, "canonical graph has no hidden overlay road for policy test")
	_check(rendered_index >= 0, "canonical graph has no rendered road for policy test")
	if hidden_index < 0 or rendered_index < 0:
		return

	var hidden_road := roads[hidden_index] as Dictionary
	var rendered_road := roads[rendered_index] as Dictionary
	var hidden_direction := _first_direction(hidden_road.points as PackedVector2Array)
	var hidden_connection := _synthetic_connection(hidden_index, hidden_direction)
	var hidden_only := {
		"position": Vector2.ZERO,
		"radius": float(hidden_road.width),
		"connections": [hidden_connection],
	}
	var hidden_geometry := graph.call("_build_junction_surface_geometry", hidden_only, 0.0) as Dictionary
	_check((hidden_geometry.polygon as PackedVector2Array).is_empty(), "all-hidden junction manufactured a surface")

	var rendered_connection := _synthetic_connection(rendered_index, hidden_direction.orthogonal())
	var mixed := {
		"position": Vector2.ZERO,
		"radius": maxf(float(hidden_road.width), float(rendered_road.width)),
		"connections": [hidden_connection, rendered_connection],
	}
	var mixed_geometry := graph.call("_build_junction_surface_geometry", mixed, 0.0) as Dictionary
	_check(not (mixed_geometry.polygon as PackedVector2Array).is_empty(), "mixed rendered+hidden junction has no surface")
	var hidden_contributed := false
	for arm_value in mixed_geometry.arms:
		if (arm_value as Dictionary).hidden_road_indices.has(hidden_index):
			hidden_contributed = true
			break
	_check(hidden_contributed, "hidden overlay road did not contribute to mixed junction envelope")


func _synthetic_connection(road_index: int, tangent: Vector2) -> Dictionary:
	return {
		"road_index": road_index,
		"forward_tangent": tangent.normalized(),
		"distance_along": 0.0,
		"total_length": 1000.0,
	}


func _first_direction(points: PackedVector2Array) -> Vector2:
	for point_index in range(points.size() - 1):
		if points[point_index].distance_to(points[point_index + 1]) > 0.1:
			return points[point_index].direction_to(points[point_index + 1])
	return Vector2.RIGHT


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error("UNIFIED_JUNCTION_SURFACE_AUDIT: %s" % failure)
		quit(1)
		return
	quit(0)
