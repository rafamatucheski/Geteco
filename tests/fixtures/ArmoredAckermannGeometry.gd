extends "res://gameplay/NativeTrafficRoutes.gd"
## Only the convoy uses this geometry. The shared traffic graph is unchanged.
## Vehicle's 2.5 m wheelbase and .48 rad steering need >= 4.8 m radius.
const TURN_RADIUS := 5.0
var turn_diagnostics: Array = []
var asphalt: Array = []
var turn_failure: Dictionary = {}

func configure_surfaces(roads: Array) -> void:
	var authored: Array[Dictionary] = []
	for road in roads:
		var line: PackedVector3Array = road.get("points",PackedVector3Array())
		if line.is_empty() or line[0].z < -270 or absf(line[0].y) > .1: continue
		authored.append(road)
	var geometry := preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new()
	geometry.configure(authored,false)
	# Exactly the source renderer's road layer, including its junction aprons.
	asphalt = geometry._layer(geometry.ROAD_COLOR,0.0,.026).polygons

func _curve(path: Array[int], closed: bool, lane_index := 0) -> Curve3D:
	var curve := super._curve(path,closed,lane_index)
	if closed: return curve
	var geometry := _curve_geometry(path,false)
	var points: Array[Vector3] = geometry.points
	var sections: Array[Dictionary] = geometry.sections
	turn_diagnostics.clear()
	for index in range(points.size()-2,0,-1):
		var at: Vector3 = points[index]
		var incoming := points[index-1].direction_to(at)
		var outgoing := at.direction_to(points[index+1])
		var angle := incoming.angle_to(outgoing)
		if angle < .35 or angle > 2.3: continue
		var first: Dictionary = sections[index-1]
		var second: Dictionary = sections[index]
		var in_offset := _lane_offset(incoming,first,lane_index)
		var out_offset := _lane_offset(outgoing,second,lane_index)
		var in_lane := at+in_offset
		var out_lane := at+out_offset
		var cross2: Variant = Geometry2D.line_intersects_line(_xz(in_lane),_xz(incoming),_xz(out_lane),_xz(outgoing))
		if not cross2 is Vector2: continue
		var cross := Vector3(cross2.x,at.y,cross2.y)
		var tangent := TURN_RADIUS*tan(angle*.5)
		var entry_index := index*2-1
		var exit_index := index*2
		# Already-wide left turns keep their native lane geometry.
		if curve.get_point_position(entry_index).distance_to(cross) >= tangent: continue
		var handle := 4.0/3.0*TURN_RADIUS*tan(angle*.25)
		var chosen: Curve3D
		turn_failure = {}
		var selected_shift := 0.0
		for shift in [0.0]:
			var in_shift: Vector3 = in_offset.normalized()*minf(shift,maxf(0,in_offset.length()-1.3))
			var out_shift: Vector3 = out_offset.normalized()*minf(shift,maxf(0,out_offset.length()-1.3))
			var adjusted: Vector2 = Geometry2D.line_intersects_line(_xz(in_lane-in_shift),_xz(incoming),_xz(out_lane-out_shift),_xz(outgoing))
			var center := Vector3(adjusted.x,at.y,adjusted.y)
			var entry := center-incoming*tangent
			var exit := center+outgoing*tangent
			var before := entry-incoming*.5+in_shift
			var after := exit+outgoing*.5+out_shift
			if (before-points[index-1]).dot(incoming) < 3.0 or (points[index+1]-after).dot(outgoing) < 3.0:
				turn_failure = {"reason":"adjacent_corner","before":before,"after":after,"previous":points[index-1],"next":points[index+1]}
				continue
			var candidate := Curve3D.new()
			candidate.bake_interval = .1
			candidate.add_point(before,Vector3.ZERO,incoming*.16)
			candidate.add_point(entry,-incoming*.16,incoming*handle)
			candidate.add_point(exit,-outgoing*handle,outgoing*.16)
			candidate.add_point(after,-outgoing*.16,Vector3.ZERO)
			if _fits_road_union(candidate,points[index-1],at,points[index+1],float(first.width),float(second.width)):
				chosen = candidate
				selected_shift = shift
				break
		turn_diagnostics.append({"point":at,"fits":chosen != null,"failure":turn_failure,"shift":selected_shift,"roads":[first.id,second.id],"block":[first.from,first.to],"widths":[first.width,second.width]})
		if chosen == null: continue
		curve.set_point_position(entry_index,chosen.get_point_position(1))
		curve.set_point_in(entry_index,chosen.get_point_in(1))
		curve.set_point_out(entry_index,chosen.get_point_out(1))
		curve.set_point_position(exit_index,chosen.get_point_position(2))
		curve.set_point_in(exit_index,chosen.get_point_in(2))
		curve.set_point_out(exit_index,chosen.get_point_out(2))
		curve.add_point(chosen.get_point_position(3),chosen.get_point_in(3),Vector3.ZERO,exit_index+1)
		curve.add_point(chosen.get_point_position(0),Vector3.ZERO,chosen.get_point_out(0),entry_index)
	return curve

func _fits_road_union(candidate: Curve3D, a: Vector3, at: Vector3, b: Vector3, width_a: float, width_b: float) -> bool:
	var road_a := _strip(a,at,width_a)
	var road_b := _strip(at,b,width_b)
	var surfaces: Array = [road_a,road_b]
	if at.z > -270 and absf(at.y) < .1:
		var bounds := Rect2(_xz(at)-Vector2.ONE*22.0,Vector2.ONE*44.0)
		for polygon in asphalt:
			var rect := Rect2(polygon[0],Vector2.ZERO)
			for p in polygon: rect = rect.expand(p)
			if rect.intersects(bounds): surfaces.append(polygon)
	for step in range(0,int(ceil(candidate.get_baked_length()*4.0))+1):
		var distance := minf(float(step)*.25,candidate.get_baked_length())
		var center := candidate.sample_baked(distance,true)
		var direction := (candidate.sample_baked(minf(distance+.05,candidate.get_baked_length()),true)-candidate.sample_baked(maxf(0,distance-.05),true)).normalized()
		var side := direction.cross(Vector3.UP)
		var hull := PackedVector2Array([_xz(center-direction*3.0-side*1.25),_xz(center+direction*3.0-side*1.25),_xz(center+direction*3.0+side*1.25),_xz(center-direction*3.0+side*1.25)])
		var remainder: Array = [hull]
		for surface in surfaces:
			var next: Array = []
			for piece in remainder: next.append_array(Geometry2D.clip_polygons(piece,surface))
			remainder = next
			if remainder.is_empty(): break
		if not remainder.is_empty():
			turn_failure = {"reason":"footprint","point":center,"outside":remainder}
			return false
	return true

func _strip(a: Vector3, b: Vector3, width: float) -> PackedVector2Array:
	var side := a.direction_to(b).cross(Vector3.UP)*width*.5
	return PackedVector2Array([_xz(a-side),_xz(b-side),_xz(b+side),_xz(a+side)])
