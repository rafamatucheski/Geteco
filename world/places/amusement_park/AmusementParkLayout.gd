extends RefCounted
## Pedestrian fairground west of Harbor; northeast corner follows the rural road.
const ORIGIN := Vector3(-176,0,78)
const FOOTPRINT := Rect2(-216,42,80,72)
const APPROACH := Rect2(-136,91,11,6)
const ENTRY := ORIGIN + Vector3(40,.08,16)
const BOARDING := ORIGIN + Vector3(-7,.16,15)
const HAUNTED_CENTER := ORIGIN + Vector3(20,0,-12)
const HAUNTED_ENTRY := HAUNTED_CENTER + Vector3(0,.08,9.8)
const HAUNTED_ID := "harbor_haunted_house"
const HOUSE_SIZE := Vector2(18,15)
const HOUSE_SPAWN := Vector3(0,.04,5.4)
const HOUSE_EXIT := Vector3(0,.04,6.8)

static func enabled() -> bool: return not Engine.get_meta("amusement_park_baseline",false)

static func reserved(point: Vector2, margin := 0.0) -> bool:
	return enabled() and (FOOTPRINT.grow(margin).has_point(point) or APPROACH.grow(margin).has_point(point))

static func outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-40,-36),Vector2(22,-36),Vector2(40,-10),Vector2(40,36),Vector2(-40,36)])

static func coaster_curve() -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = .32
	var knots := PackedVector3Array([
		Vector3(-12,.38,14),Vector3(-12,.38,4),Vector3(-14,8,-13),
		Vector3(-25,15,-24),Vector3(-34,10,-13),Vector3(-32,2,0),
		Vector3(-25,5,8),Vector3(-23,9,-6),Vector3(-29,6,-15),
		Vector3(-33,1.2,10),Vector3(-28,.38,19),Vector3(-18,.38,20)])
	for i in knots.size():
		var tangent := (knots[(i+1)%knots.size()]-knots[posmod(i-1,knots.size())])*.15
		if i == 0: tangent = Vector3(0,0,-2.4)
		var incoming := -tangent
		var outgoing := tangent
		# Low station/return handles cannot pull the cubic rail under the ground.
		incoming.y = maxf(incoming.y,.38-knots[i].y)
		outgoing.y = maxf(outgoing.y,.38-knots[i].y)
		curve.add_point(knots[i],incoming,outgoing)
	curve.add_point(knots[0],curve.get_point_in(0),curve.get_point_out(0))
	return curve

static func house_route() -> PackedVector3Array:
	return PackedVector3Array([HOUSE_SPAWN,Vector3(-6.4,.04,4.5),Vector3(-6.4,.04,-5.2),Vector3(0,.04,-5.2),Vector3(6.4,.04,-5.2),Vector3(6.4,.04,4.5),HOUSE_SPAWN])
