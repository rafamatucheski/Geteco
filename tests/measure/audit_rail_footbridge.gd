extends SceneTree
const RAIL := preload("res://world/railway/RailwayWorld.gd")
const NET := preload("res://world/railway/RailwayNetwork.gd")
const BRIDGE := preload("res://world/urban_detail/UrbanFootbridge3D.gd")
func _initialize() -> void: run.call_deferred()
func area(p: PackedVector2Array) -> float:
	var total := 0.0
	for i in p.size(): total+=p[i].cross(p[(i+1)%p.size()])
	return absf(total)*.5
func tops(owner: Node3D, height: float, tolerance: float) -> Array:
	var result: Array=[]
	for node in owner.find_children("*","MultiMeshInstance3D",true,false):
		for i in node.multimesh.instance_count:
			var t: Transform3D=node.global_transform*node.multimesh.get_instance_transform(i)
			var points := PackedVector2Array()
			var heights: Array[float]=[]
			for corner in [Vector3(-.5,.5,-.5),Vector3(.5,.5,-.5),Vector3(.5,.5,.5),Vector3(-.5,.5,.5)]:
				var p: Vector3=t*corner
				points.append(Vector2(p.x,p.z)); heights.append(p.y)
			if heights.max()-heights.min()>.0001 or absf(heights[0]-height)>tolerance: continue
			result.append({"batch":str(node.name),"instance":i,"height":heights[0],"polygon":points})
	return result
func overlaps(faces: Array) -> Array:
	var result: Array=[]
	for i in faces.size():
		for j in range(i+1,faces.size()):
			var size := 0.0
			for polygon in Geometry2D.intersect_polygons(faces[i].polygon,faces[j].polygon): size+=area(polygon)
			if size>.001: result.append({"a":str(faces[i].batch)+":"+str(faces[i].instance),"b":str(faces[j].batch)+":"+str(faces[j].instance),"area_m2":size,"height_gap_m":absf(faces[i].height-faces[j].height)})
	return result
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("MultiMesh transform readback requires a real renderer"); quit(2); return
	var report := {}
	var bridge := BRIDGE.new()
	root.add_child(bridge); bridge.build()
	await process_frame
	report.footbridge=overlaps(tops(bridge,BRIDGE.DECK_HEIGHT,.021))
	bridge.free()
	var railway := RAIL.new()
	root.add_child(railway); railway.set_process(false)
	for id in ["harbor_central","harbor_north"]:
		var station: Dictionary=NET.get_station(id)
		var node: Node3D=railway._build_station(station)
		await process_frame
		report[id]=overlaps(tops(node,station.position.y+NET.PLATFORM_HEIGHT,.001))
	var seen := {}
	var duplicates: Array=[]
	var count := 0
	var length := 0.0
	for rows in railway._descriptors.values():
		for row in rows:
			if row.id=="terminal_overlap": continue
			var middle: Vector3=(row.a+row.b)*.5
			if not Rect2(-200,-250,850,650).has_point(Vector2(middle.x,middle.z)): continue
			var a := str(row.a); var b := str(row.b)
			var key := a+":"+b if a<b else b+":"+a
			if seen.has(key): duplicates.append(key)
			seen[key]=true; count+=1; length+=row.a.distance_to(row.b)
	report.railway={"scope":"descriptor midpoints in x[-200,650],z[-250,400]","segments":count,"exact_duplicate_segments":duplicates,"total_segment_length_m":length,"ballast_over_concrete_layer_area_m2":3.4*(length+.016*count),"note":"Sum per segment, not union; structural ballast over concrete, 45mm top separation. Other junction intersections not tested by exact segment equality."}
	DirAccess.make_dir_recursive_absolute("res://evidence/rail-footbridge-audit-20261014")
	FileAccess.open("res://evidence/rail-footbridge-audit-20261014/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RAIL_FOOTBRIDGE_AUDIT ",JSON.stringify(report))
	railway.free(); quit()
