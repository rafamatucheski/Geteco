extends SceneTree
func _initialize() -> void:
	var region = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var roads: Array = []
	for road in region.roads:
		if road.get("traffic",true): roads.append(road)
	var graph := preload("res://tests/fixtures/ArmoredAckermannGeometry.gd").new()
	graph.configure(roads)
	var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
	router.configure(graph)
	var plan := router.plan(Vector3(35,0,26.75),Vector3(367,0,-254),Vector3.RIGHT)
	print("ARMORED_TURN_GEOMETRY ",JSON.stringify({"native":router._native!=null,"ok":plan.get("ok",false),"turns":graph.turn_diagnostics}))
	region.free()
	quit(0 if plan.get("ok",false) else 1)
