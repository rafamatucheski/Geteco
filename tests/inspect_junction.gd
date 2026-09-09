extends SceneTree

func _init() -> void:
	call_deferred("_run_inspect")

func _run_inspect() -> void:
	var d = load("res://district/borough_one/DistrictOneComplete.tscn").instantiate()
	root.add_child(d)
	await process_frame
	await process_frame
	var u = d.get_node("UnifiedRoadNetwork")
	var graph = u.get_graph_data()
	print("--- JUNCTIONS NEAR (870, 1260) ---")
	for j in graph.junctions:
		if abs(j.position.x - 870) < 150 and abs(j.position.y - 1280) < 200:
			print("Junction at ", j.position, " radius=", j.radius, " conn=", j.connections.size(), " id=", j.get("id", "none"))
			var geom_sidewalk = u._build_junction_surface_geometry(j, u.SIDEWALK_MARGIN * 2.0)
			print("   Sidewalk patch polygon: ", geom_sidewalk.polygon)
			var geom_road = u._build_junction_surface_geometry(j, 0.0)
			print("   Road patch polygon: ", geom_road.polygon)
	for r in graph.roads:
		if r.id == "Bairro1Expansion/north_link":
			print("north_link points (first 10):")
			for i in range(min(10, r.points.size())):
				print("   pt[", i, "] = ", r.points[i])
	quit(0)
