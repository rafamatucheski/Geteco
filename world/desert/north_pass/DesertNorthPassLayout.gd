extends RefCounted
const STORY:=preload("res://runtime/desert/DesertStoryState.gd")
const X:=342.5
const JUNCTION:=Vector3(X,0,-860)
const GATE:=Vector3(X,0,-1170)
const END:=Vector3(X,0,-1220)
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
	if point.x>=308.0 and point.x<=377.0 and point.z< -1146.0 and point.z>= -1230.0:
		return Vector3(348,0,-1138)
	return point

static func roads() -> Array[Dictionary]:
	if not enabled(): return []
	# -860 é o vértice tangente real da esquina compacta da
	# rodovia do sal. -900 sozinho deixaria um buraco no grafo.
	return [{"id":"desert_north_continuation","points":PackedVector3Array([JUNCTION,Vector3(X,0,-900),Vector3(X,0,-1080),Vector3(X,0,-1140),GATE,Vector3(X,0,-1205),END]),"width":10.0,"traffic":false,"region":"desert","surface":"asphalt","one_way":false}]

static func reservation_clear(point: Vector2, radius:=0.0) -> bool:
	if not enabled(): return true
	# Rejeição externa rápida, depois as áreas reais de estrada/obra. A antiga faixa
	# larga reservava chão vazio a oeste da estrada e cruzava as salinas.
	var margin := maxf(radius,0.0)
	if not Rect2(X-65,-1230,130,390).grow(margin+4.0).has_point(point): return true
	var road := Rect2(X-12,END.z-12,24,JUNCTION.z-END.z+24)
	if road.grow(margin).has_point(point): return false
	# Both 22 m geological walls, gate barrier, signposts and workers remain
	# protected, including their full physical footprint and a 4 m shoulder.
	var works := Rect2(LEFT_INNER-22,-1230,RIGHT_INNER-LEFT_INNER+44,155)
	return not works.grow(margin+4.0).has_point(point)

static func workers() -> Array[Dictionary]:
	return [{"position":Vector3(332.5,0,-1151),"job":0,"yaw":PI},{"position":Vector3(352,0,-1146),"job":2,"yaw":PI*.8}]
