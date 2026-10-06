extends RefCounted
## Additive, continuous relief south of the salt highway. One deterministic field
## feeds render vertices, streamed collision and the placement of grounded props.
## No scene nodes, noise resources, timers, random seed changes or per-frame work.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const BOUNDS := Rect2(-1140.0,-1936.0,580.0,368.0)
const GRID_STEP := 4.0
const ROAD_FLAT_MARGIN := 22.0
const ROAD_BLEND := 24.0
const EDGE_BLEND := 32.0
const PLATEAU_HEIGHT := 22.0
const PLATEAU_CENTER := Vector2(-1072.0,-1738.0)
const PLATEAU_RADIUS := Vector2(44.0,48.0)
const ACCESS_HALF_WIDTH := 8.0
const ACCESS_BLEND := 14.0
const ACCESS_START_T := .65
const ACCESS_CELL := 32.0
const ACCESS_WIDE_REACH := 64.0
const SAND_COLOR := Color("b9a079")
const ROCK_COLOR := Color("9f7d56")
const STRATUM_COLOR := Color("b99771")
static var _prepared := false
static var _road_guards: Array[Dictionary] = []
static var _building_guards: Array[Rect2] = []
static var _access: Array[Dictionary] = []
static var _access_buckets: Dictionary = {}
static var _access_wide_buckets: Dictionary = {}
static var _access_bounds := Rect2()

static func height_at(point: Vector2) -> float:
	# This is displacement, not absolute elevation: the caller adds its existing
	# bridge/ramp height. Exactly zero outside this patch and inside road reserves.
	if not BOUNDS.has_point(point): return 0.0
	_prepare()
	var boundary := minf(minf(point.x-BOUNDS.position.x,BOUNDS.end.x-point.x),minf(point.y-BOUNDS.position.y,BOUNDS.end.y-point.y))
	var mask := smoothstep(0.0,EDGE_BLEND,boundary)*_reservation_weight(point)
	if mask<=0.0: return 0.0
	var t := _depth(point.y)
	var across := absf(point.x-_center_x(t))
	var floor_width := _floor_half_width(t)
	# Broad shoulders, a lower ledge and a tall upper shelf describe sandstone
	# erosion. Ripples only modulate the authored mass; they never make spikes.
	var lower := smoothstep(floor_width+2.5,floor_width+12.0,across)
	var upper := smoothstep(floor_width+44.0,floor_width+88.0,across)
	var height := 17.0*lower+29.0*upper
	var ripple := sin(point.y*.032+point.x*.009)*1.7+sin(point.y*.061-point.x*.017)*.7
	height += ripple*upper
	var envelope := smoothstep(0.0,.18,t)*(1.0-smoothstep(.82,1.0,t))
	var outer := 1.0-smoothstep(180.0,276.0,across)
	height = (height+_floor_height(t))*envelope*outer
	# A real landing on the west flank, with room to stop/turn before returning.
	var ellipse := (point-PLATEAU_CENTER)/PLATEAU_RADIUS
	var landing := 1.0-smoothstep(.55,1.18,ellipse.length())
	height = lerpf(height,PLATEAU_HEIGHT,landing)
	# The ascending branch cuts a continuous 16 m driveable corridor into the
	# flank. Segment heights meet exactly; 1.5 m samples make bends sub-grid.
	var access := _access_sample(point)
	var ramp_weight := 1.0-smoothstep(ACCESS_HALF_WIDTH,ACCESS_HALF_WIDTH+ACCESS_BLEND,access.x)
	height = lerpf(height,access.y,ramp_weight)
	return maxf(height,0.0)*mask

static func normal_at(point: Vector2, sample_radius := 2.0) -> Vector3:
	# Absolute world coordinates keep neighboring render chunks' normals equal.
	var radius := maxf(sample_radius,.25)
	var dx := height_at(point+Vector2(radius,0))-height_at(point-Vector2(radius,0))
	var dz := height_at(point+Vector2(0,radius))-height_at(point-Vector2(0,radius))
	return Vector3(-dx,2.0*radius,-dz).normalized()

