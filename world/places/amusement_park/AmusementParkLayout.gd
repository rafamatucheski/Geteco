extends RefCounted
## Parque de diversões de pedestres a oeste do Harbor; o canto nordeste segue a estrada rural.
const ORIGIN := Vector3(-176,0,78)
const FOOTPRINT := Rect2(-216,42,80,72)
const APPROACH := Rect2(-136,91,11,6)
const ENTRY := ORIGIN + Vector3(40,.08,16)
const BOARDING := ORIGIN + Vector3(-7,.16,15)
const HAUNTED_CENTER := ORIGIN + Vector3(20,0,-12)
const HAUNTED_ENTRY := HAUNTED_CENTER + Vector3(0,.08,9.8)
const HAUNTED_ID := "harbor_haunted_house"
const HOUSE_SIZE := Vector2(18,35)
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
		Vector3(-12,.38,14),Vector3(-12,.38,4),Vector3(-12,7,-10),
		Vector3(-16,15,-23),Vector3(-24,16,-26),Vector3(-32,11,-21),
		Vector3(-34,2,-8),Vector3(-31,6,3),Vector3(-34,3,14),
		Vector3(-28,.8,20),Vector3(-19,.38,20)])
	# Um circuito de perímetro simples: sem retornos internos sobrepostos nem pilares
	# atravessando outro trilho. O último/primeiro trecho é reto e nivelado para atracar.
	for i in knots.size():
		var tangent := (knots[(i+1)%knots.size()]-knots[posmod(i-1,knots.size())])*.15
		if i == 0: tangent = Vector3(0,0,-2.4)
		if i == 1: tangent.x = 0
		if knots[i].y <= .38: tangent.y = 0
		var incoming := -tangent
		var outgoing := tangent
		# Alças baixas de estação/retorno não podem puxar o trilho cúbico para baixo do chão.
		incoming.y = maxf(incoming.y,.38-knots[i].y)
		outgoing.y = maxf(outgoing.y,.38-knots[i].y)
		curve.add_point(knots[i],incoming,outgoing)
	curve.add_point(knots[0],curve.get_point_in(0),curve.get_point_out(0))
	return curve

static func house_route() -> PackedVector3Array:
	return PackedVector3Array([HOUSE_SPAWN,Vector3(-6.4,.04,4.5),Vector3(-6.4,.04,-5.2),Vector3(0,.04,-5.2),Vector3(6.4,.04,-5.2),Vector3(6.4,.04,4.5),HOUSE_SPAWN])
