extends RefCounted
## Small authored pull-offs, resolved against the effective (edited) geography.
## No road edges are added to the through-traffic graph and no map is rewritten.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const SLOT_LENGTH := 6.8
const DEPTH := 6.2
const SURFACE_Y := 0.045
const META := &"roadside_parking_sites"
# The terminal plaza is an authored composite: its benches, ramps and bus
# disembarking corridor have no individual NativeRegion obstacle records.
const HARBOR_RESERVED := [Rect2(91.0,59.0,30.0,16.5)]
const CANDIDATES := {
	"harbor": [
		["market", "market_street", Vector2(157,78), -1.0, 2],
		["dock", "dock_street", Vector2(145,137.5), 1.0, 2],
		["westgate", "westgate_drive", Vector2(25,78), 1.0, 1],
		["museum", "island_market_street", Vector2(374,78), -1.0, 2],
		["northbank", "northbank_neighborhood_street", Vector2(320,-22), 1.0, 1],
	],
	"mountain": [
		["forest", "mountain_pass", Vector2(650,-287), -1.0, 2],
		["woodland", "mountain_track_1", Vector2(747,-273), -1.0, 1],
		["lake", "mountain_track_2", Vector2(743,-333), 1.0, 1],
		["snow", "mountain_pass", Vector2(682,-454), -1.0, 2],
		["village", "mountain_track_5", Vector2(729,-424), -1.0, 1],
	]
}

static func prepare(region: Node) -> void:
	if region.get_meta(&"roadside_parking_registered",false): return
	for site in sites(region):
		region._record(site.edge,{"kind":"roadside_parking","site":site,"position":site.edge})
	region.set_meta(&"roadside_parking_registered",true)

static func sites(region: Node) -> Array[Dictionary]:
	if region.has_meta(META): return region.get_meta(META)
	var result: Array[Dictionary] = []
	for candidate in CANDIDATES.get(str(region.region_id), []):
		for road: Dictionary in region.roads:
			if str(road.id).trim_prefix("road/") != candidate[1]: continue
			# Nearby alternatives preserve the selected street while avoiding a tree
			# or an edited building. They are deterministic across streaming visits.
			for shift in [0.0, -4.0, 4.0, -8.0, 8.0]:
				var site := _resolve(region, road, candidate, shift)
				if site.is_empty() or not rejection_reason(region, site).is_empty(): continue
				result.append(site)
				break
			break
	region.set_meta(META, result)
	return result

static func _resolve(region: Node, road: Dictionary, row: Array, shift: float) -> Dictionary:
	var wanted := Vector3(row[2].x, 0, row[2].y)
	var nearest := Vector3.ZERO
	var tangent := Vector3.ZERO
	var best := INF
	var points: PackedVector3Array = road.points
	for index in range(points.size()-1):
		var delta := points[index+1]-points[index]
		if delta.length_squared() < .01: continue
		var projected := Geometry3D.get_closest_point_to_segment(wanted, points[index], points[index+1])
		var distance := wanted.distance_squared_to(projected)
		if distance >= best: continue
		best = distance
		nearest = projected
		tangent = delta.normalized()
	if best > 12.0*12.0: return {}
	nearest += tangent*shift
	# A positive side is the right-hand driving lane of the source polyline.
	var forward := tangent*float(row[3])
	var outward := forward.cross(Vector3.UP).normalized()
	var edge := nearest+outward*float(road.width)*.5
	var center := edge+outward*2.25
	center.y = SURFACE_Y
	var lane_width := float(road.width)/(2.0*maxi(1,int(road.get("lanes_per_direction",1))))
	var lane := edge-outward*lane_width*.5
	lane.y = SURFACE_Y
	var yaw := atan2(-forward.x, -forward.z)
	var slots: Array[Dictionary] = []
	for index in int(row[4]):
		var offset := forward*(float(index)-float(int(row[4])-1)*.5)*SLOT_LENGTH
		slots.append({"id":str(row[0])+"_%d"%index,"position":center+offset,"yaw":yaw,
			"lane_position":lane+offset,"approach":lane+offset-forward*9.0,
			"departure":lane+offset+forward*9.0,"explore_position":edge+offset+outward*5.25+Vector3.UP*SURFACE_Y,
			"forward":forward,"outward":outward})
	return {"id":str(region.region_id)+"_"+str(row[0]),"region":str(region.region_id),
		"road_id":str(road.id),"position":center,"forward":forward,"outward":outward,
		"yaw":yaw,"edge":edge,"half_length":SLOT_LENGTH*float(row[4])*.5+2.5,
		"depth":DEPTH,"road_width":float(road.width),"slots":slots,
		"road_points":points,
		"lane_position":lane,"approach":lane-forward*12.0,"departure":lane+forward*12.0,
		"explore_position":edge+outward*5.25+Vector3.UP*SURFACE_Y,
		"surface":"gravel" if region.region_id=="mountain" else "asphalt"}