static func passage_clear(point: Vector2, radius := 0.0) -> bool:
	# TRUE means reserved passage: decoration must reject this footprint.
	# Include the approach from asphalt and enough margin for the whole vehicle.
	var margin := maxf(radius,0.0)
	if not BOUNDS.grow(40.0+margin).has_point(point): return false
	if point.y>BOUNDS.end.y:
		return absf(point.x+860.0)<=40.0+margin and point.y<=-1535.0+margin
	if point.y<BOUNDS.position.y-margin: return false
	var t := _depth(point.y)
	if absf(point.x-_center_x(t))<=_floor_half_width(t)+margin+4.0: return true
	_prepare()
	var reserve := ACCESS_HALF_WIDTH+margin+4.0
	if _access_sample(point,maxf(reserve,ACCESS_HALF_WIDTH+ACCESS_BLEND)).x<=reserve: return true
	return ((point-PLATEAU_CENTER)/(PLATEAU_RADIUS*.65+Vector2.ONE*margin)).length()<=1.0

static func clear(point: Vector2, radius := 0.0) -> bool:
	return not passage_clear(point,radius)

static func canyon_centerline(step := GRID_STEP) -> PackedVector3Array:
	# Includes the flat connection to the existing salt highway. This path is
	# guidance/validation data; it does not add an ambient traffic road or barrier.
	var result := PackedVector3Array()
	result.append(Vector3(-860.0,0.0,-1540.0))
	var count := maxi(2,ceili(BOUNDS.size.y/maxf(step,1.0)))
	for i in range(count+1):
		var t := float(i)/float(count)
		var p := Vector2(_center_x(t),lerpf(BOUNDS.end.y,BOUNDS.position.y,t))
		result.append(Vector3(p.x,height_at(p),p.y))
	return result

static func plateau_access(step := GRID_STEP) -> PackedVector3Array:
	var result := PackedVector3Array()
	# Bound sample length by the Bezier control polygon instead of assuming its
	# endpoint separation equals its length. Positions use the actual heightfield.
	var count := maxi(2,ceili(270.0/maxf(step,1.0)))
	for i in range(count+1):
		var p := _access_point(float(i)/float(count))
		result.append(Vector3(p.x,height_at(p),p.y))
	return result

static func _depth(z: float) -> float:
	return clampf((BOUNDS.end.y-z)/BOUNDS.size.y,0.0,1.0)

static func _center_x(t: float) -> float:
	var phase := t*t*(3.0-2.0*t)
	return -860.0+42.0*sin(TAU*phase)+12.0*sin(PI*t)

static func _floor_half_width(t: float) -> float:
	# Keep both flanks legible in the normal orthographic camera while retaining
	# two vehicles' passing room. Only the approach opens to an 80 m mouth.
	return 12.0+2.0*pow(sin(PI*t),2.0)+28.0*(1.0-smoothstep(0.0,.24,t))+6.0*smoothstep(.8,1.0,t)

static func _floor_height(t: float) -> float:
	return 3.5*pow(sin(PI*t),2.0)

static func _access_point(t: float) -> Vector2:
	var a := Vector2(_center_x(ACCESS_START_T),lerpf(BOUNDS.end.y,BOUNDS.position.y,ACCESS_START_T))
	var b := Vector2(-944.0,-1846.0)
	var c := Vector2(-1080.0,-1846.0)
	var u := 1.0-t
	return a*u*u*u+b*3.0*u*u*t+c*3.0*u*t*t+PLATEAU_CENTER*t*t*t

