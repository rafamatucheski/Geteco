extends RefCounted
## Sidewalk centers follow the width of each bordering road.
const BLOCKS := [Rect2(477,482,736,686),Rect2(1387,482,736,686),Rect2(2277,482,641,686),Rect2(477,1332,736,786),Rect2(1387,1332,736,786),Rect2(2277,1332,641,786)]

static func circuit(box: Rect2) -> PackedVector2Array:
	return PackedVector2Array([box.position,Vector2(box.end.x,box.position.y),box.end,Vector2(box.position.x,box.end.y),box.position])

static func from_entry(box: Rect2, entry: Vector2) -> PackedVector2Array:
	var corners := circuit(box)
	var best := 0
	var distance := INF
	for i in 4:
		var d := entry.distance_to(Geometry2D.get_closest_point_to_segment(entry,corners[i],corners[i+1]))
		if d < distance:
			distance = d
			best = i
	var result := PackedVector2Array([entry])
	for i in 4: result.append(corners[(best+1+i)%4])
	result.append(entry)
	return result

static func connected_routes(tree: SceneTree) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for crossing in tree.get_nodes_in_group("road_crossing_area"):
		var a: Vector2 = crossing.to_global(Vector2(0,-crossing.road_width*0.5-22))
		var b: Vector2 = crossing.to_global(Vector2(0,crossing.road_width*0.5+22))
		var ai := -1
		var bi := -1
		for i in BLOCKS.size():
			var box: Rect2 = BLOCKS[i]
			if box.grow(2).has_point(a) and not box.grow(-3).has_point(a): ai=i
			if box.grow(2).has_point(b) and not box.grow(-3).has_point(b): bi=i
		if ai < 0 or bi < 0 or ai == bi: continue
		var route := from_entry(BLOCKS[ai],a)
		route.append_array(from_entry(BLOCKS[bi],b))
		route.append(a)
		result.append(route)
	return result

static func crossing_wait(actor: CharacterBody2D, destination: Vector2) -> bool:
	for crossing in actor.get_tree().get_nodes_in_group("road_crossing_area"):
		var p: Vector2 = crossing.to_local(actor.global_position)
		var goal: Vector2 = crossing.to_local(destination)
		if absf(p.x)>18 or absf(goal.x)>18 or p.y*goal.y>=0: continue
		# Once committed, finish crossing even when the signal changes.
		if absf(p.y)<crossing.road_width*0.5+8: continue
		if absf(p.y)>crossing.road_width*0.5+40: continue
		crossing.pedestrian_request.emit(crossing.crossing_id,crossing.junction_id)
		if not crossing.is_pedestrian_allowed(): return true
		for car in actor.get_tree().get_nodes_in_group("vehicle"):
			if not is_instance_valid(car) or not car.is_visible_in_tree(): continue
			var v = car.get("velocity")
			if not v is Vector2: continue
			var now: Vector2 = crossing.to_local(car.global_position)
			var future: Vector2 = crossing.to_local(car.global_position+v*1.8)
			if absf(now.y)<crossing.road_width*0.5+18 and (absf(now.x)<65 or (now.x*future.x<=0 and absf(now.x)<320)):
				return true
	return false
