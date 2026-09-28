extends RefCounted
## Built once per region. Road footprints also cut shoulders and joining paths.
var footprints: Array[Dictionary] = []

static func edges(points: PackedVector3Array, width: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var closed := points[0].is_equal_approx(points[-1])
	for i in points.size():
		var previous := points[points.size()-2] if closed and i == 0 else points[maxi(0,i-1)]
		var next := points[1] if closed and i == points.size()-1 else points[mini(points.size()-1,i+1)]
		var incoming := (points[i]-previous).normalized()
		var outgoing := (next-points[i]).normalized()
		if incoming.is_zero_approx(): incoming = outgoing
		if outgoing.is_zero_approx(): outgoing = incoming
		var normal := Vector3(outgoing.z,0,-outgoing.x)
		var miter := (Vector3(incoming.z,0,-incoming.x)+normal).normalized()
		if miter.is_zero_approx(): miter = normal
		var reach := width*.5/maxf(.45,miter.dot(normal))
		result.append({"left":points[i]+miter*reach,"right":points[i]-miter*reach})
	return result

static func polygon(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector2Array:
	var result := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z),Vector2(c.x,c.z),Vector2(d.x,d.z)])
	if Geometry2D.is_polygon_clockwise(result): result.reverse()
	return result

static func bounds(polygon_points: PackedVector2Array) -> Rect2:
	var rect := Rect2(polygon_points[0],Vector2.ZERO)
	for point in polygon_points: rect = rect.expand(point)
	return rect

func configure(roads: Array[Dictionary]) -> void:
	footprints.clear()
	for road in roads:
		var outline := edges(road.points,float(road.width))
		for i in range(outline.size()-1):
			var shape := polygon(outline[i].left,outline[i+1].left,outline[i+1].right,outline[i].right)
			footprints.append({"id":road.id,"polygon":shape,"bounds":bounds(shape)})

func outside_roads(shape: PackedVector2Array, excluded_id := "", earlier_only := false) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [shape]
	var rect := bounds(shape)
	for footprint in footprints:
		# Surface precedence follows configure(): main road, branches, then paths.
		if footprint.id == excluded_id:
			if earlier_only: break
			continue
		if not rect.intersects(footprint.bounds): continue
		var remaining: Array[PackedVector2Array] = []
		for piece in pieces:
			for clipped in Geometry2D.clip_polygons(piece,footprint.polygon):
				if clipped.size() >= 3: remaining.append(clipped)
		pieces = remaining
		if pieces.is_empty(): break
	return pieces

func contains(point: Vector3, clearance: float = 0.0) -> bool:
	var flat := Vector2(point.x,point.z)
	for footprint in footprints:
		if not footprint.bounds.grow(clearance).has_point(flat): continue
		if Geometry2D.is_point_in_polygon(flat,footprint.polygon): return true
		if clearance <= 0.0: continue
		var shape: PackedVector2Array = footprint.polygon
		for i in shape.size():
			if flat.distance_to(Geometry2D.get_closest_point_to_segment(flat,shape[i],shape[(i+1)%shape.size()])) < clearance: return true
	return false