static func contains(site: Dictionary, point: Vector3, margin := 0.0) -> bool:
	var delta: Vector3 = point-site.edge
	return absf(delta.dot(site.forward)) <= float(site.half_length)+margin \
		and delta.dot(site.outward) >= -.3-margin and delta.dot(site.outward) <= DEPTH+margin

static func is_reserved(point: Vector2, source_sites: Array, margin := .5) -> bool:
	for site: Dictionary in source_sites:
		if contains(site, Vector3(point.x,0,point.y), margin): return true
	return false

static func rejection_reason(region: Node, site: Dictionary) -> String:
	# Full footprint samples include the open mouth, all spaces and pedestrian
	# shoulder. No arbitrary roadside extension is allowed over a river or slope.
	var samples: Array[Vector3] = []
	for along in [-1.0,-.5,0.0,.5,1.0]:
		for across in [0.0,2.25,4.25,DEPTH]:
			samples.append(site.edge+site.forward*along*float(site.half_length)+site.outward*across)
	var bounds := Rect2(Vector2(samples[0].x,samples[0].z),Vector2.ZERO)
	for point in samples: bounds=bounds.expand(Vector2(point.x,point.z))
	if region.region_id=="harbor":
		for reserved: Rect2 in HARBOR_RESERVED:
			if reserved.grow(.6).intersects(bounds): return "terminal_access"
		for reserved: Rect2 in _transit_footprints(region):
			if reserved.grow(1.0).intersects(bounds): return "transit_station"
	# Shared connection geometry is built by ProductionWorld, outside regional
	# records. Its tunnel walls/portal and bridge railings must remain untouched.
	var crossing := Rect2(CONNECTION.HARBOR_ABUTMENT_X,CONNECTION.CENTER_Z-16.0,
		CONNECTION.TUNNEL_END_X+6.0-CONNECTION.HARBOR_ABUTMENT_X,32.0)
	if crossing.intersects(bounds): return "shared_connection"
	for point in samples:
		if region.terrain != null:
			if absf(region.terrain.surface_height_at(Vector2(point.x,point.z))) > .02: return "terrain"
		elif region.harbor_ocean != null:
			var on_land := false
			for polygon: PackedVector2Array in region.harbor_ocean.shores:
				if Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),polygon):
					on_land = true
					break
			if not on_land: return "water"
		for building: Dictionary in region.buildings:
			var local := (point-(building.position as Vector3)).rotated(Vector3.UP,-float(building.get("editor_rotation",0)))
			var size: Vector2 = building.size
			if absf(local.x)<size.x*.5+1.5 and absf(local.z)<size.y*.5+1.5: return "building"
		for entry: Dictionary in region.entries:
			var origin: Vector3 = entry.get("exterior_position",entry.get("position",Vector3.INF))
			if point.distance_to(origin) < 10.0: return "entrance"
	# Protect footprints even when their centre falls between the sample grid.
	for building: Dictionary in region.buildings:
		if contains(site,building.position,(building.size as Vector2).length()*.5+1.0): return "building"
	for lamp: Vector3 in _generated_lamps(region):
		if contains(site,lamp,1.0): return "streetlight"
	for records: Array in region.records.values():
		for record: Dictionary in records:
			if record.get("kind","") not in ["tree","container","editor_prop","editor_light","mountain_road_lamp","harbor_prop","mountain_place","original_facade"]: continue
			var point: Vector3 = record.get("position",record.get("data",{}).get("exterior_position",Vector3.INF))
			if not point.is_finite(): continue
			var padding := 1.6
			if record.kind in ["mountain_place","original_facade"]: padding = 10.0
			if record.kind == "container": padding = (record.size as Vector2).length()*.5+1.0
			if contains(site,point,padding): return str(record.kind)
	# Never install in a crossing, driveway, or a hairpin's neighbouring lane.
	for road: Dictionary in region.roads+region.walkways:
		if str(road.id) == str(site.road_id):
			for slot: Dictionary in site.slots:
				for point: Vector3 in [slot.position,slot.explore_position]:
					var separation := INF
					for index in range(road.points.size()-1):
						separation = minf(separation,Geometry3D.get_closest_point_to_segment(point,road.points[index],road.points[index+1]).distance_to(point))
					if separation < float(road.width)*.5+1.2: return "curve"
			continue
		for index in range(road.points.size()-1):
			for point in samples:
				var closest := Geometry3D.get_closest_point_to_segment(point,road.points[index],road.points[index+1])
				if closest.distance_to(point) < float(road.width)*.5+2.0: return "junction"
	return ""

