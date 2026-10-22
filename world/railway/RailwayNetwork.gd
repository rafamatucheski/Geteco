extends RefCounted
## Authored metre coordinates. Geometry, journeys and maps use the same rails.
## Junctions are not road graph vertices: the railway crosses roads above them.
const TRACK_HEIGHT := 12.0
const TRACK_WIDTH := 4.8
const PLATFORM_OFFSET := 4.4
const PLATFORM_HEIGHT := 0.83
const GATE_POSITION := Vector3(315, 14, -350)
static var _station_cache: Array[Dictionary] = []
static var _edge_cache: Array[Dictionary] = []

static func stations() -> Array[Dictionary]:
	if _station_cache.is_empty():
		_station_cache = [
			_station("harbor_central", "Harbor Central", Vector3(-12,12,52), "harbor", -1.0),
			_station("harbor_north", "Northgate", Vector3(386,12,-194), "harbor", 1.0),
			_station("mountain_pines", "Pinhais", Vector3(730,12,-402), "mountain", -1.0),
			_station("desert_copper", "Cobre", Vector3(-72,12,-925), "desert", -1.0),
		]
	return _station_cache.duplicate(true)

static func get_stations() -> Array[Dictionary]: return stations()

static func _station(id: String, label: String, point: Vector3, region: String, side: float) -> Dictionary:
	# Northgate opens east over water; no staircase or platform occupies the highway.
	var entry := point + Vector3(side * 12.0, -point.y + 0.12, 12.0)
	return {"id":id, "label":label, "name":label, "position":point,
		"arrival":point + Vector3(side * PLATFORM_OFFSET, PLATFORM_HEIGHT + 0.12, 0),
		"entry":entry, "entrance":entry, "region":region,
		"requires_act1":region == "desert", "side":side}

static func get_station(id: String) -> Dictionary:
	for station in stations():
		if station.id == id: return station
	return {}

static func ground_landing_rect(id: String) -> Rect2:
	var station := get_station(id)
	if station.is_empty(): return Rect2()
	var center: Vector2=Vector2(station.position.x,station.position.z)+Vector2(float(station.side)*10.65,11.5)
	return Rect2(center-Vector2(2.8,2.75),Vector2(5.6,5.5))

## On-foot restore only: old elevated platform/stair saves go to the new
## supported entrance. Do not apply this to vehicles or arbitrary Harbor roofs.
static func restore_harbor_pedestrian(point: Vector3) -> Vector3:
	if point.y<.5: return point
	# Only migrate unsupported former surfaces; a save on an overlapping
	# platform or retained landing keeps its exact position.
	for old in [Vector3(-12,12,52),Vector3(386,12,-179),Vector3(386,12,-194)]:
		var target := "harbor_central" if old.x < 0 else "harbor_north"
		if (_on_access_surface(point,old,false) or _on_access_surface(point,old,true)) and not _on_access_surface(point,get_station(target).position,true,float(get_station(target).side)):
			return get_station(target).entry
	var p := Vector2(point.x-145,point.z-67)
	var floor_y := TRACK_HEIGHT+PLATFORM_HEIGHT
	var rise := floor_y/3.0
	if Rect2(2,-17,4.8,34).has_point(p) and absf(point.y-floor_y)<.35:
		return get_station("harbor_central").entry
	for deck in [[rise,-5.5],[rise*2,11.5],[floor_y,-5.5]]:
		if Rect2(7.9,float(deck[1])-1.5,5.5,3).has_point(p) and absf(point.y-float(deck[0]))<.35:
			return get_station("harbor_central").entry
	if Rect2(4,-6.85,8,2.7).has_point(p) and absf(point.y-floor_y)<.35:
		return get_station("harbor_central").entry
	for index in 3:
		var x := 12.0 if index!=1 else 9.3
		if absf(p.x-x)>1.06 or p.y< -4.0 or p.y>10.0: continue
		var fraction := inverse_lerp(10.0,-4.0,p.y) if index!=1 else inverse_lerp(-4.0,10.0,p.y)
		if absf(point.y-rise*(index+fraction))<.35:
			return get_station("harbor_central").entry
	return point

static func _on_access_surface(point: Vector3, origin: Vector3, compact: bool, side := -1.0) -> bool:
	var local := Vector2((point.x-origin.x)*side,point.z-origin.z)
	var floor_y := origin.y+PLATFORM_HEIGHT
	var rise := floor_y/3.0
	var far_z := 2.0 if compact else -4.0
	var landing_z := .5 if compact else -5.5
	if Rect2(2,-17,4.8,34).has_point(local) and absf(point.y-floor_y)<.35: return true
	if Rect2(6.8,landing_z-1.35,1.1,2.7).has_point(local) and absf(point.y-floor_y)<.35: return true
	for deck in [[rise,landing_z],[rise*2,11.5],[floor_y,landing_z]]:
		if Rect2(7.9,float(deck[1])-1.5,5.5,3).has_point(local) and absf(point.y-float(deck[0]))<.35: return true
	for index in 3:
		var x := 12.0 if index != 1 else 9.3
		if absf(local.x-x)>1.06 or local.y<far_z or local.y>10.0: continue
		var fraction := inverse_lerp(10.0,far_z,local.y) if index != 1 else inverse_lerp(far_z,10.0,local.y)
		if absf(point.y-rise*(index+fraction))<.35: return true
	return false

