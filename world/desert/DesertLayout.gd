extends RefCounted
## Authored metre coordinates, north of the final-campaign bridge. No source-pixel offsets.
const ID := "desert"
const BOUNDS := Rect2(-1500, -1950, 1940, 1576.5)
const BRIDGE_END := Vector3(342.5, 2.4, -373.5)
const TOWN := Vector3(-180, 0, -900)
const DRAG_LENGTH := 800.0
const DRAG_LANE_SPACING := 4.0
const BANK := Vector3(-210, 0, -920)
const WORKSHOP := Vector3(-140, 0, -955)
const TRUCK_STOP := Vector3(285, 0, -750)
static var _clearance_roads: Array[Dictionary] = []

static func drag_start_point() -> Vector3: return Vector3(-1140, 0, -1280)
static func drag_direction() -> Vector3: return Vector3.RIGHT
static func drag_staging_point() -> Vector3: return Vector3(-1150, 0, -1264)
static func contains(point: Vector3) -> bool: return BOUNDS.has_point(Vector2(point.x, point.z))
static func surface_height(point: Vector2) -> float:
	return 2.4 * (1.0 - smoothstep(373.5, 445.0, -point.y))

static func roads() -> Array[Dictionary]:
	# Every T/crossing is an explicit vertex, avoiding near-miss graph connections.
	# The strip has its own access and is excluded from ambient traffic.
	return [
		_road("desert_route_66", _rounded([Vector2(342.5,-373.5),Vector2(342.5,-445),Vector2(342.5,-750),Vector2(342.5,-880),Vector2(342.5,-1540),Vector2(302.5,-1540)],40), 10.0),
		_road("desert_main_street", [Vector2(342.5,-880),Vector2(-110,-880),Vector2(-140,-880),Vector2(-210,-880),Vector2(-370,-880),Vector2(-1160,-880)], 9.0),
		_road("desert_west_highway", _rounded([Vector2(-1160,-880),Vector2(-1200,-880),Vector2(-1200,-1264),Vector2(-1200,-1540),Vector2(-1160,-1540)],40), 9.0),
		_road("desert_salt_highway", [Vector2(-1160,-1540),Vector2(302.5,-1540)], 10.0),
		_road("desert_digo_street", _rounded([Vector2(-110,-880),Vector2(-110,-980),Vector2(-370,-980),Vector2(-370,-880)],16), 7.0),
		_road("desert_bank_approach", [Vector2(-210,-880),Vector2(-210,-907)], 6.5),
		_road("desert_truck_stop_entry", _rounded([Vector2(342.5,-750),Vector2(320,-750),Vector2(306,-758),Vector2(290,-758)],6), 12.0),
		_road("desert_drag_access", _rounded([Vector2(-1200,-1264),Vector2(-1150,-1264),Vector2(-1140,-1264),Vector2(-1140,-1280)],6), 8.0, false),
		_road("desert_drag_strip", [Vector2(-1170,-1280),Vector2(-1140,-1280),Vector2(-340,-1280),Vector2(-150,-1280)], 10.0, false),
	]

static func _rounded(positions: Array, radius: float) -> Array:
	# Sample actual circular centre-lines. Render, collision, traffic and clearance
	# queries consume these same points, rather than drawing a curve over a corner.
	var result: Array = [positions[0]]
	for i in range(1,positions.size()-1):
		var at: Vector2 = positions[i]
		var before: Vector2 = (at-positions[i-1]).normalized()
		var after: Vector2 = (positions[i+1]-at).normalized()
		var turn := before.angle_to(after)
		if absf(turn)<.001:
			_push_distinct(result,at)
			continue
		var tangent := minf(radius*tan(absf(turn)*.5),minf(at.distance_to(positions[i-1]),at.distance_to(positions[i+1])))
		var actual_radius := tangent/tan(absf(turn)*.5)
		var entry := at-before*tangent
		var center := entry+Vector2(-before.y,before.x)*signf(turn)*actual_radius
		var start_angle := (entry-center).angle()
		var steps := maxi(4,ceili(absf(turn)*actual_radius/5.0))
		for k in range(steps+1):
			var angle := start_angle+turn*float(k)/steps
			_push_distinct(result,center+Vector2(cos(angle),sin(angle))*actual_radius)
	_push_distinct(result,positions[-1])
	return result

