extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var original_hash := preload("res://world/editing/WorldEditData.gd").disk_hash()
	var harbor = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	var desert = preload("res://world/editing/EditableDesertRegion.gd").build_region("desert")
	harbor.prepare_data()
	desert.prepare_data()
	var roads: Array = []
	for region in [harbor,desert]:
		for road in region.roads:
			if road.get("traffic",true): roads.append(road)
	roads.append_array(preload("res://world/urban_detail/CanalTunnel3D.gd").traffic_roads(harbor.roads))
	if "--with-private-bridge" in OS.get_cmdline_user_args():
		var bridge := preload("res://world/north_gateway/NorthGatewayLayout.gd").centerline()
		# O acesso autoral começa na borda oeste do calçamento da arterial.
		for road in roads:
			if road.id != "map2_highway_inbound": continue
			for index in range(1,road.points.size()):
				var projected := Geometry3D.get_closest_point_to_segment(bridge[0],road.points[index-1],road.points[index])
				if projected.distance_to(bridge[0]) < 4.0:
					bridge.insert(0,projected)
					break
		roads.append({"id":"armored_private_north_bridge","width":6.4,"points":bridge})
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(roads)
	var joins: Array = []
	var approach := preload("res://world/north_gateway/NorthGatewayLayout.gd").APPROACH
	for segment in graph.segments:
		if str(segment.id).begins_with("armored_"): continue
		var point := Geometry3D.get_closest_point_to_segment(approach,segment.a,segment.b)
		joins.append({"id":segment.id,"gap":point.distance_to(approach),"point":point,"a":segment.a,"b":segment.b})
	joins.sort_custom(func(a,b): return a.gap < b.gap)
	print("APPROACH_NEIGHBORS ",joins.slice(0,5))
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(graph)
	for ids in [["harbor_bank","desert_bank"],["desert_bank","harbor_bank"]]:
		var origin: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition(ids[0]).entry_position
		var destination: Vector3 = preload("res://world/places/PlaceCatalog.gd").get_definition(ids[1]).entry_position
		var edge := router.nearest_edge(origin)
		var goal_edge := router.nearest_edge(destination)
		var heading: Vector3 = (graph.vertices[edge.edge.to]-graph.vertices[edge.edge.from]).normalized()
		var plan := router.plan(edge.closest-heading*30.0,destination,heading)
		print("ARMORED_ROUTE ",ids," origin=",origin," destination=",destination," edge=",edge," goal_edge=",goal_edge," native=",router._native != null)
		print("PLAN ",plan)
		var from_bank := router.plan(edge.closest,destination,heading)
		print("BANK_PLAN ",from_bank)
	print("GRAPH vertices=",graph.vertices.size()," roads=",roads.size())
	for road in roads:
		if str(road.id).contains("north") or str(road.id).contains("gateway"):
			print("GATEWAY ",road.id," points=",road.points)
	assert(original_hash == preload("res://world/editing/WorldEditData.gd").disk_hash())
	harbor.free()
	desert.free()
	quit()
