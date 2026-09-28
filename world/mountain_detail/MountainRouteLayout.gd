extends RefCounted
const CATALOG := preload("res://world/places/PlaceCatalog.gd")

static func main_route(source_controls: Array) -> PackedVector3Array:
	var controls := PackedVector2Array()
	for point in source_controls: controls.append(Vector2(point[0],point[1]))
	controls[-1] = Vector2(6590,-2660)
	var curve := Curve2D.new()
	curve.bake_interval = 16
	for i in controls.size():
		var tangent := Vector2.ZERO
		if i > 0 and i < controls.size()-1:
			tangent = (controls[i+1]-controls[i-1]).normalized()*minf(controls[i-1].distance_to(controls[i]),controls[i+1].distance_to(controls[i]))*.38
		curve.add_point(controls[i],-tangent,tangent)
	var points := PackedVector3Array()
	for distance in range(0,int(curve.get_baked_length()),64):
		points.append(CATALOG._at(curve.sample_baked(distance,true),"mountain"))
	points.append(CATALOG._at(controls[-1],"mountain"))
	return points

static func branches(main: PackedVector3Array) -> Array[Dictionary]:
	var authored := [
		["mountain_track_1",3.75,"earth",[Vector2(6250,340),Vector2(6850,690),Vector2(7350,620),Vector2(7850,580),Vector2(8350,480),Vector2(8700,460)]],
		["mountain_track_2",5.0,"asphalt",[Vector2(6950,-250),Vector2(7150,-350),Vector2(7450,-320),Vector2(7850,-320),Vector2(7850,-135),Vector2(7750,-135)]],
		["mountain_track_4",5.0,"asphalt",[Vector2(6850,-2450),Vector2(7020,-2500),Vector2(7140,-2545),Vector2(7140,-2678)]],
		["mountain_track_5",5.0,"asphalt",preload("res://world/mountain_detail/OriginalVillageLayout.gd").ACCESS_CORRIDORS[0]],
	]
	var result: Array[Dictionary] = []
	for row in authored:
		var points := PackedVector3Array()
		for point in row[3]: points.append(CATALOG._at(point,"mountain"))
		result.append({"id":row[0],"width":row[1],"surface":row[2],"points":snap_start(points,main)})
	var village_return := PackedVector3Array()
	for point in preload("res://world/mountain_detail/OriginalVillageLayout.gd").ACCESS_CORRIDORS[1]:
		village_return.append(CATALOG._at(point,"mountain"))
	village_return.reverse()
	result.append({"id":"mountain_village_return","width":5.0,"surface":"asphalt","points":snap_start(village_return,main)})
	result.append({"id":"mountain_turnaround","width":5.0,"surface":"asphalt","points":turnaround()})
	return result

static func turnaround() -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 25:
		var angle := TAU*float(i)/24.0
		points.append(CATALOG._at(Vector2(6500,-2660)+Vector2(cos(angle),sin(angle))*90.0,"mountain"))
	points[-1] = points[0]
	return points

static func paths() -> Array[Dictionary]:
	# Approach doors from their open side. The cave trail ends on the dry bank;
	# its existing stepping stones and automatic threshold own the last metres.
	var authored := [
		["cave_trail",1.6,[Vector2(6120,320),Vector2(5910,220),Vector2(5850,20),Vector2(5890,-160),Vector2(6020,-215),Vector2(6130,-200),Vector2(6200,-240)]],
		["forest_shop_walk",1.8,[Vector2(6030,380),Vector2(5860,490),Vector2(5860,710),Vector2(5980,719),Vector2(5980,703)]],
		["forest_cabin_walk",1.6,[Vector2(5980,719),Vector2(6120,725),Vector2(6120,850),Vector2(6050,850),Vector2(6050,834)]],
		["helipad_walk",1.8,[Vector2(6410,-2660),Vector2(6440,-2720),Vector2(6365,-2720),Vector2(6335,-2735),Vector2(6335,-2765)]],
		["bunker_walk",1.8,[Vector2(6500,-2750),Vector2(6500,-2820)]],
		["lift_walk",2.2,[Vector2(7000,-2494),Vector2(6960,-2630),Vector2(6820,-2780),Vector2(6820,-2920),Vector2(6880,-2920),Vector2(6880,-2938.2)]],
		["summit_shop_walk",1.8,[Vector2(7140,-2678),Vector2(7250,-2678),Vector2(7400,-2678),Vector2(7400,-2682)]],
	]
	var result: Array[Dictionary] = []
	for row in authored:
		var points := PackedVector3Array()
		for point in row[2]: points.append(CATALOG._at(point,"mountain"))
		result.append({"id":row[0],"width":row[1],"points":points,"surface":"footpath"})
	return result

static func snap_start(points: PackedVector3Array, road: PackedVector3Array) -> PackedVector3Array:
	var result := points.duplicate()
	var best := INF
	for i in range(road.size()-1):
		var candidate := Geometry3D.get_closest_point_to_segment(points[0],road[i],road[i+1])
		var distance := candidate.distance_squared_to(points[0])
		if distance < best:
			best = distance
			result[0] = candidate
	return result
