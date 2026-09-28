extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var region := preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var graph := preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(region.roads)
	var neighbours := {}
	for i in graph.vertices.size(): neighbours[i]={}
	for i in graph.edges:
		for edge in graph.edges[i]:
			neighbours[i][edge.to]=true
			neighbours[edge.to][i]=true
	var gaps := []
	for i in graph.vertices.size():
		if neighbours[i].size()!=1 or graph.edges[i].is_empty(): continue
		var point: Vector3 = graph.vertices[i]
		var own: String = graph.edges[i][0].id
		var best := INF
		var target := ""
		for segment in graph.segments:
			if segment.id==own: continue
			var near := Geometry3D.get_closest_point_to_segment(point,segment.a,segment.b)
			var distance := point.distance_to(near)
			if distance < best: best=distance; target=segment.id
		if best<5: gaps.append({"road":own,"at":point,"gap":best,"target":target})
	print("GRAPH ",graph.vertices.size()," vertices near_deadends=",gaps)
	var seen := {}
	var components := []
	for i in graph.vertices.size():
		if seen.has(i): continue
		var queue := [i]
		seen[i]=true
		var cursor := 0
		while cursor<queue.size():
			var at: int = queue[cursor]; cursor+=1
			for next in neighbours[at]:
				if not seen.has(next): seen[next]=true; queue.append(next)
		components.append(queue.size())
	print("COMPONENTS ",components)
	region.free()
	quit()
