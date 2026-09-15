extends RefCounted
## Shared whole-body curved maneuver. Planning is sliced; execution checks live
## solids again. Pavement is taken from the road's own rendered ribbons.
const SLICE_USEC := 700
const FRAME_USEC := 2400
static var _frame := -1
static var _used := 0
static var _queue: Array[WeakRef] = []
var _queued := false
var _last_request := 0
var poses: Array[Transform2D] = []
var checked := 1
var cursor := 1
var pending := false
var valid := false
var surfaces: Array[PackedVector2Array] = []
var lane: Path2D
var hull: CollisionShape2D
var body: CharacterBody2D
var failure := ""

static func connection(start: Transform2D, end: Transform2D, radius: float) -> Array[Transform2D]:
	var length := start.origin.distance_to(end.origin)
	var handle := length*.55
	var a := start.origin+start.x*handle
	var b := end.origin-end.x*handle
	var result: Array[Transform2D] = [start]
	var count := maxi(20,ceili(length/2))
	for i in range(1,count+1):
		var t := float(i)/count
		var point := start.origin.bezier_interpolate(a,b,end.origin,t)
		var angle := start.origin.bezier_derivative(a,b,end.origin,t).angle()
		var ds := point.distance_to(result.back().origin)
		if ds < .001 or absf(angle_difference(result.back().get_rotation(),angle)) > ds/radius: return []
		result.append(Transform2D(angle,point))
	return result

static func lane_change(path: Path2D, offset: float, length: float, lateral: float, target: float, radius: float) -> Array[Transform2D]:
	var result: Array[Transform2D] = []
	var count := maxi(16,ceili((length+absf(target-lateral))/2))
	for i in range(count+1):
		var t := float(i)/count
		var point := _lane_point(path,offset,length,lateral,target,t)
		var tangent := _lane_point(path,offset,length,lateral,target,minf(1,t+.0001))-_lane_point(path,offset,length,lateral,target,maxf(0,t-.0001))
		var pose := Transform2D(tangent.angle(),point)
		if not result.is_empty():
			var ds := point.distance_to(result.back().origin)
			if ds < .001 or absf(angle_difference(result.back().get_rotation(),pose.get_rotation())) > ds/radius: return []
		result.append(pose)
	return result

static func _lane_point(path: Path2D, offset: float, length: float, lateral: float, target: float, t: float) -> Vector2:
	var pose := path.global_transform*path.curve.sample_baked_with_rotation(offset+length*t,true)
	var blend := t*t*t*(10+t*(-15+6*t))
	return pose.origin+pose.y*lerpf(lateral,target,blend)

func configure(actor: CharacterBody2D, path: Path2D, route: Array[Transform2D]) -> void:
	body = actor
	lane = path
	poses = route
	hull = actor.get_node_or_null("Collision") as CollisionShape2D
	if hull == null: hull = actor.get_node("CollisionShape2D")
	checked = 1
	cursor = 1
	pending = poses.size()>1
	valid = false
	surfaces.clear()
	var graph := path.get_parent().get_parent()
	if graph.has_method("get_signal_ground_surfaces"):
		var version: int = graph.get_routing_revision()
		var cache: Dictionary = graph.get_meta("emergency_paved_surface_cache",{})
		if cache.get("version",-1) != version:
			cache = {"version":version,"surfaces":graph.get_signal_ground_surfaces(graph.SIDEWALK_MARGIN*2)}
			graph.set_meta("emergency_paved_surface_cache",cache)
		var bounds := Rect2(poses[0].origin,Vector2.ZERO)
		for pose in poses: bounds = bounds.expand(pose.origin)
		bounds = bounds.grow(120)
		for polygon in cache.surfaces:
			var world: PackedVector2Array = graph.global_transform*polygon
			var region := Rect2(world[0],Vector2.ZERO)
			for vertex in world: region = region.expand(vertex)
			if bounds.intersects(region): surfaces.append(world)

func advance_plan() -> void:
	if not pending: return
	var frame := Engine.get_process_frames()
	if frame != _frame:
		_frame = frame
		_used = 0
	_last_request = Time.get_ticks_msec()
	if not _queued:
		_queue.append(weakref(self))
		_queued = true
	while not _queue.is_empty():
		var first = _queue[0].get_ref()
		if first != null and first.pending and _last_request-first._last_request<500: break
		_queue.pop_front()
		if first != null: first._queued = false
	if _used >= FRAME_USEC or _queue.is_empty() or _queue[0].get_ref() != self: return
	_queue.pop_front()
	_queued = false
	var started := Time.get_ticks_usec()
	while pending and Time.get_ticks_usec()-started < SLICE_USEC:
		if not clear(poses[checked-1],poses[checked]):
			pending = false
			break
		checked += 1
		if checked == poses.size():
			pending = false
			valid = true
	_used += Time.get_ticks_usec()-started

func clear(from: Transform2D, to: Transform2D) -> bool:
	var half := hull.shape.get_rect().size*.5
	if body.has_meta("emergency_visual_half_size"):
		half = half.max(body.get_meta("emergency_visual_half_size"))
	var turn := absf(angle_difference(from.get_rotation(),to.get_rotation()))
	var shape := RectangleShape2D.new()
	shape.size = half*2
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = from.interpolate_with(to,.5)*hull.transform
	query.transform.origin = (from*hull.transform).origin
	query.margin = 1.0+half.length()*sin(turn*.5)
	query.motion = (to*hull.transform).origin-query.transform.origin
	query.collision_mask = 15
	query.exclude = [body.get_rid()]
	var space := body.get_world_2d().direct_space_state
	var hits := space.intersect_shape(query,1)
	if not hits.is_empty():
		failure = "solid: "+str(hits[0].collider.get_path())
		return false
	if space.cast_motion(query)[0] < 1:
		failure = "swept solid"
		return false
	for corner in [-half,Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
		if not paved(to*hull.transform*corner):
			failure = "pavement: "+str(to*hull.transform*corner)
			return false
	return true

func paved(point: Vector2) -> bool:
	if not surfaces.is_empty():
		for polygon in surfaces:
			if Geometry2D.is_point_in_polygon(point,polygon): return true
		return false
	if not lane.has_meta("traffic_road_width"): return false
	var at := lane.curve.get_closest_offset(lane.to_local(point))
	var pose := lane.global_transform*lane.curve.sample_baked_with_rotation(at,true)
	var local := pose.affine_inverse()*point
	var offset := absf(float(lane.get_meta("traffic_lane_offset",0)))
	var width := float(lane.get_meta("traffic_road_width"))*.5
	var sidewalk := float(lane.get_meta("traffic_sidewalk_width",0))
	return local.y >= -width-offset-sidewalk+2 and local.y <= width-offset+sidewalk-2

func next(distance: float) -> Transform2D:
	var at := body.global_transform
	while cursor < poses.size() and at.origin.distance_to(poses[cursor].origin) < .05: cursor += 1
	if cursor >= poses.size(): return at
	var fraction := minf(1,distance/maxf(.001,at.origin.distance_to(poses[cursor].origin)))
	return at.interpolate_with(poses[cursor],fraction)

func finished() -> bool:
	return not poses.is_empty() and body.global_position.distance_to(poses.back().origin) < .1
