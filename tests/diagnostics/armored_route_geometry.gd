extends SceneTree
func _initialize() -> void:
	var harbor = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	var desert = preload("res://world/editing/EditableRegion.gd").build_region("desert")
	var roads: Array = []
	for region in [harbor,desert]:
		region.prepare_data()
		for road in region.roads:
			if road.get("traffic",true): roads.append(road)
	roads.append_array(preload("res://world/urban_detail/CanalTunnel3D.gd").traffic_roads(harbor.roads))
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(roads)
	for origin in ["harbor_bank","desert_bank"]:
		var convoy := preload("res://gameplay/armored/ArmoredTransport.gd").new()
		convoy.session = {"controller":{"_route_cache":{"harbor,desert":{"traffic":[graph.segments],"ambient_roads":roads}}}}
		for id in ["harbor_bank","desert_bank"]: convoy.banks[id] = preload("res://world/places/PlaceCatalog.gd").get_definition(id)
		convoy.data = preload("res://gameplay/armored/ArmoredSchedule.gd").initial({"id":"1:0","origin":origin,"destination":"desert_bank" if origin == "harbor_bank" else "harbor_bank"})
		var ok := convoy._prepare_route()
		print("ARMORED_GEOMETRY ",JSON.stringify({"origin":origin,"ok":ok,"probe":convoy.admission_probe}))
		if origin == "harbor_bank" and "--gateway-edges" in OS.get_cmdline_user_args():
			var private_graph: RefCounted = convoy._private_graph
			for from in private_graph.edges:
				var a: Vector3 = private_graph.vertices[from]
				if a.x < 350 or a.x > 390 or a.z > -248 or a.z < -270: continue
				for edge in private_graph.edges[from]:
					print("GATEWAY_EDGE ",JSON.stringify({"from":from,"to":edge.to,"a":a,"b":private_graph.vertices[edge.to],"id":edge.id,"one_way":edge.one_way}))
			var router := preload("res://gameplay/dispatch/DispatchRoadRouter.gd").new()
			router.configure(private_graph)
			for from in private_graph.edges:
				for edge in private_graph.edges[from]:
					if edge.id == "map2_temporary_return" and private_graph.vertices[edge.to].x < private_graph.vertices[from].x:
						router.block_edge(from,edge.to,1000000.0)
			var alternative: Dictionary = router.plan(convoy.admission_probe.start,convoy.road.sample_baked(convoy.road.get_baked_length()),Vector3.RIGHT)
			var ids: Array = []
			for index in range(alternative.get("nodes",[]).size()-1):
				var edge: Dictionary = private_graph._edge(alternative.nodes[index],alternative.nodes[index+1])
				if ids.is_empty() or ids[-1] != edge.id: ids.append(edge.id)
			print("GATEWAY_ALTERNATIVE ",JSON.stringify({"ok":alternative.get("ok",false),"reason":alternative.get("reason",""),"length":alternative.get("length",0),"roads":ids,"native":router._native != null}))
			for offset in [690.0,702.0,714.0,726.0,1300.0,1336.0]: print("POST_GATEWAY_POSE ",offset," ",convoy.road.sample_baked(offset,true))
		convoy.free()
	harbor.free()
	desert.free()
	quit()