static func nearest_station(point: Vector3, radius: float = 8.0) -> Dictionary:
	var result := {}
	var closest := radius
	for station in stations():
		var distance := point.distance_to(station.arrival)
		if distance <= closest:
			closest = distance
			result = station
	return result

static func approach_path(id: String) -> PackedVector3Array:
	var station := get_station(id)
	if station.is_empty(): return PackedVector3Array()
	var origin: Vector3 = station.position
	var side := float(station.side)
	var rise := (origin.y + PLATFORM_HEIGHT) / 3.0
	var local := PackedVector3Array([
		Vector3(12,0,12), Vector3(12,0,10), Vector3(12,rise,-4),
		Vector3(12,rise,-5.5), Vector3(9.3,rise,-5.5), Vector3(9.3,rise,-4),
		Vector3(9.3,rise*2,10), Vector3(9.3,rise*2,11.5), Vector3(12,rise*2,11.5),
		Vector3(12,rise*2,10), Vector3(12,rise*3,-4), Vector3(12,rise*3,-5.5),
		Vector3(PLATFORM_OFFSET,rise*3,-5.5), Vector3(PLATFORM_OFFSET,rise*3,0),
	])
	if station.region == "harbor":
		for i in local.size():
			if local[i].z == -4.0: local[i].z = 2.0
			elif local[i].z == -5.5: local[i].z = .5
	var result := PackedVector3Array([station.entry])
	for point in local: result.append(Vector3(origin.x+point.x*side,point.y+0.12,origin.z+point.z))
	return result

static func nodes() -> Dictionary:
	var result := {"junction_west":Vector3(350,14,-245), "junction_east":Vector3(420,14,-245), "north_throat":Vector3(386,12,-217)}
	for station in stations(): result[station.id] = station.position
	return result

static func edges() -> Array[Dictionary]:
	if not _edge_cache.is_empty(): return _edge_cache.duplicate(true)
	_edge_cache = [
		_edge("harbor_viaduct", "harbor_central", "harbor_north", [
			Vector3(-12,12,52), Vector3(-12,12,-18), Vector3(210,14,-18),
			Vector3(260,14,-65), Vector3(260,14,-157), Vector3(386,12,-157), Vector3(386,12,-194)]),
		_edge("north_throat", "harbor_north", "north_throat", [Vector3(386,12,-194), Vector3(386,12,-217)]),
		_coastal_edge(),
		_north_east_edge(),
		_edge("north_west", "north_throat", "junction_west", [
			Vector3(386,12,-217), Vector3(368,14,-238), Vector3(350,14,-245)]),
		_edge("junction_chord", "junction_west", "junction_east", [
			Vector3(350,14,-245), Vector3(364,14,-261), Vector3(406,14,-261), Vector3(420,14,-245)]),
		_edge("pines_scenic", "junction_east", "mountain_pines", [
			Vector3(420,14,-245), Vector3(490,14,-245), Vector3(680,14,-245),
			Vector3(730,12,-286), Vector3(730,12,-340), Vector3(730,12,-402)]),
		_edge("copper_express", "junction_west", "desert_copper", [
			Vector3(350,14,-245), Vector3(315,14,-275), Vector3(315,14,-400),
			Vector3(315,12,-745), Vector3(290,12,-770), Vector3(10,12,-770),
			Vector3(-72,12,-850), Vector3(-72,12,-925)], true),
	]
	return _edge_cache.duplicate(true)

static func _north_east_edge() -> Dictionary:
	var points := PackedVector3Array()
	# The curve starts beyond the platform and its full coach overhang.
	for i in 29:
		var t := float(i)/28.0
		var angle := PI+t*PI*.5
		points.append(Vector3(414.0+28.0*cos(angle),lerpf(12,14,t),-217.0+28.0*sin(angle)))
	_append_segment(points,Vector3(420,14,-245))
	return {"id":"north_east","from":"north_throat","to":"junction_east","points":points,
		"length":route_length(points),"requires_act1":false}

