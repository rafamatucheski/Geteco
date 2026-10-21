extends SceneTree
## Finite geometry + real collision oracle. Real driving/appearance/performance
## remain the parent's serialized rendered-Main validation.
const L := preload("res://world/desert/DesertLayout.gd")
const GEOMETRY := preload("res://world/desert/DesertRoadGeometry.gd")
const UTILITY := preload("res://world/desert/DesertUtilityLines.gd")
const ROUTES := preload("res://gameplay/NativeTrafficRoutes.gd")
const BRIDGE_STYLE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
var failures: Array[String] = []
var checks := 0
var geometry: RefCounted

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("DESERT_ROADS timeout"); quit(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks+=1
	print("DESERT_ROADS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _inside(point: Vector2) -> bool:
	for row in geometry.corridors:
		if Geometry2D.is_point_in_polygon(point,row.polygon): return true
	return false

func _painted(point: Vector2) -> bool:
	for row in geometry.paint:
		if Geometry2D.is_point_in_polygon(point,row.polygon): return true
	return false

func _run() -> void:
	var roads := L.roads()
	geometry=GEOMETRY.new(); geometry.configure(roads)
	var edge_inset: float=BRIDGE_STYLE.EDGE_LINE_INSET if BRIDGE_STYLE.enabled() else .25
	_check(geometry.junctions.size()>=7,"T intersections are explicit centre-line vertices")
	_check(not _painted(Vector2(342.5-(5.0-edge_inset),-540)),"west edge is interrupted at Route 66 / town mouth")
	_check(_painted(Vector2(342.5+(5.0-edge_inset),-540)),"opposite Route 66 edge stays continuous across a T")
	_check(not _painted(Vector2(342.5,-540)),"no half dash remains through the T centre")
	_check(not _painted(Vector2(-110,-540-(4.5-edge_inset))),"town edge is interrupted at Digo street")
	_check(_painted(Vector2(340,-547)) and not _painted(Vector2(345,-547)),"native seven-metre stop bar marks only the incoming lane")
	_check(not _painted(Vector2(-1062,-751)),"race-only branch does not add a stop bar to the ambient highway")
	_check(_inside(Vector2(336,-534)),"turning fillet supplies paved support outside original T rectangle")
	_check(not _inside(Vector2(325,-523)),"fillet does not inflate the entire intersection into a paved square")
	_check(_inside(Vector2(-211.9,-569.3)) and not _inside(Vector2(-210,-572)),"Cobre round terminal closes the approach before the portico")
	var worst_turn := 0.0
	var highway_points := 0
	for road in roads:
		if road.id not in ["desert_route_66","desert_west_highway","desert_digo_street"]: continue
		var points: PackedVector3Array = road.points
		for i in range(1,points.size()-1):
			worst_turn=maxf(worst_turn,(points[i]-points[i-1]).normalized().angle_to((points[i+1]-points[i]).normalized()))
		if road.id=="desert_route_66": highway_points=points.size()
	_check(worst_turn<=deg_to_rad(18),"road curves replace isolated ninety-degree vertices")
	_check(highway_points>12,"Route 66 contains sampled driving-radius curve")
	var graph := ROUTES.new()
	graph.configure(roads.filter(func(road: Dictionary): return road.traffic))
	var off_road := 0
	var samples := 0
	for pair in [
		[Vector3(342.5,0,-840),Vector3(-1000,0,-900)],
		[Vector3(-1000,0,-900),Vector3(342.5,0,-840)],
		[Vector3(-1010,0,-540),Vector3(-1060,0,-780)],
		[Vector3(-1060,0,-780),Vector3(-1010,0,-540)],
		[Vector3(-110,0,-570),Vector3(-370,0,-570)],
		[Vector3(342.5,0,-450),Vector3(290,0,-498)],
	]:
		var curve: Curve3D = graph.route_between(pair[0],pair[1])
		_check(curve!=null,"directed route exists "+str(pair))
		if curve==null: continue
		var distance := 0.0
		while distance<curve.get_baked_length():
			var position := curve.sample_baked(distance)
			var tangent := position.direction_to(curve.sample_baked(minf(distance+.5,curve.get_baked_length())))
			var normal := Vector2(-tangent.z,tangent.x)
			for offset in [-1.0,0.0,1.0]:
				samples+=1
				if not _inside(Vector2(position.x,position.z)+normal*offset): off_road+=1
			distance+=2
	_check(off_road==0,"real traffic paths plus two-metre vehicle width stay on asphalt: %d / %d outside"%[off_road,samples])
	var pole_conflicts: Array[String] = []
	var record_data := UTILITY.records()
	var pole_count := 0
	var services := 0
	for record in record_data:
		if record.kind=="utility_service": services+=1
		if record.kind!="utility_pole": continue
		pole_count+=1
		var point := Vector2(record.position.x,record.position.z)
		if not L.road_clear(point,.25): pole_conflicts.append(str(record.id)+" road")
		for building in L.buildings():
			var size := Vector2(building.size.x,building.size.z)
			var bounds := Rect2(Vector2(building.position.x,building.position.z)-size*.5,size).grow(.3)
			if bounds.has_point(point): pole_conflicts.append(str(record.id)+" "+str(building.id))
	_check(pole_conflicts.is_empty(),"all poles clear carriageways and buildings: "+str(pole_conflicts))
	_check(pole_count>40 and pole_count<200 and services==3,"bounded utility network serves all three original connections on shorter roads")
	var pole_positions: Dictionary = {}
	for record in record_data:
		if record.kind == "utility_pole": pole_positions[record.position] = true
	for record in record_data:
		if record.kind == "utility_span": _check(pole_positions.has(record.a) and pole_positions.has(record.b), "overhead span connects existing poles")
	# Compare actual streamed mesh triangles with the physical surface at curves/T.
	var region := Node3D.new(); root.add_child(region)
	var probes: Array[Vector2] = [Vector2(336,-534),Vector2(330.78,-888.28),Vector2(-1048.28,-551.72),Vector2(-114.69,-635.31),Vector2(302,-498),Vector2(-211.9,-569.3)]
	var cells: Dictionary = {}
	for point in probes:
		var cell := Vector2i(floori(point.x/96),floori(point.y/96))
		if cells.has(cell): continue
		cells[cell]=true
		geometry.build_chunk(region,Rect2(Vector2(cell)*96,Vector2.ONE*96))
	await physics_frame; await physics_frame
	for point in probes:
		var position := Vector3(point.x,0,point.y)
		var query := PhysicsRayQueryParameters3D.create(position+Vector3.UP,position-Vector3.UP,1)
		var hit := region.get_world_3d().direct_space_state.intersect_ray(query)
		# Unified paving deliberately keeps physical asphalt flush with the sand;
		# its 26mm rendered finish is not an extra physical step for the tires.
		var physical_height := 0.0 if BRIDGE_STYLE.enabled() else .018
		# Several chunks share this fixture parent; Godot may rename subsequent
		# same-named meshes to @MeshInstance3D@.... Surface ownership is semantic.
		var road_hit: bool=not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.get_meta("vehicle_surface","")=="hard" and hit.collider.get_parent() is MeshInstance3D and hit.collider.get_parent().get_meta("vehicle_surface","")=="hard"
		var observed_path := str(hit.collider.get_path()) if not hit.is_empty() else "none"
		var observed_height := str(hit.position.y) if not hit.is_empty() else "none"
		_check(road_hit and absf(float(hit.position.y)-physical_height)<.003,"authored asphalt collider supports tires at %s: collider=%s y=%s expected=%.3f"%[str(point),observed_path,observed_height,physical_height])
	for z in [-569.65,-570.165,-570.70]:
		var position := Vector3(-210,0,float(z))
		var hit := region.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP,position-Vector3.UP,1))
		var expected := lerpf(.024,.082,inverse_lerp(-569.6,-570.73,float(z)))
		_check(not hit.is_empty() and absf(float(hit.position.y)-expected)<.003,"Cobre walking ramp has the same rendered and physical height at "+str(z))
	region.free()
	print("DESERT_ROADS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"traffic_samples":samples,"poles":pole_count}))
	quit(0 if failures.is_empty() else 1)
