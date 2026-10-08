extends RefCounted
## Scheduled coaches share the authored roads, including the campaign-gated
## northern bridge. Preparing route data never mounts a distant rendered region.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const VILLAGE := preload("res://world/mountain_detail/OriginalVillageLayout.gd")
const GATE := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const BRIDGE := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const ROUTER := preload("res://gameplay/dispatch/DispatchRoadRouter.gd")

class CoachGraph extends GRAPH:
	func _curve_geometry(path: Array[int], closed: bool) -> Dictionary:
		var geometry := super._curve_geometry(path,closed)
		var points: Array[Vector3] = geometry.points
		var sections: Array[Dictionary] = geometry.sections
		# The ice access is a sharp turn off the pass. Gentle controls immediately
		# before it leave too little room for the lane-offset arc, making a hook.
		# Coalesce only this approach; keep its physical road and graph forks.
		var index := 1
		while index<points.size()-1:
			var first: Dictionary=sections[index-1]
			var second: Dictionary=sections[index]
			if first.id=="mountain_pass" and second.id=="mountain_track_5":
				while index>1 and points[index].distance_to(points[index-1])<float(first.width):
					if not _same_lane_section(sections[index-2],first): break
					if points[index-2].direction_to(points[index-1]).dot(points[index-1].direction_to(points[index]))<.90: break
					points.remove_at(index-1); sections.remove_at(index-1); index-=1
			index+=1
		return geometry
static var _graph: RefCounted
static var _signature := ""

static func stations() -> Array[Dictionary]:
	return [
		{"id":"harbor","label":"Rodoviária de Harbor","name":"Rodoviária de Harbor","region":"harbor","arrival":Vector3(135,0,72),"road_point":Vector3(135,0,78.125)},
		{"id":"mountain","label":"Estação de Gelo","name":"Estação de Gelo","region":"mountain","arrival":PLACES._at(VILLAGE.BUS_DOOR,"mountain"),"road_point":PLACES._at(VILLAGE.BERTH,"mountain")},
		{"id":"desert","label":"Cobre · Deserto","name":"Cobre · Deserto","region":"desert","arrival":Vector3(-185,0,-886),"road_point":Vector3(-185,0,-880),"requires_act1":true},
	]

static func station(id: String) -> Dictionary:
	for entry in stations():
		if entry.id==id: return entry
	return {}

static func plan(controller, from: String, to: String) -> Dictionary:
	var origin := station(from)
	var destination := station(to)
	if origin.is_empty() or destination.is_empty() or from==to: return {"ok":false,"reason":"invalid_station"}
	var unlocked := GATE.campaign_completed(controller.state.campaign.snapshot())
	if (from=="desert" or to=="desert") and not unlocked: return {"ok":false,"reason":"campaign_locked"}
	var signature := preload("res://world/editing/WorldEditData.gd").disk_hash()+str(unlocked)
	if _graph==null or signature!=_signature:
		var roads: Array = []
		for id in ["harbor","mountain","desert"]:
			if id=="desert" and not unlocked: continue
			var region: Node3D = controller.regions.get(id)
			var borrowed := is_instance_valid(region)
			if not borrowed:
				region=controller._build_region(id)
				region.prepare_data()
			for road in region.roads:
				if road.get("traffic",true): roads.append(road.duplicate(true))
			if not borrowed: region.free()
		roads.append_array(CONNECTION.traffic_connectors())
		if unlocked:
			var bridge := BRIDGE.centerline()
			# Same physical seam used by the armored service; no connection to
			# the eastern mountain bridge at a different elevation.
			var projection := Vector3.INF
			var gap := 4.0
			for road in roads:
				if road.id!="map2_highway_inbound": continue
				for i in range(road.points.size()-1):
					var point := Geometry3D.get_closest_point_to_segment(bridge[0],road.points[i],road.points[i+1])
					if point.distance_to(bridge[0])<gap: projection=point; gap=point.distance_to(bridge[0])
			if not projection.is_finite(): return {"ok":false,"reason":"bridge_seam_missing"}
			bridge.insert(0,projection)
			roads.append({"id":"regional_coach_north_bridge","width":6.4,"points":bridge})
		_graph=CoachGraph.new()
		_graph.configure(roads)
		_signature=signature
	var router := ROUTER.new()
	router.configure(_graph)
	var result: Dictionary = router.plan(origin.road_point,destination.road_point)
	if not result.get("ok",false): return result
	var curve: Curve3D = result.curve
	var lane_sections: Array = []
	for index in range(result.nodes.size()-1):
		var edge: Dictionary = _graph._edge(result.nodes[index],result.nodes[index+1])
		lane_sections.append({"a":_graph.vertices[edge.from],"b":_graph.vertices[edge.to],"lanes":edge.get("lanes",1),"width":edge.width})
	curve.set_meta("lane_sections",lane_sections)
	curve.set_meta("lane_index",0)
	result.start_gap=curve.sample_baked(0).distance_to(origin.arrival)
	result.end_gap=curve.sample_baked(curve.get_baked_length()).distance_to(destination.arrival)
	result.native=router._native!=null
	if result.start_gap>18 or result.end_gap>18: return {"ok":false,"reason":"station_off_route","start_gap":result.start_gap,"end_gap":result.end_gap}
	return result