static func _push_distinct(points: Array, point: Vector2) -> void:
	if points.is_empty() or Vector2(points[-1]).distance_squared_to(point)>.000001: points.append(point)

static func _road(id: String, positions: Array, width: float, traffic := true) -> Dictionary:
	var points := PackedVector3Array()
	for p: Vector2 in positions: points.append(Vector3(p.x, surface_height(p), p.y))
	return {"id":id,"points":points,"width":width,"traffic":traffic,"region":"desert","surface":"asphalt","one_way":false}

static func road_clear(point: Vector2, radius := 0.0) -> bool:
	if _clearance_roads.is_empty(): _clearance_roads=roads()
	for road in _clearance_roads:
		var points: PackedVector3Array = road.points
		for i in range(1, points.size()):
			var a := Vector2(points[i-1].x,points[i-1].z)
			var b := Vector2(points[i].x,points[i].z)
			if Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point) < float(road.width)*.5+radius+3.0: return false
	return true

static func buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"id":"desert_bank","name":"Cobre","position":BANK,"size":Vector3(20,4.4,14),"kind":"bank","color":Color("c4a47a")},
		{"id":"desert_digo","name":"Digo","position":WORKSHOP,"size":Vector3(25,5.2,18),"kind":"workshop","color":Color("b59e7c")},
		{"id":"desert_fuel","name":"Miragem","position":TRUCK_STOP+Vector3(-13,0,-30),"size":Vector3(26,3.5,10),"kind":"fuel","color":Color("caba95")},
		{"id":"desert_motel","name":"Horizonte","position":Vector3(-330,0,-923),"size":Vector3(34,3.4,12),"kind":"motel","color":Color("ceaa87")},
		{"id":"desert_diner","name":"Solana","position":Vector3(-255,0,-856),"size":Vector3(19,3.7,11),"kind":"diner","color":Color("cab898")},
		{"id":"desert_market","name":"Alvorada","position":Vector3(-180,0,-856),"size":Vector3(17,3.6,11),"kind":"shop","color":Color("b88869")},
	]
	for i in 10:
		result.append({"id":"desert_home_%02d"%i,"name":"","position":Vector3(-300+(i%5)*29,0,-1030-floori(i/5.0)*37),"size":Vector3(14+(i%3)*2,3.0+(i%2)*.5,11),"kind":"home","color":[Color("b39172"),Color("d1b895"),Color("bda58d")][i%3]})
	return result

static func place_definitions() -> Array[Dictionary]:
	var bank := _place("desert_bank","Cobre",BANK,Vector2(20,14),"bank","res://world/desert/DesertBankInterior.gd",6.0,12.0)
	# A legally parked car can occupy every point on the narrow centre approach.
	# Authored side exits remain in the open forecourt, clear of columns/benches.
	bank.return_clearance_offsets=[Vector3(2.8,0,0),Vector3(-2.8,0,0)]
	return [
		bank,
		_place("desert_digo","Digo",WORKSHOP,Vector2(25,18),"desert_tuning","res://world/desert/DesertWorkshopInterior.gd",8.0,15.0),
	]

static func _place(id: String, title: String, exterior: Vector3, size: Vector2, service: String, model: String, spawn_z: float, camera: float) -> Dictionary:
	var entrance := exterior+Vector3(0,0,size.y*.5+1.4)
	return {"id":id,"original_name":title,"region":"desert","model":model,"source_id":model,"exterior_position":exterior,"entry_position":entrance,"return_position":entrance+Vector3(0,0,1),"spawn":Vector3(0,0,spawn_z),"exit":Vector3(0,0,size.y*.5-.5),"camera_target":Vector3(0,.7,0),"camera_size":camera,"size":size,"variant":0,"service":service,"reward":{},"rewards":[],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,"integration_status":"native_geometry_pending_validation"}