static func _coastal_edge() -> Dictionary:
	var points := PackedVector3Array()
	# A quarter circle begins eastbound, tangent to the common mountain throat.
	for i in 19:
		var angle := -PI*.5+float(i)/18.0*PI*.5
		points.append(Vector3(420.0+18.0*cos(angle),14,-227.0+18.0*sin(angle)))
	var tail := _rounded([Vector3(438,14,-227),Vector3(438,14,-100),Vector3(430,14,-70),
		Vector3(430,14,45),Vector3(540,14,45),Vector3(540,14,162),Vector3(440,14,162),
		Vector3(210,14,162),Vector3(-17,12,162),Vector3(-17,12,92)],18.0)
	for i in range(1,tail.size()): points.append(tail[i])
	# Ease back to the station after clearing the saved western infill block.
	for i in range(1,17):
		var t := float(i)/16.0
		points.append(Vector3(-17.0+5.0*smoothstep(0,1,t),12,92.0-16.0*t))
	_append_segment(points,Vector3(-12,12,52))
	return {"id":"harbor_coast","from":"junction_east","to":"harbor_central","points":points,
		"length":route_length(points),"requires_act1":false}

static func _edge(id: String, from: String, to: String, controls: Array, gated := false) -> Dictionary:
	var points := _rounded(controls, 18.0)
	return {"id":id, "from":from, "to":to, "points":points,
		"length":route_length(points), "requires_act1":gated}

static func get_route(from_id: String, to_id: String) -> PackedVector3Array:
	if from_id == to_id or get_station(from_id).is_empty() or get_station(to_id).is_empty():
		return PackedVector3Array()
	if from_id == "harbor_north" and to_id == "harbor_central":
		var loop := PackedVector3Array()
		for id in ["north_throat", "north_east", "harbor_coast"]:
			for edge in edges():
				if edge.id != id: continue
				for point in edge.points:
					if loop.is_empty() or not loop[-1].is_equal_approx(point): loop.append(point)
		return loop
	var distances := {from_id:0.0}
	var previous := {}
	var open: Array[String] = [from_id]
	var all_edges := edges()
	while not open.is_empty():
		var current: String = open[0]
		for id in open:
			if float(distances[id]) < float(distances[current]): current = id
		open.erase(current)
		if current == to_id: break
		for edge in all_edges:
			if current != edge.from and current != edge.to: continue
			var next: String = edge.to if current == edge.from else edge.from
			var cost := float(distances[current]) + float(edge.length)
			if cost >= float(distances.get(next, INF)): continue
			distances[next] = cost
			previous[next] = {"node":current, "edge":edge}
			if next not in open: open.append(next)
	if not previous.has(to_id): return PackedVector3Array()
	var path: Array[PackedVector3Array] = []
	var cursor := to_id
	while cursor != from_id:
		var step: Dictionary = previous[cursor]
		var points: PackedVector3Array = step.edge.points.duplicate()
		if step.edge.to != cursor: points.reverse()
		path.push_front(points)
		cursor = step.node
	var result := PackedVector3Array()
	for points in path:
		for point in points:
			if result.is_empty() or result[-1].distance_squared_to(point) > 0.000001: result.append(point)
	return result

static func route_points() -> PackedVector3Array:
	return get_route("harbor_central", "mountain_pines")

static func route_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
	return total

static func sample(points: PackedVector3Array, distance: float) -> Dictionary:
	if points.size() < 2: return {"position":Vector3.ZERO, "direction":Vector3.FORWARD, "yaw":0.0}
	var remaining := maxf(0.0, distance)
	for index in range(1, points.size()):
		var delta := points[index] - points[index - 1]
		var length := delta.length()
		if remaining <= length or index == points.size() - 1:
			var direction := delta.normalized()
			return {"position":points[index - 1].lerp(points[index], clampf(remaining / maxf(length,0.001),0,1)),
				"direction":direction, "yaw":atan2(-direction.x, -direction.z)}
		remaining -= length
	return {}

static func tunnels() -> Array[Dictionary]:
	return [
		{"id":"pines_gallery", "a":Vector3(588,14,-245), "b":Vector3(643,14,-245), "region":"mountain", "color":Color("70746b")},
		{"id":"copper_gallery", "a":Vector3(315,13.55,-478), "b":Vector3(315,13.18,-542), "region":"desert", "color":Color("a88862")},
	]

static func _rounded(controls: Array, radius: float) -> PackedVector3Array:
	var result := PackedVector3Array([controls[0]])
	for i in range(1, controls.size() - 1):
		var before: Vector3 = controls[i - 1]
		var point: Vector3 = controls[i]
		var after: Vector3 = controls[i + 1]
		var entry := point.move_toward(before, minf(radius, point.distance_to(before) * 0.35))
		var leave := point.move_toward(after, minf(radius, point.distance_to(after) * 0.35))
		_append_segment(result, entry)
		var steps := maxi(6, ceili(entry.distance_to(leave) / 2.0))
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			result.append(entry.lerp(point,t).lerp(point.lerp(leave,t),t))
	_append_segment(result, controls[-1])
	return result

static func _append_segment(result: PackedVector3Array, end: Vector3) -> void:
	var start := result[-1]
	var count := maxi(1, ceili(start.distance_to(end) / 5.0))
	for index in range(1, count + 1): result.append(start.lerp(end,float(index) / float(count)))
