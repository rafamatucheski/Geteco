extends RefCounted
## Authored winter service loop. Original mountain-map coordinates; no civilian traffic.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const WIDTH := 5.8
const SHOULDER := 4.0
const TIME_LIMIT := 110.0
const VEHICLE := "desert_jeep_4x4"
const LOAN_ID := "mountain_trail_jeep_01"
const CONTROLS := [Vector2(5970,-2030),Vector2(5610,-2030),Vector2(5260,-2150),
	Vector2(4880,-2150),Vector2(4500,-2280),Vector2(4110,-2290),Vector2(3900,-2530),
	Vector2(4180,-2790),Vector2(4610,-2890),Vector2(5050,-2750),Vector2(5480,-2600),
	Vector2(5760,-2370),Vector2(5970,-2210),Vector2(5970,-2030)]
static var _points := PackedVector3Array()
static var _distances := PackedFloat32Array()
static var _bounds := Rect2()

static func _prepare() -> void:
	if not _points.is_empty(): return
	var curve := Curve2D.new()
	curve.bake_interval = 8.0
	for i in CONTROLS.size():
		var tangent := Vector2.ZERO
		if i > 0 and i < CONTROLS.size()-1:
			tangent = (CONTROLS[i+1]-CONTROLS[i-1]).normalized()*minf(CONTROLS[i].distance_to(CONTROLS[i-1]),CONTROLS[i].distance_to(CONTROLS[i+1]))*.30
		curve.add_point(CONTROLS[i],-tangent,tangent)
	for distance in range(0,ceili(curve.get_baked_length()),32):
		_points.append(CATALOG._at(curve.sample_baked(distance,true),"mountain"))
	_points.append(CATALOG._at(CONTROLS[-1],"mountain"))
	_bounds=Rect2(Vector2(_points[0].x,_points[0].z),Vector2.ZERO)
	for point in _points: _bounds=_bounds.expand(Vector2(point.x,point.z))
	_distances.append(0.0)
	for i in range(1,_points.size()):
		_distances.append(_distances[-1]+_points[i-1].distance_to(_points[i]))

static func centerline() -> PackedVector3Array:
	_prepare()
	return _points.duplicate()

static func length() -> float:
	_prepare()
	return _distances[-1]

static func start() -> Vector3:
	return CATALOG._at(CONTROLS[0],"mountain")

static func parking() -> Vector3:
	return start()+Vector3(5.5,.12,0)

static func parking_yaw() -> float:
	return PI*.5

static func sample(distance: float) -> Dictionary:
	_prepare()
	var s := clampf(distance,0.0,_distances[-1])
	for i in range(1,_points.size()):
		if _distances[i] < s: continue
		var part := inverse_lerp(_distances[i-1],_distances[i],s)
		var point := _points[i-1].lerp(_points[i],part)
		point.y = rise(s)
		return {"position":point,"forward":_points[i-1].direction_to(_points[i]),"distance":s}
	return {"position":_points[-1],"forward":_points[-2].direction_to(_points[-1]),"distance":s}

static func rise(distance: float) -> float:
	# Two shallow crests: approach/departure slope stays below thirteen percent.
	for interval in [[70.0,108.0,1.4],[205.0,251.0,1.7]]:
		if distance > interval[0] and distance < interval[1]:
			return pow(sin(PI*inverse_lerp(interval[0],interval[1],distance)),2)*interval[2]
	return 0.0

static func checkpoints() -> Array[Dictionary]:
	var gates: Array[Dictionary] = []
	# Final gate precedes the paddock, leaving twelve metres for braking and exit.
	var finish := length()-12.0
	for distance in range(28,int(finish-12.0),28): gates.append(sample(float(distance)))
	gates.append(sample(finish))
	return gates

static func paths(main: PackedVector3Array) -> Array[Dictionary]:
	var access := PackedVector3Array([CATALOG._at(Vector2(6250,-2050),"mountain"),
		CATALOG._at(Vector2(6120,-2050),"mountain"),start()+Vector3(5.5,0,0),start()])
	var best := INF
	var requested := access[0]
	for i in range(1,main.size()):
		var closest := Geometry3D.get_closest_point_to_segment(requested,main[i-1],main[i])
		var distance := requested.distance_squared_to(closest)
		if distance<best:
			best=distance
			access[0]=closest
	return [{"id":"mountain_jeep_access","width":8.0,"surface":"earth","points":access},
		{"id":"mountain_jeep_loop","width":WIDTH,"surface":"earth","points":centerline()}]

static func corridor_distance(point: Vector3) -> float:
	_prepare()
	var closest := INF
	var flat := Vector2(point.x,point.z)
	for i in range(1,_points.size()):
		var nearest := Geometry2D.get_closest_point_to_segment(flat,Vector2(_points[i-1].x,_points[i-1].z),Vector2(_points[i].x,_points[i].z))
		closest = minf(closest,flat.distance_to(nearest))
	return closest

static func is_reserved(point: Vector2, radius: float = 0.0) -> bool:
	_prepare()
	var reach := WIDTH*.5+SHOULDER+maxf(0.0,radius)
	return _bounds.grow(reach).has_point(point) and corridor_distance(Vector3(point.x,0,point.y)) <= reach

static func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var gates := checkpoints()
	for i in gates.size():
		result.append({"kind":"mountain_jeep_scenery","variant":"gate","position":gates[i].position,
			"forward":gates[i].forward,"finish":i==gates.size()-1})
	result.append({"kind":"mountain_jeep_scenery","variant":"start","position":start(),"forward":Vector3.LEFT})
	for interval in [[70.0,108.0],[205.0,251.0]]:
		result.append({"kind":"mountain_jeep_scenery","variant":"crest","position":sample((interval[0]+interval[1])*.5).position,"from":interval[0],"to":interval[1]})
	return result
