extends RefCounted
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
## NativeRegion already supplies metres. Junctions are split where the authored
## centre-lines actually meet; no synthetic cross-block shortcuts or U-turns.
var segments: Array[Dictionary] = []
var vertices: Array[Vector3] = []
var edges: Dictionary = {}
var _vertex_ids: Dictionary = {}

func configure(roads: Array, minimum_width: float = 5.0) -> void:
	segments.clear()
	vertices.clear()
	edges.clear()
	_vertex_ids.clear()
	for road in roads:
		if not road is Dictionary or not road.has("points"): continue
		var points: PackedVector3Array = road.points
		var width := float(road.get("width", 7.5))
		var id := str(road.get("id", "road"))
		var one_way := id.contains("inbound") or id.contains("outbound")
		# Single-lane bridges have an explicit direction in the original map.
		# Narrow two-way service paths remain pedestrian/service access.
		if width < minimum_width and not one_way: continue
		for index in range(points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			if a.distance_squared_to(b) < 0.00000001: continue
			segments.append({"a":a,"b":b,"width":width,"id":id,"one_way":one_way,"lanes":int(road.get("lanes_per_direction",1)),"splits":[0.0,1.0]})
	for first in segments.size():
		var a: Dictionary = segments[first]
		for second in range(first + 1, segments.size()):
			var b: Dictionary = segments[second]
			var rect_a := Rect2(_xz(a.a), Vector2.ZERO).expand(_xz(a.b)).grow(0.05)
			var rect_b := Rect2(_xz(b.a), Vector2.ZERO).expand(_xz(b.b)).grow(0.05)
			if not rect_a.intersects(rect_b, true): continue
			var crossing: Variant = Geometry2D.segment_intersects_segment(_xz(a.a), _xz(a.b), _xz(b.a), _xz(b.b))
			if crossing is Vector2:
				_add_split(a, crossing)
				_add_split(b, crossing)
			else:
				# Collinear joins/overlaps also need endpoint nodes.
				for endpoint: Vector3 in [a.a, a.b]:
					if Geometry3D.get_closest_point_to_segment(endpoint, b.a, b.b).distance_to(endpoint) < 0.05: _add_split(b, _xz(endpoint))
				for endpoint: Vector3 in [b.a, b.b]:
					if Geometry3D.get_closest_point_to_segment(endpoint, a.a, a.b).distance_to(endpoint) < 0.05: _add_split(a, _xz(endpoint))
	for segment in segments:
		segment.splits.sort()
		for index in range(segment.splits.size() - 1):
			var a: Vector3 = segment.a.lerp(segment.b, segment.splits[index])
			var b: Vector3 = segment.a.lerp(segment.b, segment.splits[index + 1])
			var from := _vertex(a)
			var to := _vertex(b)
			# A junction may split a continuous road only centimetres from a control
			# point. Keep that link whenever quantization gives distinct vertices;
			# dropping it would cut both the main road and its branch off the graph.
			if from == to: continue
			_connect(from, to, segment)
			if not segment.one_way: _connect(to, from, segment)

func _xz(point: Vector3) -> Vector2: return Vector2(point.x, point.z)

func _add_split(segment: Dictionary, point: Vector2) -> void:
	var direction := _xz(segment.b) - _xz(segment.a)
	var fraction := clampf((point - _xz(segment.a)).dot(direction) / direction.length_squared(), 0, 1)
	for existing in segment.splits:
		if absf(existing - fraction) < 0.00001: return
	segment.splits.append(fraction)

func _vertex(point: Vector3) -> int:
	var key := Vector3i(roundi(point.x * 20), roundi(point.y * 20), roundi(point.z * 20))
	if _vertex_ids.has(key): return _vertex_ids[key]
	var index := vertices.size()
	_vertex_ids[key] = index
	vertices.append(point)
	edges[index] = []
	return index

func _connect(from: int, to: int, segment: Dictionary) -> void:
	for edge in edges[from]:
		if edge.to == to: return
	edges[from].append({"from":from,"to":to,"width":segment.width,"id":segment.id,"one_way":segment.one_way,"lanes":segment.get("lanes",1)})

func route_near(point: Vector3, lane_index := 0) -> Curve3D:
	if vertices.is_empty(): return null
	var selected: Dictionary = {}
	var distance := INF
	for from in edges:
		for edge in edges[from]:
			var direction := (vertices[edge.to] - vertices[from]).normalized()
			var offset := _lane_offset(direction, edge, lane_index)
			var closest := Geometry3D.get_closest_point_to_segment(point, vertices[from] + offset, vertices[edge.to] + offset)
			var separation := closest.distance_squared_to(point)
			if separation < distance:
				distance = separation
				selected = edge
	if selected.is_empty(): return null
	var path := _cycle(selected)
	var closed := not path.is_empty()
	if not closed: path = _open_path(selected)
	if path.size() < 2: return null
	var curve := _curve(path, closed, lane_index)
	curve.set_meta("lane_index",lane_index)
	curve.set_meta("junction_reach",7.0 if lane_index>0 else 4.0)
	curve.set_meta("traffic_open", not closed)
	curve.set_meta("traffic_endpoint", curve.get_point_position(curve.get_point_count() - 1))
	curve.set_meta("traffic_nodes", path)
	curve.set_meta("traffic_source_ids", _source_ids(path))
	return curve

func route_between(start: Vector3, finish: Vector3, arrival_direction: Vector3 = Vector3.ZERO) -> Curve3D:
	# Mission journeys use the same directed intersections as ambient traffic.
	if vertices.is_empty(): return null
	var first := 0
	var last := 0
	for index in vertices.size():
		if start.distance_squared_to(vertices[index]) < start.distance_squared_to(vertices[first]): first = index
		if finish.distance_squared_to(vertices[index]) < finish.distance_squared_to(vertices[last]): last = index
	var final_edge: Dictionary = {}
	var final_center := Vector3.ZERO
	if arrival_direction.length_squared() > .01:
		var nearest := INF
		for from in edges:
			for edge in edges[from]:
				var direction := vertices[from].direction_to(vertices[edge.to])
				if direction.dot(arrival_direction.normalized()) < .9: continue
				var center := Geometry3D.get_closest_point_to_segment(finish, vertices[from], vertices[edge.to])
				if center.distance_to(vertices[from]) < .1: continue
				var distance := center.distance_squared_to(finish)
				if distance < nearest:
					nearest = distance
					final_edge = edge
					final_center = center
		if not final_edge.is_empty(): last = final_edge.from
	var queue: Array[int] = [first]
	var previous := {first: -1}
	var cursor := 0
	while cursor < queue.size() and not previous.has(last):
		var current := queue[cursor]
		cursor += 1
		for edge in edges[current]:
			if not previous.has(edge.to):
				previous[edge.to] = current
				queue.append(edge.to)
	if not previous.has(last) or (first == last and final_edge.is_empty()): return null
	var path: Array[int] = [last]
	while path[0] != first: path.push_front(previous[path[0]])
	var temporary := -1
	if not final_edge.is_empty():
		temporary = vertices.size()
		vertices.append(final_center)
		var tail := final_edge.duplicate()
		tail.to = temporary
		edges[last].append(tail)
		path.append(temporary)
	var curve := _curve(path, false)
	if temporary >= 0:
		vertices.pop_back()
		edges[last].pop_back()
	curve.set_meta("traffic_open", true)
	curve.set_meta("traffic_endpoint", curve.get_point_position(curve.point_count - 1))
	return curve

func _cycle(first: Dictionary) -> Array[int]:
	# Search from the next junction back to the first without using the same
	# street in reverse. A cycle must contain at least three distinct nodes.
	var queue: Array[int] = [first.to]
	var previous: Dictionary = {first.to: -1}
	var cursor := 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		for edge in edges[current]:
			var next: int = edge.to
			if current == first.to and next == first.from: continue
			if next == first.from:
				var reverse: Array[int] = [next, current]
				while previous[current] != -1:
					current = previous[current]
					reverse.append(current)
				reverse.reverse()
				var result: Array[int] = [first.from]
				result.append_array(reverse)
				return result
			if previous.has(next): continue
			previous[next] = current
			queue.append(next)
	return []

func _open_path(first: Dictionary) -> Array[int]:
	var result: Array[int] = [first.from, first.to]
	var visited: Dictionary = {first.from:true, first.to:true}
	for step in 256:
		var current := result[-1]
		var previous := result[-2]
		var incoming := (vertices[current] - vertices[previous]).normalized()
		var next := -1
		var best := -INF
		for edge in edges[current]:
			if visited.has(edge.to): continue
			var direction := (vertices[edge.to] - vertices[current]).normalized()
			var score := direction.dot(incoming)
			if score > best:
				best = score
				next = edge.to
		if next < 0: break
		result.append(next)
		visited[next] = true
	return result

func _edge(from: int, to: int) -> Dictionary:
	for edge in edges[from]:
		if edge.to == to: return edge
	return {}

func _lane_offset(direction: Vector3, edge: Dictionary, lane_index := 0) -> Vector3:
	var lanes := maxi(1,int(edge.get("lanes",1)))
	var lane := clampi(lane_index,0,lanes-1)
	var width := float(edge.width)
	var offset := width/(2.0*lanes)*(lane+.5)
	if edge.one_way: offset = width/lanes*(lane+.5)-width*.5
	return direction.cross(Vector3.UP)*offset

func _source_ids(path: Array[int]) -> Array[String]:
	var result: Array[String] = []
	for index in range(path.size() - 1):
		var id: String = _edge(path[index], path[index + 1]).id
		if not result.has(id): result.append(id)
	return result

func _curve_geometry(path: Array[int], closed: bool) -> Dictionary:
	var nodes: Array[int] = path.duplicate()
	if closed: nodes.pop_back()
	var points: Array[Vector3] = []
	var sections: Array[Dictionary] = []
	for node in nodes: points.append(vertices[node])
	for index in range(path.size()-1): sections.append(_edge(path[index],path[index+1]))
	# Graph control points are not corners. A split a few centimetres before a
	# junction must not shrink its lane turn into a reversing hook. Coalesce only
	# gentle, same-road control points beside a change of road; keep real forks,
	# lane/width changes and sharp bends. Graph vertices and lane metadata stay intact.
	var index := 1
	while index < points.size()-1:
		var first: Dictionary = sections[index-1]
		var second: Dictionary = sections[index]
		if first.id == second.id:
			index += 1
			continue
		var span := maxf(float(first.width),float(second.width))
		while index > 1 and points[index].distance_to(points[index-1]) < span:
			var outer: Dictionary = sections[index-2]
			if not _same_lane_section(outer,first) or edges[nodes[index-1]].size()>2: break
			if points[index-2].direction_to(points[index-1]).dot(points[index-1].direction_to(points[index])) < .94: break
			points.remove_at(index-1); nodes.remove_at(index-1); sections.remove_at(index-1)
			index -= 1
		while index+2 < points.size() and points[index].distance_to(points[index+1]) < span:
			var outer: Dictionary = sections[index+1]
			if not _same_lane_section(second,outer) or edges[nodes[index+1]].size()>2: break
			if points[index].direction_to(points[index+1]).dot(points[index+1].direction_to(points[index+2])) < .94: break
			points.remove_at(index+1); nodes.remove_at(index+1); sections.remove_at(index+1)
		index += 1
	return {"points":points,"sections":sections}

func _same_lane_section(a: Dictionary, b: Dictionary) -> bool:
	return a.id==b.id and a.width==b.width and a.one_way==b.one_way and a.get("lanes",1)==b.get("lanes",1)

func _curve(path: Array[int], closed: bool, lane_index := 0) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 0.25
	var geometry := _curve_geometry(path,closed)
	var points: Array[Vector3] = geometry.points
	var sections: Array[Dictionary] = geometry.sections
	for index in points.size():
		var at: Vector3 = points[index]
		if not closed and index == 0:
			var direction := (points[1] - at).normalized()
			curve.add_point(at + _lane_offset(direction,sections[0],lane_index))
			continue
		if not closed and index == points.size() - 1:
			var direction := (at - points[index-1]).normalized()
			curve.add_point(at + _lane_offset(direction,sections[-1],lane_index))
			continue
		var previous := posmod(index-1,points.size())
		var next := (index+1)%points.size()
		var incoming := (at-points[previous]).normalized()
		var outgoing := (points[next]-at).normalized()
		var first: Dictionary = sections[previous]
		var second: Dictionary = sections[index]
		var incoming_offset := _lane_offset(incoming, first,lane_index)
		var outgoing_offset := _lane_offset(outgoing, second,lane_index)
		var trim := minf(minf(at.distance_to(points[previous]),at.distance_to(points[next]))*.35,maxf(1.5,minf(first.width,second.width)*.5))
		var entry := at - incoming * trim + incoming_offset
		var exit := at + outgoing * trim + outgoing_offset
		var crossing: Variant = Geometry2D.line_intersects_line(_xz(at + incoming_offset), _xz(incoming), _xz(at + outgoing_offset), _xz(outgoing))
		var first_handle := trim * 0.55
		var second_handle := trim * 0.55
		if crossing is Vector2:
			first_handle = minf(_xz(entry).distance_to(crossing) * 0.55, trim * 1.5)
			second_handle = minf(_xz(exit).distance_to(crossing) * 0.55, trim * 1.5)
		curve.add_point(entry, Vector3.ZERO, incoming * first_handle)
		curve.add_point(exit, -outgoing * second_handle, Vector3.ZERO)
	if closed:
		curve.add_point(curve.get_point_position(0), curve.get_point_in(0), curve.get_point_out(0))
	var lane_sections := []
	for index in range(path.size()-1):
		var edge := _edge(path[index],path[index+1])
		lane_sections.append({"a":vertices[path[index]],"b":vertices[path[index+1]],"lanes":edge.get("lanes",1),"width":edge.width})
	curve.set_meta("lane_sections",lane_sections)
	# Túnel do canal: curva acompanha a altura do piso da rampa (CanalTunnel3D).
	CANAL_TUNNEL.follow_floor(curve)
	curve.set_meta("lane_index",lane_index)
	curve.set_meta("junction_reach",7.0 if lane_index>0 else 4.0)
	return curve
