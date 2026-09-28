@tool
extends RefCounted
## Editor-only geometry. Road IDs and centre-lines remain the traffic authority.
var surfaces: Array[Dictionary] = []
var markings: Array[Dictionary] = []
var junctions: Array[Dictionary] = []
var revision := 0
var pavement: Array = []
var crossings: Array = []
var _signature := -1

func configure(rows: Array) -> void:
	var signature := hash(rows)
	if signature == _signature: return
	_signature = signature
	# The preview uses the same in-memory endpoint joins as the runtime.
	var native_rows: Array = []
	for row in rows:
		if row.get("pathway",false): continue
		var source: Dictionary = row.duplicate(true)
		source.points = PackedVector3Array()
		for point in row.points: source.points.append(Vector3(point[0],0,point[1]))
		native_rows.append(source)
	var resolved := {}
	for row in preload("res://world/editing/WorldRoadJoins.gd").resolve(native_rows): resolved[row.id] = row.points
	rows = rows.duplicate(true)
	for row in rows:
		if not resolved.has(row.id): continue
		row.points = []
		for point in resolved[row.id]: row.points.append([point.x,point.z])
	revision += 1
	surfaces.clear()
	markings.clear()
	junctions.clear()
	pavement.clear()
	crossings.clear()
	var native := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	var sources: Array[Dictionary] = []
	for row in rows:
		if not row.get("urban",false): continue
		var source: Dictionary = row.duplicate(true)
		var points := PackedVector3Array()
		for point in row.points: points.append(Vector3(point[0],0,point[1]))
		source.points = points
		sources.append(source)
	if not sources.is_empty():
		native.configure(sources)
		pavement.assign(native._layers[0].polygons)
		crossings.assign(native._crosswalk_white)
	var segments: Array[Dictionary] = []
	for row in rows:
		var points := PackedVector2Array()
		for p in row.points: points.append(Vector2(p[0],p[1]))
		for i in range(points.size()-1):
			if points[i].distance_to(points[i+1]) < .01: continue
			segments.append({"a":points[i],"b":points[i+1],"width":float(row.width),"id":row.id,"surface":row.surface})
		var layers: Array = []
		for extra in [.22,0.0]:
			layers.append(_ribbons(points,float(row.width)*.5+extra))
		surfaces.append({"border":layers[0],"fill":layers[1],"surface":row.surface})
	for i in segments.size():
		var first := segments[i]
		for j in range(i+1,segments.size()):
			var second := segments[j]
			var hit: Variant = Geometry2D.segment_intersects_segment(first.a,first.b,second.a,second.b)
			if not hit is Vector2: continue
			var junction: Dictionary = {}
			for existing in junctions:
				if existing.at.distance_to(hit) < .01:
					junction = existing
					break
			if junction.is_empty():
				junction = {"at":hit,"arms":[],"radius":0.0}
				junctions.append(junction)
			for segment in [first,second]:
				for end in [segment.a,segment.b]:
					if end.distance_to(hit) < .01: continue
					var direction: Vector2 = hit.direction_to(end)
					var found := false
					for arm in junction.arms:
						if arm.direction.dot(direction) > .9999:
							arm.width = maxf(arm.width,segment.width)
							arm.length = minf(arm.length,hit.distance_to(end))
							found = true
							break
					if not found: junction.arms.append({"direction":direction,"width":segment.width,"length":hit.distance_to(end),"surface":segment.surface})
	# Two arms are a bend or continuation, not a traffic intersection.
	junctions = junctions.filter(func(j): return j.arms.size() >= 3)
	for junction in junctions:
		junction.arms.sort_custom(func(a,b): return a.direction.angle() < b.direction.angle())
		for arm in junction.arms: junction.radius = maxf(junction.radius,arm.width*.65+1)
		for i in junction.arms.size():
			var first: Dictionary = junction.arms[i]
			var second: Dictionary = junction.arms[(i+1)%junction.arms.size()]
			var layers: Array = []
			for extra in [.22,0.0]: layers.append(_corner(junction.at,first,second,extra))
			if not layers[1].is_empty(): surfaces.append({"border":[layers[0]],"fill":[layers[1]],"surface":first.surface})
	for segment in segments:
		var pieces: Array[PackedVector2Array] = [PackedVector2Array([segment.a,segment.b])]
		for junction in junctions:
			if Geometry2D.get_closest_point_to_segment(junction.at,segment.a,segment.b).distance_to(junction.at) > .02: continue
			var mask := PackedVector2Array()
			for i in 32: mask.append(junction.at+Vector2.from_angle(TAU*i/32.0)*float(junction.radius))
			var remaining: Array[PackedVector2Array] = []
			for piece in pieces: remaining.append_array(Geometry2D.clip_polyline_with_polygon(piece,mask))
			pieces = remaining
		for mask in native._crossing_masks:
			var remaining: Array[PackedVector2Array] = []
			for piece in pieces: remaining.append_array(Geometry2D.clip_polyline_with_polygon(piece,mask))
			pieces = remaining
		for piece in pieces: markings.append({"id":segment.id,"points":piece})

func _ribbons(points: PackedVector2Array, half_width: float) -> Array[PackedVector2Array]:
	var polygons := Geometry2D.offset_polyline(points,half_width,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT)
	if polygons.size() <= 1: return polygons
	# Canvas polygons cannot encode holes. Short overlapping ribbons preserve the
	# empty island inside a loop instead of painting its inner contour as asphalt.
	var pieces: Array[PackedVector2Array] = []
	for i in range(points.size()-2):
		pieces.append_array(Geometry2D.offset_polyline(points.slice(i,i+3),half_width,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT))
	return pieces

func _corner(at: Vector2, first: Dictionary, second: Dictionary, extra: float) -> PackedVector2Array:
	var a: Vector2 = first.direction
	var b: Vector2 = second.direction
	var angle := fposmod(b.angle()-a.angle(),TAU)
	if angle < .25 or angle >= PI-.01: return PackedVector2Array()
	var hit: Variant = Geometry2D.line_intersects_line(at-a.orthogonal()*(first.width*.5+extra),a,at+b.orthogonal()*(second.width*.5+extra),b)
	if not hit is Vector2: return PackedVector2Array()
	var radius := minf(minf(first.width,second.width)*.3,minf(first.length,second.length)*.2)
	# Sub-centimetre authored seams have no room for a fillet; retain the joined
	# road ribbons there instead of emitting near-coincident float32 vertices.
	if radius < .05: return PackedVector2Array()
	if hit.distance_to(at) > maxf(first.width,second.width)*2: return PackedVector2Array()
	var start: Vector2 = hit+a*radius
	var finish: Vector2 = hit+b*radius
	var polygon := PackedVector2Array([at,start])
	for i in range(1,9):
		var t := float(i)/8
		polygon.append(start*(1-t)*(1-t)+hit*2*t*(1-t)+finish*t*t)
	polygon.append(at)
	polygon.resize(polygon.size()-1)
	return polygon
