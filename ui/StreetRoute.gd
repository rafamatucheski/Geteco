extends RefCounted
## Grafo de orientação pelas ruas; não controla a física nem o tráfego.
var graph := AStar2D.new()
var segments: Array = []
var points := {}
var edges: Array = []
const CELL_SIZE := 256.0
var _segment_cells: Dictionary = {}
var _edge_cells: Dictionary = {}
var intersection_tests := 0

func build(roads: Array, frame_tree: SceneTree = null) -> void:
	graph.clear()
	segments.clear()
	points.clear()
	edges.clear()
	_segment_cells.clear()
	_edge_cells.clear()
	intersection_tests = 0
	var budget_start := Time.get_ticks_usec()
	for road in roads:
		var path: PackedVector2Array = road.points
		for i in range(path.size()-1):
			if path[i].distance_to(path[i+1])>0.5: segments.append([path[i],path[i+1],[path[i],path[i+1]]])
			if frame_tree != null and Time.get_ticks_usec() - budget_start > 1500:
				await frame_tree.process_frame
				budget_start = Time.get_ticks_usec()
	for i in segments.size():
		for cell in _cells_for(segments[i][0], segments[i][1]):
			if not _segment_cells.has(cell): _segment_cells[cell] = []
			_segment_cells[cell].append(i)
		if frame_tree != null and Time.get_ticks_usec() - budget_start > 1500:
			await frame_tree.process_frame
			budget_start = Time.get_ticks_usec()
	for i in segments.size():
		var nearby := {}
		for cell in _cells_for(segments[i][0], segments[i][1]):
			for j in _segment_cells[cell]:
				if j > i: nearby[j] = true
		var candidates := nearby.keys()
		candidates.sort()
		for j in candidates:
			intersection_tests += 1
			var intersection: Variant = Geometry2D.segment_intersects_segment(segments[i][0],segments[i][1],segments[j][0],segments[j][1])
			if intersection != null:
				segments[i][2].append(intersection)
				segments[j][2].append(intersection)
		if frame_tree != null and Time.get_ticks_usec() - budget_start > 1500:
			await frame_tree.process_frame
			budget_start = Time.get_ticks_usec()
	for segment in segments:
		var origin: Vector2 = segment[0]
		segment[2].sort_custom(func(a: Vector2,b: Vector2): return origin.distance_squared_to(a)<origin.distance_squared_to(b))
		for i in range(segment[2].size()-1):
			var a := _point(segment[2][i])
			var b := _point(segment[2][i+1])
			if a != b and not graph.are_points_connected(a,b):
				graph.connect_points(a,b)
				for cell in _cells_for(graph.get_point_position(a),graph.get_point_position(b)):
					if not _edge_cells.has(cell): _edge_cells[cell] = []
					_edge_cells[cell].append(edges.size())
				edges.append([a,b])
		if frame_tree != null and Time.get_ticks_usec() - budget_start > 1500:
			await frame_tree.process_frame
			budget_start = Time.get_ticks_usec()

func _cells_for(a: Vector2, b: Vector2) -> Array[Vector2i]:
	var bounds := Rect2(a, b-a).abs().grow(0.001)
	var first := Vector2i((bounds.position / CELL_SIZE).floor())
	var last := Vector2i((bounds.end / CELL_SIZE).floor())
	var cells: Array[Vector2i] = []
	for y in range(first.y, last.y+1):
		for x in range(first.x, last.x+1): cells.append(Vector2i(x, y))
	return cells

func _point(position: Vector2) -> int:
	var key := Vector2i(roundi(position.x),roundi(position.y))
	if points.has(key): return points[key]
	var id := graph.get_available_point_id()
	graph.add_point(id,position)
	points[key] = id
	return id

func route(from: Vector2,to: Vector2) -> PackedVector2Array:
	if graph.get_point_count()<2: return PackedVector2Array()
	var first := _nearest_edge(from,350.0)
	var last := _nearest_edge(to,450.0)
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

func _nearest_edge(position: Vector2, maximum_distance := INF) -> Dictionary:
	var result := {}
	var best := INF
	var candidates: Array = []
	if is_finite(maximum_distance):
		var found := {}
		var radius := Vector2.ONE*maximum_distance
		for cell in _cells_for(position-radius,position+radius):
			for index in _edge_cells.get(cell,[]): found[index] = true
		candidates = found.keys()
		candidates.sort()
	else:
		candidates = range(edges.size())
	for index in candidates:
		var edge: Array = edges[index]
		var point := Geometry2D.get_closest_point_to_segment(position,graph.get_point_position(edge[0]),graph.get_point_position(edge[1]))
		var distance := point.distance_to(position)
		if distance <= maximum_distance and distance < best:
			best = distance
			result = {"edge":edge,"point":point,"distance":distance}
	return result
