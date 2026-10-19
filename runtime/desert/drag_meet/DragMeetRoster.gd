extends RefCounted
## Authored social islands shared by contact, crowd and sound placement.
const LEADERS := {
	"livia":Vector3(-968,0,-1291),"raul":Vector3(-1003,0,-1288),
	"jessica":Vector3(-915,0,-1260),"nadir":Vector3(-967,0,-1244),
}
const COLORS := {"livia":Color("be6038"),"raul":Color("65764c"),"jessica":Color("d8d0c6"),"nadir":Color("374f66")}
const CREW_OFFSETS := [Vector3(-3,0,0),Vector3(3,0,0),Vector3(-5,0,4.5),Vector3(-3.5,0,6),Vector3(3.5,0,6),Vector3(5,0,4.5)]
const TEAM_POINTS := {
	"livia":[Vector3(-971,0,-1290),Vector3(-970,0,-1287),Vector3(-966,0,-1287),Vector3(-964,0,-1290)],
	"raul":[Vector3(-1006,0,-1290),Vector3(-1005,0,-1293),Vector3(-1001,0,-1293),Vector3(-1000,0,-1290)],
	"jessica":[Vector3(-918,0,-1263),Vector3(-921,0,-1262),Vector3(-921,0,-1258),Vector3(-918,0,-1257)],
	"nadir":[Vector3(-970,0,-1243),Vector3(-969,0,-1240),Vector3(-965,0,-1240),Vector3(-963,0,-1243)],
}
const WALK_ENDS := {"livia":Vector3(-963,0,-1287),"raul":Vector3(-998,0,-1292),"jessica":Vector3(-918,0,-1254),"nadir":Vector3(-964,0,-1236)}
const VISITOR_POINTS := [Vector3(-1020,0,-1297),Vector3(-990,0,-1304),Vector3(-949,0,-1304),Vector3(-905,0,-1288),Vector3(-899,0,-1335.4),Vector3(-985,0,-1227)]

static func guests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for team in TEAM_POINTS:
		for index in 4:
			var point: Vector3 = TEAM_POINTS[team][index]
			result.append({"team":team,"point":point,"walk_end":WALK_ENDS[team] if index==3 else point,
				"focus":LEADERS[team],"coat":COLORS[team],"roamer":index==3})
	for index in VISITOR_POINTS.size():
		for side in [-1.0,1.0]:
			var point: Vector3 = VISITOR_POINTS[index]+Vector3(side*.9,0,0)
			result.append({"team":"visitor","point":point,"walk_end":point,
				"focus":VISITOR_POINTS[index]-Vector3(side*.9,0,0),
				"coat":[Color("ac8138"),Color("4c737b"),Color("886858"),Color("827386")][index%4],"roamer":false})
	return result
