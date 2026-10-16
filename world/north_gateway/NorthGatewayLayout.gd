extends RefCounted
## World coordinates. This spur is scenery/player access, never an NPC traffic road.
const APPROACH := Vector3(364.55, 0.0, -254.0)
const TERMINAL := Vector3(342.5, 2.4, -361.5)
const WORK_POSITION := Vector3(342.5, 2.4, -282.8)
const DECK_HEIGHT := 2.4
const ROAD_HALF_WIDTH := 3.2
const GAP_SOUTH := -309.5
const GAP_NORTH := -322.5
const END_Z := -373.5
const GATE_WIDTH := 17.0
const GATE_HEIGHT := 2.25
const BOUNDS := Rect2(328.75, -374.25, 36.55, 126.0)
static var _points := PackedVector3Array()
static var _distances := PackedFloat32Array()
static var _shore_polygon := PackedVector2Array()
static var _shore_bounds := Rect2()

static func centerline() -> PackedVector3Array:
	_prepare()
	return _points.duplicate()

static func length() -> float:
	_prepare()
	return _distances[-1]

static func sample(distance: float) -> Vector3:
	_prepare()
	var d := clampf(distance, 0.0, _distances[-1])
	for i in range(1, _points.size()):
		if d <= _distances[i]:
			var weight := (d - _distances[i - 1]) / (_distances[i] - _distances[i - 1])
			return _points[i - 1].lerp(_points[i], weight)
	return _points[-1]

static func deck_half_width_at(distance: float) -> float:
	return deck_half_width(sample(distance))

static func walk_height_at(distance: float) -> float:
	# Um metro de concordância evita degrau junto à calçada urbana e à areia.
	return lerpf(0.008, 0.07, clampf(distance, 0.0, 1.0)) * clampf(length() - distance, 0.0, 1.0)

static func deck_half_width(point: Vector3) -> float:
	var z := point.z
	if z > -273.0: return 5.0
	if z > -281.0: return lerpf(5.0, 8.5, (-273.0 - z) / 8.0)
	if z >= -297.0: return 8.5
	if z > -303.0: return lerpf(8.5, 5.0, (-297.0 - z) / 6.0)
	if z > -343.0: return 5.0
	# The former dead-end turnaround is now a through road into the desert.
	return lerpf(5.0,6.2,clampf((-343.0-z)/30.5,0.0,1.0))

static func bounds() -> Rect2:
	return BOUNDS

static func gate_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, WORK_POSITION)

static func work_positions() -> Array[Vector3]:
	return [Vector3(336.7, 2.4, -286.8), Vector3(348.3, 2.4, -286.8),
		Vector3(336.7, 2.4, -292.0), Vector3(348.3, 2.4, -292.0)]

static func work_yaws() -> Array[float]:
	return [PI / 2.0, -PI / 2.0, 0.0, -PI / 2.0]

static func in_gap(point: Vector3) -> bool:
	return point.z < GAP_SOUTH and point.z > GAP_NORTH

static func shore_opening_polygon() -> PackedVector2Array:
	# Only the first shoreline crossing. Does not reserve the mountain/return route.
	# CoastalProtection must split its segments at this polygon before querying
	# their midpoints; otherwise an entire long coast segment could be removed.
	_prepare_shore()
	return _shore_polygon

static func _prepare_shore() -> void:
	if not _shore_polygon.is_empty(): return
	_prepare()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(12):
		var p := _points[i]
		var direction := _points[mini(i + 1, _points.size() - 1)] - _points[maxi(i - 1, 0)]
		var side := Vector2(-direction.z, direction.x).normalized() * 5.65
		left.append(Vector2(p.x, p.z) + side)
		right.append(Vector2(p.x, p.z) - side)
	for i in range(right.size() - 1, -1, -1): left.append(right[i])
	_shore_polygon = left
	_shore_bounds = Rect2(left[0], Vector2.ZERO)
	for point in left: _shore_bounds = _shore_bounds.expand(point)

static func reserves_shore_opening(point: Vector2) -> bool:
	_prepare_shore()
	if not _shore_bounds.has_point(point): return false
	return Geometry2D.is_point_in_polygon(point, _shore_polygon)

static func shore_opening_cuts(a: Vector2, b: Vector2) -> Array[float]:
	var result: Array[float] = []
	var delta := b - a
	if delta.length_squared() < 0.000001: return result
	_prepare_shore()
	if not Rect2(a, Vector2.ZERO).expand(b).grow(0.01).intersects(_shore_bounds): return result
	var polygon := _shore_polygon
	for i in polygon.size():
		var hit = Geometry2D.segment_intersects_segment(a, b, polygon[i], polygon[(i + 1) % polygon.size()])
		if hit is Vector2:
			result.append(clampf((hit - a).dot(delta) / delta.length_squared(), 0.0, 1.0))
	return result

static func _prepare() -> void:
	if not _points.is_empty(): return
	var a := Vector2(APPROACH.x, APPROACH.z)
	var b := Vector2(352.0, -254.0)
	var c := Vector2(342.5, -264.0)
	var d := Vector2(342.5, -280.0)
	var planar := PackedVector2Array()
	var planar_distance := PackedFloat32Array([0.0])
	for i in range(25):
		var t := float(i) / 24.0
		var u := 1.0 - t
		planar.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
		if i > 0: planar_distance.append(planar_distance[-1] + planar[i - 1].distance_to(planar[i]))
	# O modo A/B preserva o piso original elevado; o novo nasce no físico da rua.
	var start_height := 0.032 if OS.get_environment("GETECO_UNIFIED_BRIDGE") == "0" else APPROACH.y
	for i in planar.size():
		# Keep the junction and dry bank level; start the incline beyond the coast.
		var rise := smoothstep(9.0, planar_distance[-1], planar_distance[i])
		_points.append(Vector3(planar[i].x, lerpf(start_height, DECK_HEIGHT, rise), planar[i].y))
	# Include all width/gap boundaries exactly, then subdivide for curved guards.
	var stops: Array[float] = [-281.0, WORK_POSITION.z, -286.8, -292.0, -297.0,
		-303.0, GAP_SOUTH, GAP_NORTH, -330.0, -343.0, -352.0, TERMINAL.z, END_Z]
	for stop in stops:
		var previous := _points[-1]
		var count := maxi(1, ceili(absf(stop - previous.z) / 3.0))
		for i in range(1, count + 1):
			_points.append(Vector3(TERMINAL.x, DECK_HEIGHT, lerpf(previous.z, stop, float(i) / count)))
	_distances.append(0.0)
	for i in range(1, _points.size()):
		_distances.append(_distances[-1] + _points[i - 1].distance_to(_points[i]))
