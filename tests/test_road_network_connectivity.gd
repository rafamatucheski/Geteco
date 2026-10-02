extends SceneTree
const GRAPH = preload("res://gameplay/NativeTrafficRoutes.gd")
const REGION = preload("res://world/editing/EditableRegion.gd")
const CONNECTION = preload("res://world/regions/WorldConnection3D.gd")
const TUNNEL = preload("res://world/urban_detail/CanalTunnel3D.gd")
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok: failures+=1; push_error(label)
func road(id: String, points: Array, width:=8.0)->Dictionary:
	return {"id":id,"points":PackedVector3Array(points),"width":width}
func run():
	var graph=GRAPH.new()
	graph.configure([road("main",[Vector3(-10,0,0),Vector3.ZERO,Vector3(10,0,0)]),road("branch",[Vector3(.0516,0,-10),Vector3(.0516,0,0)])])
	check(graph.route_between(Vector3(-10,0,0),Vector3(10,0,0))!=null,"A branch 5 cm after a control point never cuts the main road")
	check(graph.route_between(Vector3(10,0,0),Vector3(-10,0,0))!=null,"Short split keeps the return route")
	check(graph.route_between(Vector3(-10,0,0),Vector3(.0516,0,-10))!=null,"Short split preserves access to the branch")
	graph.configure([road("tiny",[Vector3(-10,0,0),Vector3.ZERO,Vector3(.06,0,0),Vector3(10,0,0)])])
	check(graph.route_between(Vector3(-10,0,0),Vector3(10,0,0))!=null,"Short authored segment preserves continuity")
	graph.configure([road("tiny",[Vector3(-10,0,0),Vector3.ZERO,Vector3(.005,0,0),Vector3(10,0,0)])])
	var self_edge:=false
	for from in graph.edges:
		for edge in graph.edges[from]: self_edge=self_edge or from==edge.to
	check(not self_edge,"Vertices in the same quantization cell never create self edges")
	graph.configure([road("main_outbound",[Vector3(-10,0,0),Vector3.ZERO,Vector3(10,0,0)]),road("branch",[Vector3(.0516,0,-10),Vector3(.0516,0,0)])])
	check(graph.route_between(Vector3(-10,0,0),Vector3(10,0,0))!=null,"Short split preserves one-way travel")
	check(graph.route_between(Vector3(10,0,0),Vector3(-10,0,0))==null,"Short split never permits driving against one-way traffic")
	graph.configure([road("surface",[Vector3(-10,0,0),Vector3(10,0,0)]),road("bridge",[Vector3(0,5,-10),Vector3(0,5,10)])])
	check(graph.route_between(Vector3(-10,0,0),Vector3(0,5,10))==null,"Crossing at a different elevation stays disconnected")
	graph.configure([road("a",[Vector3(-10,0,0),Vector3(10,0,0)]),road("b",[Vector3(-10,0,2),Vector3(10,0,2)])])
	check(graph.route_between(Vector3(-10,0,0),Vector3(-10,0,2))==null,"Adjacent parallel roads never gain lateral shortcuts")
	graph.configure([road("main",[Vector3(-16,0,0),Vector3(-8,0,0),Vector3(-4,0,0),Vector3(-2,0,0),Vector3(-.5,0,0),Vector3.ZERO,Vector3(10,0,0)],8.75),road("branch",[Vector3(.0516,0,-16),Vector3(.0516,0,0)],5.0)])
	var turn:Curve3D=graph.route_between(Vector3(.0516,0,-16),Vector3(-16,0,0))
	var backwards:=false
	if turn!=null:
		var previous:Vector3=turn.sample_baked(0,true)
		for i in range(1,ceili(turn.get_baked_length()*10)):
			var p:Vector3=turn.sample_baked(i*.1,true)
			if p.x>previous.x+.005 or p.z<previous.z-.005:backwards=true
			previous=p
	check(turn!=null and not backwards,"Dense control points must not create a reversing hook in a normal left turn")
	var hash_before=preload("res://world/editing/WorldEditData.gd").disk_hash()
	var harbor=REGION.build_region("harbor")
	var mountain=REGION.build_region("mountain")
	harbor.prepare_data(); mountain.prepare_data()
	graph.configure(harbor.roads+mountain.roads+CONNECTION.traffic_connectors()+TUNNEL.traffic_roads(harbor.roads))
	var gateway_join:=false
	for at in graph.edges:
		if graph.vertices[at].distance_to(Vector3(291,0,-122))>.05:continue
		var ids=[]
		for edge in graph.edges[at]:ids.append(edge.id)
		gateway_join=gateway_join or ("northbank_gateway_avenue" in ids and "island_esplanade" in ids)
	check(gateway_join,"Northbank gateway directly joins the esplanade, without a false dead end")
	var city:=Vector3(382.5,0,-125)
	for destination in [Vector3(680.625,0,-476.25),Vector3(758,0,-323),Vector3(715,0,-477.375),Vector3(748,0,-438)]:
		check(graph.route_between(city,destination)!=null,"Current map outbound to "+str(destination))
		check(graph.route_between(destination,city)!=null,"Current map inbound from "+str(destination))
	# Every road eligible for general vehicle routing belongs to the same directed network.
	for reverse in [false,true]:
		var adjacency: Dictionary={}
		for i in graph.vertices.size(): adjacency[i]=[]
		for from in graph.edges:
			for edge in graph.edges[from]: adjacency[edge.to if reverse else from].append(from if reverse else edge.to)
		var queue: Array[int]=[0]
		var seen: Dictionary={0:true}
		var cursor:=0
		while cursor<queue.size():
			var at:=queue[cursor];cursor+=1
			for next in adjacency[at]:
				if not seen.has(next): seen[next]=true;queue.append(next)
		check(seen.size()==graph.vertices.size(),"All current vehicle-road vertices reachable "+("backward" if reverse else "forward")+" (%d/%d)"%[seen.size(),graph.vertices.size()])
	check(preload("res://world/editing/WorldEditData.gd").disk_hash()==hash_before,"Connectivity validation never writes the saved map")
	harbor.free();mountain.free()
	print("ROAD_NETWORK_CONNECTIVITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
