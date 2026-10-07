extends RefCounted
const STORY:=preload("res://runtime/desert/DesertStoryState.gd")
const X:=342.5
const JUNCTION:=Vector3(X,0,-1500)
const GATE:=Vector3(X,0,-1810)
const END:=Vector3(X,0,-1945)
const GROUP:="desert_north_pass_gate"
const LEFT_INNER:=330.0
const RIGHT_INNER:=355.0

static func enabled() -> bool:
	return preload("res://runtime/desert/DesertActivitiesPolicy.gd").enabled()

static func completed(world: Dictionary) -> bool:
	var state: Variant=world.get("desert_story",STORY.defaults())
	return STORY.valid(state) and bool(state.delivered)

static func restore_point(point: Vector3, world: Dictionary) -> Vector3:
	if not enabled() or completed(world): return point
	if point.x>=308.0 and point.x<=377.0 and point.z< -1786.0 and point.z>= -1950.0:
		return Vector3(348,0,-1778)
	return point

static func roads() -> Array[Dictionary]:
	if not enabled(): return []
	# -1500 is the actual tangent vertex of the existing rounded salt-highway
	# corner. -1540 alone would only look joined while leaving a graph gap.
	return [{"id":"desert_north_continuation","points":PackedVector3Array([JUNCTION,Vector3(X,0,-1540),Vector3(X,0,-1720),Vector3(X,0,-1780),GATE,Vector3(X,0,-1920),END]),"width":10.0,"traffic":false,"region":"desert","surface":"asphalt","one_way":false}]

static func reservation_clear(point: Vector2, radius:=0.0) -> bool:
	if not enabled(): return true
	return not Rect2(X-65,-1950,130,455).grow(radius).has_point(point)

static func workers() -> Array[Dictionary]:
	return [{"position":Vector3(332.5,0,-1791),"job":0,"yaw":PI},{"position":Vector3(352,0,-1786),"job":2,"yaw":PI*.8}]