static func _access_sample(point: Vector2, reach := ACCESS_HALF_WIDTH+ACCESS_BLEND) -> Vector2:
	if not _access_bounds.grow(reach).has_point(point): return Vector2(INF,0.0)
	var distance_squared := INF
	var height := 0.0
	var segments: Array = _access
	var key := Vector2i(floori(point.x/ACCESS_CELL),floori(point.y/ACCESS_CELL))
	if reach<=ACCESS_HALF_WIDTH+ACCESS_BLEND:
		segments=_access_buckets.get(key,[])
	elif reach<=ACCESS_WIDE_REACH:
		segments=_access_wide_buckets.get(key,[])
	for segment in segments:
		var a: Vector2 = segment.a
		var delta: Vector2 = segment.delta
		var along := clampf((point-a).dot(delta)*float(segment.inverse_length_squared),0.0,1.0)
		var d := point.distance_squared_to(a+delta*along)
		if d>=distance_squared: continue
		distance_squared=d
		height=lerpf(float(segment.h0),float(segment.h1),along)
	return Vector2(sqrt(distance_squared),height)

static func _reservation_weight(point: Vector2) -> float:
	var nearest := INF
	for road in _road_guards:
		if not (road.bounds as Rect2).has_point(point): continue
		var a: Vector2 = road.a
		var b: Vector2 = road.b
		nearest=minf(nearest,Geometry2D.get_closest_point_to_segment(point,a,b).distance_to(point)-float(road.half_width))
	if nearest<=ROAD_FLAT_MARGIN: return 0.0
	for rect in _building_guards:
		if rect.has_point(point): return 0.0
		var closest := Vector2(clampf(point.x,rect.position.x,rect.end.x),clampf(point.y,rect.position.y,rect.end.y))
		nearest=minf(nearest,point.distance_to(closest)+ROAD_FLAT_MARGIN)
	return smoothstep(ROAD_FLAT_MARGIN,ROAD_FLAT_MARGIN+ROAD_BLEND,nearest)

static func _prepare() -> void:
	if _prepared: return
	_prepared=true
	# Filter authored roads once. Height queries never resample road curves or
	# scan city buildings; all five race lanes/accesses are included in this mask.
	for road in LAYOUT.roads():
		var points: PackedVector3Array = road.points
		var half_width: float = float(road.width)*.5
		for i in range(1,points.size()):
			var a := Vector2(points[i-1].x,points[i-1].z)
			var b := Vector2(points[i].x,points[i].z)
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(half_width+ROAD_FLAT_MARGIN+ROAD_BLEND)
			if bounds.intersects(BOUNDS,true): _road_guards.append({"a":a,"b":b,"half_width":half_width,"bounds":bounds})
	for building in LAYOUT.buildings():
		var at: Vector3 = building.position
		var size: Vector3 = building.size
		var rect := Rect2(Vector2(at.x-size.x*.5,at.z-size.z*.5),Vector2(size.x,size.z)).grow(22.0)
		if rect.grow(ROAD_BLEND).intersects(BOUNDS,true): _building_guards.append(rect)
	var last := _access_point(0.0)
	_access_bounds=Rect2(last,Vector2.ZERO)
	var first_height := _floor_height(ACCESS_START_T)
	var last_height := first_height
	for i in range(1,181):
		var t := float(i)/180.0
		var p := _access_point(t)
		var height := lerpf(first_height,PLATEAU_HEIGHT,smoothstep(0.0,1.0,t))
		var delta := p-last
		var segment := {"a":last,"delta":delta,"inverse_length_squared":1.0/maxf(delta.length_squared(),.000001),"h0":last_height,"h1":height}
		_access.append(segment)
		_access_bounds=_access_bounds.expand(p)
		_index_access(segment,Rect2(last,Vector2.ZERO).expand(p).grow(ACCESS_HALF_WIDTH+ACCESS_BLEND),_access_buckets)
		_index_access(segment,Rect2(last,Vector2.ZERO).expand(p).grow(ACCESS_WIDE_REACH),_access_wide_buckets)
		last=p
		last_height=height

static func _index_access(segment: Dictionary, cells: Rect2, buckets: Dictionary) -> void:
	for x in range(floori(cells.position.x/ACCESS_CELL),floori(cells.end.x/ACCESS_CELL)+1):
		for z in range(floori(cells.position.y/ACCESS_CELL),floori(cells.end.y/ACCESS_CELL)+1):
			var key := Vector2i(x,z)
			if not buckets.has(key): buckets[key]=[]
			buckets[key].append(segment)
