extends SceneTree

func _init() -> void:
	call_deferred("_test_patch")

func _test_patch() -> void:
	var d = load("res://legacy/district/borough_one/DistrictOneComplete.tscn").instantiate()
	root.add_child(d)
	await process_frame
	await process_frame
	var u = d.get_node("UnifiedRoadNetwork")
	var graph = u.get_graph_data()
	
	for j in graph.junctions:
		if abs(j.position.x - 870) < 50 and abs(j.position.y - 1260) < 50:
			var sw = u._build_junction_surface_geometry(j, u.SIDEWALK_MARGIN * 2.0)
			print("NEW Sidewalk polygon: ", sw.polygon)
			var rd = u._build_junction_surface_geometry(j, 0.0)
			print("NEW Road polygon:     ", rd.polygon)

	quit(0)