static func _transit_footprints(region: Node) -> Array[Rect2]:
	const TRANSIT_META := &"roadside_parking_transit_footprints"
	if region.has_meta(TRANSIT_META): return region.get_meta(TRANSIT_META)
	var result: Array[Rect2] = []
	# Read the same effective edited definitions as the live station owner. No
	# meshes, lights, physics bodies or service controllers are instantiated.
	var transit = load("res://runtime/UrbanTransitPresentation.gd").new()
	transit.configure(null)
	for definition: Dictionary in transit.definitions:
		if definition.get("deleted",false) or int(definition.type)==2: continue
		# UrbanStationModel3D platform + ramp, and ticket office at Terminal Sul.
		# FLOOR_CALIBRATION cancels that model's /18 and floor projection to /16.
		var source := Rect2(-157,-106 if int(definition.type)==1 else -32,351,141 if int(definition.type)==1 else 67)
		var edit: Dictionary = definition.get("edit",{})
		var stretch: Array = edit.get("stretch",[1,1])
		var basis := Basis(Vector3.UP,deg_to_rad(float(edit.get("rotation",0))))*Basis.from_scale(Vector3(stretch[0],1,stretch[1]))
		var bounds := Rect2(Vector2.ZERO,Vector2.ZERO)
		var first := true
		for corner: Vector2 in [source.position,Vector2(source.end.x,source.position.y),source.end,Vector2(source.position.x,source.end.y)]:
			var rotated := corner.rotated(float(definition.angle))/16.0
			var world: Vector3 = definition.position+basis*Vector3(rotated.x,0,rotated.y)
			var point := Vector2(world.x,world.z)
			bounds = Rect2(point,Vector2.ZERO) if first else bounds.expand(point)
			first = false
		result.append(bounds)
	transit.free()
	region.set_meta(TRANSIT_META,result)
	return result

static func _generated_lamps(region: Node) -> Array[Vector3]:
	# Match the existing lamp placement; choose bays between lights instead of
	# deleting or moving the light that already serves the street.
	const LAMP_META := &"roadside_parking_lamp_points"
	if region.has_meta(LAMP_META): return region.get_meta(LAMP_META)
	var result: Array[Vector3] = []
	var mountain_side := 1.0
	var since_lamp := 25.0
	for road: Dictionary in region.roads:
		if str(road.get("surface","asphalt")) != "asphalt": continue
		var travelled := 0.0
		for index in range(road.points.size()-1):
			var a: Vector3 = road.points[index]
			var b: Vector3 = road.points[index+1]
			var length := a.distance_to(b)
			if length < .01: continue
			var forward := (b-a)/length
			var left := Vector3(forward.z,0,-forward.x)
			if region.region_id == "harbor":
				var at := fposmod(-travelled,18.0)
				while at < length:
					var side := 1.0 if int(round((travelled+at)/18.0))%2==0 else -1.0
					result.append(a+forward*at+left*side*(float(road.width)*.5+.45))
					at += 18.0
			else:
				var at := 0.0
				while at+(50.0-since_lamp)<length:
					at += 50.0-since_lamp
					since_lamp=0.0
					var center := a+forward*at
					if _in_crossing(a) or _in_crossing(b) or _in_crossing(center): continue
					var point := center+left*mountain_side*(float(road.width)*.5+2.3)
					if region.route_geometry.contains(point,.7): continue
					result.append(point)
					mountain_side = -mountain_side
				since_lamp += length-at
			travelled += length
	region.set_meta(LAMP_META,result)
	return result

static func _in_crossing(point: Vector3) -> bool:
	return point.x<CONNECTION.TUNNEL_END_X+4.0 and absf(point.z-CONNECTION.CENTER_Z)<16.0
