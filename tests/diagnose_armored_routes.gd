extends SceneTree
const REGION := preload("res://world/editing/EditableRegion.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var harbor = REGION.build_region("harbor")
	var desert = REGION.build_region("desert")
	harbor.prepare_data()
	desert.prepare_data()
	var roads: Array = []
	for region in [harbor,desert]:
		for road in region.roads:
			if road.get("traffic",true): roads.append(road)
	roads.append_array(preload("res://world/urban_detail/CanalTunnel3D.gd").traffic_roads(harbor.roads))
	var graph := GRAPH.new()
	graph.configure(roads)
	var router := ROUTER.new()
	router.configure(graph)
	for pair in [["harbor_bank","desert_bank"],["desert_bank","harbor_bank"]]:
		var origin: Vector3 = PLACES.get_definition(pair[0]).entry_position
		var destination: Vector3 = PLACES.get_definition(pair[1]).entry_position
		var edge: Dictionary = router.nearest_edge(origin)
		var heading: Vector3 = (graph.vertices[edge.edge.to]-graph.vertices[edge.edge.from]).normalized()
		for offset in [0.0,30.0]:
			var start: Vector3 = edge.closest-heading*offset
			var plan: Dictionary = router.plan(start,destination,heading)
			print("ARMORED_ROUTE ",pair," offset ",offset," origin ",origin," from ",start," edge ",edge," plan ",plan)
	print("ARMORED_ROUTE native=",router._native!=null)
	harbor.free()
	desert.free()
	quit()
