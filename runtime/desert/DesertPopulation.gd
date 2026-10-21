extends RefCounted
## Residents belong to places, never to arbitrary highway shoulders.
## One actor per slot; short authored routes stay in the inhabited forecourts.
static func slots() -> Array[Dictionary]:
	return [
		_spot("santa_lua",Vector3(-536,0,-497),"talk",Vector3.RIGHT),
		_spot("santa_lua",Vector3(-534.5,0,-497),"talk",Vector3.LEFT),
		_spot("santa_lua",Vector3(-521,0,-470),"talk",Vector3.RIGHT),
		_spot("santa_lua",Vector3(-519.5,0,-470),"talk",Vector3.LEFT),
		_walk("santa_lua",Vector3(-532,0,-495),Vector3(-532,0,-464)),
		_walk("santa_lua",Vector3(-524,0,-491),Vector3(-524,0,-463)),
		_spot("santa_lua",Vector3(-548,0,-513.8),"inspect",Vector3.FORWARD),
		_spot("truckstop",Vector3(309.6,0,-514.8),"talk",Vector3.RIGHT),
		_spot("truckstop",Vector3(311.1,0,-514.8),"talk",Vector3.LEFT),
		_walk("truckstop",Vector3(303,0,-522),Vector3(303,0,-511)),
		_spot("truckstop",Vector3(312,0,-478),"inspect",Vector3.RIGHT),
		_spot("town",Vector3(-182,0,-526),"talk",Vector3.RIGHT),
		_spot("town",Vector3(-180.5,0,-526),"talk",Vector3.LEFT),
		_walk("town",Vector3(-190,0,-529),Vector3(-168,0,-529)),
		_walk("town",Vector3(-259,0,-526),Vector3(-249,0,-526)),
	]

static func _spot(place: String, point: Vector3, activity: String, facing: Vector3) -> Dictionary:
	return {"place":place,"point":point,"activity":activity,"facing":facing,"route":PackedVector3Array([point,point])}

static func _walk(place: String, a: Vector3, b: Vector3) -> Dictionary:
	var slot:=_spot(place,a,"walk",(b-a).normalized())
	slot.route=PackedVector3Array([a,b])
	return slot

static func nearby_parameter(a: Vector3,b: Vector3,focus: Vector3,radius: float) -> float:
	var length:=a.distance_to(b)
	if length<.01: return 0.0
	var center:=clampf((focus-a).dot(b-a)/(length*length),0.0,1.0)
	return randf_range(maxf(.01,center-radius/length),minf(.99,center+radius/length))
