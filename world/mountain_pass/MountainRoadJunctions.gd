extends RefCounted
## Flared junction surfaces and barrier openings share the actual access curves.
var road_curve: Curve2D
var half_road := 70.0
var mouths: Array[Dictionary] = []
var _through_road: PackedVector2Array

func add_access(access: Curve2D, half_width: float, at_end := false, label := "") -> void:
	for mouth in mouths:
		if mouth.label == label: return
	var length := access.get_baked_length()
	var centers := PackedVector2Array()
	var distances := PackedFloat32Array()
	for step in range(0,mini(int(length),420)+1,3):
		var offset := length-float(step) if at_end else float(step)
		var point := access.sample_baked(offset,true)
		var distance := point.distance_to(road_curve.get_closest_point(point))
		centers.append(point)
		distances.append(distance)
		if distance > half_road+110: break
	if centers.size()<2:return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in centers.size():
		var tangent := (centers[mini(i+1,centers.size()-1)]-centers[maxi(0,i-1)]).normalized()
		var normalized := (distances[i]-half_road)/95.0
		var flare := 24.0*pow(maxf(0.0,1.0-normalized*normalized),2.0)
		var normal := tangent.orthogonal()*(half_width+flare)
		left.append(centers[i]+normal)
		right.append(centers[i]-normal)
	var polygon := left.duplicate()
	var reverse := right.duplicate()
	reverse.reverse()
	polygon.append_array(reverse)
	# Retain only the connected mouth on the destination side of the highway.
	# A wide coach corridor beginning in a traffic lane can otherwise nick the
	# opposite shoulder before the turn has even started.
	if _through_road.is_empty():
		var strips := Geometry2D.offset_polyline(road_curve.get_baked_points(),half_road-9.0,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
		if not strips.is_empty():_through_road=strips[0]
	for outside in Geometry2D.clip_polygons(polygon,_through_road):
		if Geometry2D.is_point_in_polygon(centers[-1],outside):
			polygon=outside
			break
	var clear_polygons := Geometry2D.offset_polygon(polygon,9.0,Geometry2D.JOIN_ROUND)
	var rims: Array[PackedVector2Array] = []
	var rim_bounds := Geometry2D.offset_polygon(polygon,0.2)
	for edge in [left,right]:
		for outside in _outside_road(edge):
			for bounds in rim_bounds:
				rims.append_array(Geometry2D.intersect_polyline_with_polygon(outside,bounds))
	mouths.append({"label":label,"polygon":polygon,"left":left,"right":right,"rims":rims,"clear":clear_polygons})

func contains(point: Vector2, barrier := false) -> bool:
	for mouth in mouths:
		if barrier:
			for polygon in mouth.clear:
				if Geometry2D.is_point_in_polygon(point,polygon):return true
		elif Geometry2D.is_point_in_polygon(point,mouth.polygon):return true
	return false

func draw_surfaces(canvas: Node2D, excluded_labels: PackedStringArray = []) -> void:
	for mouth in mouths:
		if mouth.label in excluded_labels: continue
		# The two curved rims stop at the far edge, never across the driveway.
		for rim in mouth.rims:
			if rim.size()>1:canvas.draw_polyline(rim,Color("5c656b"),7.0,true)
		canvas.draw_colored_polygon(mouth.polygon,Color("1a1e23"))
		for rim in mouth.rims:
			if rim.size()>1:canvas.draw_polyline(rim,Color("c7cacc"),2.0,true)

func clip_marking(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [points]
	for mouth in mouths:
		var remaining: Array[PackedVector2Array] = []
		for piece in pieces:
			remaining.append_array(Geometry2D.clip_polyline_with_polygon(piece,mouth.polygon))
		pieces = remaining
	return pieces

func _outside_road(edge: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var section := PackedVector2Array()
	var limit := half_road-8.0
	for i in edge.size():
		var outside := edge[i].distance_to(road_curve.get_closest_point(edge[i]))>=limit
		if i>0:
			var previous_outside := edge[i-1].distance_to(road_curve.get_closest_point(edge[i-1]))>=limit
			if outside!=previous_outside:
				var a := edge[i-1]
				var b := edge[i]
				for iteration in 12:
					var midpoint := a.lerp(b,0.5)
					if (midpoint.distance_to(road_curve.get_closest_point(midpoint))>=limit)==previous_outside:a=midpoint
					else:b=midpoint
				section.append(a.lerp(b,0.5))
				if not outside:
					if section.size()>1:result.append(section)
					section=PackedVector2Array()
		if outside:section.append(edge[i])
	if section.size()>1:result.append(section)
	return result
