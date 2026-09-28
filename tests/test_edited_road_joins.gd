extends SceneTree
const JOINS := preload("res://world/editing/WorldRoadJoins.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func road(id: String,a: Vector3,b: Vector3,width:=7.5) -> Dictionary:
	return {"id":id,"points":PackedVector3Array([a,b]),"width":width}
func connected(graph, first: String, second: String) -> bool:
	for at in graph.edges:
		var ids := []
		for edge in graph.edges[at]: ids.append(edge.id)
		if first in ids and second in ids: return true
	return false
func run() -> void:
	var original := [road("main",Vector3(-30,0,0),Vector3(30,0,0)),road("branch",Vector3(0,0,-25),Vector3(0,0,-1.2))]
	var joined := JOINS.resolve(original)
	check(original[1].points[-1]==Vector3(0,0,-1.2),"Normalization never mutates source geometry")
	var graph := GRAPH.new()
	graph.configure(joined)
	check(connected(graph,"main","branch"),"Endpoint inside perpendicular asphalt becomes real junction")
	check(joined[1].points[-1]==Vector3.ZERO,"Gap closes on target centreline")
	check(JOINS.resolve(joined)==joined,"Reapplying normalization is stable")
	var parallel := [road("a",Vector3(0,0,0),Vector3(30,0,0)),road("b",Vector3(0,0,2),Vector3(30,0,2))]
	check(JOINS.resolve(parallel)==parallel,"Nearby parallel lanes are not joined sideways")
	var separated := [road("a",Vector3(-30,0,0),Vector3(30,0,0)),road("b",Vector3(0,0,-25),Vector3(0,0,-5))]
	check(JOINS.resolve(separated)==separated,"Gaps outside asphalt stay disconnected")
	var overpass := [road("a",Vector3(-30,5,0),Vector3(30,5,0)),road("b",Vector3(0,0,-25),Vector3(0,0,-1))]
	check(JOINS.resolve(overpass)==overpass,"Roads at different elevations do not snap")
	var narrow := [road("a",Vector3(-30,0,0),Vector3(30,0,0)),road("path",Vector3(0,0,-25),Vector3(0,0,-1),3)]
	check(JOINS.resolve(narrow)==narrow,"Pedestrian paths do not become traffic junctions")
	var ends := [road("a",Vector3(-30,0,0),Vector3.ZERO),road("b",Vector3(1,0,0),Vector3(30,0,0))]
	var result := JOINS.resolve(ends)
	check(result[0].points[-1]==result[1].points[0],"End-to-end continuation has one stable shared endpoint")
	var hash := DATA.disk_hash()
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	graph.configure(region.roads)
	for pair in [["market_street","quay_boulevard"],["medical_garden_lane","warehouse_way"],["northbank_civic_avenue","island_esplanade"],["northbank_neighborhood_street","island_esplanade"],["south_port_access","dock_street"],["northbank_gateway_avenue","eastgate_drive"]]:
		check(connected(graph,pair[0],pair[1]),"Saved map repaired: "+pair[0]+" / "+pair[1])
	check(DATA.disk_hash()==hash,"User's saved map remains byte-for-byte unchanged")
	region.free()
	print("EDITED_ROAD_JOINS ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
