extends RefCounted
## Grafo de orientação pelas ruas; não controla a física nem o tráfego.
var graph := AStar2D.new()
var segments: Array = []
var points := {}
var edges: Array = []

func build(roads: Array) -> void:
	graph.clear()
	segments.clear()
	points.clear()
	edges.clear()
	for road in roads:
		var path: PackedVector2Array = road.points
		for i in range(path.size()-1):
			if path[i].distance_to(path[i+1])>0.5: segments.append([path[i],path[i+1],[path[i],path[i+1]]])
	for i in segments.size():
		for j in range(i+1,segments.size()):
			var intersection: Variant = Geometry2D.segment_intersects_segment(segments[i][0],segments[i][1],segments[j][0],segments[j][1])
			if intersection != null:
				segments[i][2].append(intersection)
				segments[j][2].append(intersection)
	for segment in segments:
		var origin: Vector2 = segment[0]
		segment[2].sort_custom(func(a: Vector2,b: Vector2): return origin.distance_squared_to(a)<origin.distance_squared_to(b))
		for i in range(segment[2].size()-1):
			var a := _point(segment[2][i])
			var b := _point(segment[2][i+1])
			if a != b and not graph.are_points_connected(a,b):
				graph.connect_points(a,b)
				edges.append([a,b])

func _point(position: Vector2) -> int:
	var key := Vector2i(roundi(position.x),roundi(position.y))
	if points.has(key): return points[key]
	var id := graph.get_available_point_id()
	graph.add_point(id,position)
	points[key] = id
	return id

func route(from: Vector2,to: Vector2) -> PackedVector2Array:
	if graph.get_point_count()<2: return PackedVector2Array()
	var first := _nearest_edge(from)
	var last := _nearest_edge(to)
	if first.is_empty() or last.is_empty() or first.distance>350 or last.distance>450:
		return PackedVector2Array()
	if first.edge == last.edge: return PackedVector2Array([first.point,last.point])
	var start := graph.get_available_point_id()
	graph.add_point(start,first.point)
	for id in first.edge: graph.connect_points(start,id)
	var end := graph.get_available_point_id()
	graph.add_point(end,last.point)
	for id in last.edge: graph.connect_points(end,id)
	var path := graph.get_point_path(start,end)
	graph.remove_point(start)
	graph.remove_point(end)
	return path

func _nearest_edge(position: Vector2) -> Dictionary:
	var result := {}
	var best := INF
	for edge in edges:
		var point := Geometry2D.get_closest_point_to_segment(position,graph.get_point_position(edge[0]),graph.get_point_position(edge[1]))
		var distance := point.distance_to(position)
		if distance < best:
			best = distance
			result = {"edge":edge,"point":point,"distance":distance}
	return result
