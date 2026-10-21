extends SceneTree
## Lane geometry contracts. Rendered physical driving with visitors remains a
## separate integration check; this test does not certify steering or FPS.
const ARRIVAL := preload("res://activities/desert_drag/DragArrivalPath.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROAD_GEOMETRY := preload("res://world/desert/DesertRoadGeometry.gd")
const ROSTER := preload("res://activities/desert_drag/DragOpenRoster.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
var checks := 0
var failures: Array[String] = []
var footprint_samples := 0
var bad_samples: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _signed_offset(point: Vector3, center: PackedVector3Array) -> float:
	var best := INF
	var signed := 0.0
	for index in range(1,center.size()):
		var a := Vector2(center[index-1].x,center[index-1].z)
		var b := Vector2(center[index].x,center[index].z)
		var p := Vector2(point.x,point.z)
		var nearest := Geometry2D.get_closest_point_to_segment(p,a,b)
		var distance := p.distance_squared_to(nearest)
		if distance>=best: continue
		best=distance
		var forward := (center[index]-center[index-1]).normalized()
		signed=(point-Vector3(nearest.x,point.y,nearest.y)).dot(forward.cross(Vector3.UP))
	return signed

func _paved(point: Vector3, corridors: Array[Dictionary]) -> bool:
	var flat := Vector2(point.x,point.z)
	for corridor in corridors:
		if Geometry2D.is_point_in_polygon(flat,corridor.polygon): return true
	return false

func run() -> void:
	var east := {"points":PackedVector3Array([Vector3.ZERO,Vector3(300,0,0)]),"width":8.0}
	var west := {"points":PackedVector3Array([Vector3(300,0,0),Vector3.ZERO]),"width":8.0}
	var incoming := ARRIVAL.build(east)
	var outgoing := ARRIVAL.build(west)
	check(incoming.size()==2 and incoming[0].is_equal_approx(Vector3(100,.08,2)), "Visitor enters 100 m along the access in the right-hand eastbound lane")
	check(outgoing.size()==2 and outgoing[0].is_equal_approx(Vector3(200,.08,-2)), "Reversing travel reverses the lane side and preserves the 100 m entry distance")
	if incoming.size()==2 and outgoing.size()==2:
		var meet_east := incoming[0].lerp(incoming[1],.25)
		var meet_west := outgoing[0].lerp(outgoing[1],.25)
		check(is_equal_approx(meet_east.x,meet_west.x) and is_equal_approx(meet_east.distance_to(meet_west),4.0), "Opposing vehicles at the same station have four metres of lane separation")
	check(ARRIVAL.build({"points":PackedVector3Array([Vector3.ZERO,Vector3(99,0,0)]),"width":8.0}).is_empty(), "An access shorter than the entry distance cannot spawn a visitor on its junction")
	var road: Dictionary = {}
	for candidate in LAYOUT.roads():
		if candidate.id=="desert_drag_access": road=candidate; break
	check(not road.is_empty(), "The real authored access exists")
	if road.is_empty(): finish(); return
	var original := road.duplicate(true)
	var arrival := ARRIVAL.build(road)
	check(road==original, "Building one visitor route preserves the shared authored geometry")
	check(arrival.size()>4, "The actual curved access produces a useful arrival route")
	if arrival.size()<2: finish(); return
	var start: Vector3 = road.points[0]
	check(arrival[0].distance_to(start)>80.0, "Admission is clear of the public-road entry junction")
	check(arrival[-1].is_equal_approx(Vector3(-786,.08,-800)), "The access joins the existing strip queue in the right-hand lane")
	var in_lane := true
	var distinct := true
	for index in arrival.size():
		var side := _signed_offset(arrival[index],road.points)
		in_lane=in_lane and side>0.0 and side<float(road.width)*.5
		if index>0: distinct=distinct and arrival[index].distance_to(arrival[index-1])>.001
	check(in_lane and distinct, "All real curved-road waypoints remain on the travel-right side without folded or duplicate segments")
	var geometry := ROAD_GEOMETRY.new()
	geometry.configure(LAYOUT.roads())
	var models: Array[String] = []
	for row in ROSTER.CARS.values():
		if not models.has(str(row.car)): models.append(str(row.car))
	for model in models:
		var bounds: Array = FLEET.spec(model).bounds_size
		var half := Vector2(float(bounds[0])*.5,float(bounds[2])*.5)
		var paved := true
		var right_half := true
		for index in range(1,arrival.size()):
			var a := arrival[index-1]
			var b := arrival[index]
			var forward := (b-a).normalized()
			var right := forward.cross(Vector3.UP)
			var steps := maxi(1,ceili(a.distance_to(b)/.5))
			for step in steps+1:
				var center := a.lerp(b,float(step)/float(steps))
				for across in [-half.x,half.x]:
					for along in [-half.y,half.y]:
						footprint_samples+=1
						var corner := center+right*float(across)+forward*float(along)
						var supported := _paved(corner,geometry.corridors)
						var signed := _signed_offset(corner,road.points)
						paved=supported and paved
						right_half=(signed>0.0) and right_half
						if (not supported or signed<=0.0) and bad_samples.size()<24:
							bad_samples.append({"model":model,"segment":index-1,"step":step,"center":str(center),"corner":str(corner),"paved":supported,"signed_lane":signed})
		check(paved, "Full catalog body remains over the actual rendered pavement through access curves: "+model)
		check(right_half, "Every catalog body corner stays in the right-hand carriageway through curves: "+model)
	finish()

func finish() -> void:
	print(JSON.stringify({"checks":checks,"failures":failures,"footprint_samples":footprint_samples,"bad_samples":bad_samples,"scope":"Pure route/pavement contracts; no physics or rendered performance approval."}))
	quit(0 if failures.is_empty() else 1)
