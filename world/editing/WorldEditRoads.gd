@tool
extends RefCounted
## Pedestrian paths keep their own route data; they never become traffic streets.
static func catalog_walkways(region: Node) -> Dictionary:
	var result := {}
	for path in region.walkways:
		var points: Array = []
		for point in path.points: points.append([point.x,point.z])
		var id := "path/"+str(path.id)
		result[id] = {"id":id,"type":"road","pathway":true,"surface":"earth","points":points,"width":path.width,"label":str(path.id).capitalize()}
	return result

static func rebuild(region: Node, effective: Dictionary) -> void:
	var candidates: Array = []
	for row in effective.values():
		if row.get("type","") != "road" or row.get("deleted",false) or row.get("pathway",false) or str(row.id).begins_with("path/"): continue
		var points := PackedVector3Array()
		for point in row.points: points.append(Vector3(float(point[0]),0,float(point[1])))
		candidates.append({"id":row.id,"points":points,"width":row.width})
	var joined := {}
	for road in preload("res://world/editing/WorldRoadJoins.gd").resolve(candidates): joined[road.id]=road.points
	region.roads.clear()
	region.walkways.clear()
	for row in effective.values():
		if row.get("type","") != "road" or row.get("deleted",false): continue
		var points := PackedVector3Array()
		for point in row.points: points.append(Vector3(float(point[0]),0,float(point[1])))
		if joined.has(row.id): points=joined[row.id]
		if row.get("pathway",false) or str(row.id).begins_with("path/"):
			var path := {"id":str(row.id).trim_prefix("path/"),"points":points,"width":float(row.width),"surface":"footpath"}
			region.walkways.append(path)
			region._record_path(path)
		else:
			region._add_road(str(row.id).trim_prefix("road/"),points,float(row.width),str(row.get("surface","asphalt")))
			for key in ["sidewalk_width","crossings","crossing_offset","crossing_depth","crossing_entries","lanes_per_direction"]:
				if row.has(key): region.roads[-1][key] = row[key]
	region.route_geometry.configure(region.roads+region.walkways)
