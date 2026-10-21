extends RefCounted
## Authored social islands shared by contact, crowd and sound placement.
const LEADERS := {
	"livia":Vector3(-828,0,-771),"raul":Vector3(-863,0,-768),
	"jessica":Vector3(-775,0,-740),"nadir":Vector3(-827,0,-724),
}
const COLORS := {"livia":Color("be6038"),"raul":Color("65764c"),"jessica":Color("d8d0c6"),"nadir":Color("374f66")}
const CREW_OFFSETS := [Vector3(-3,0,0),Vector3(3,0,0),Vector3(-5,0,4.5),Vector3(-3.5,0,6),Vector3(3.5,0,6),Vector3(5,0,4.5)]
const TEAM_POINTS := {
	"livia":[Vector3(-831,0,-770),Vector3(-830,0,-767),Vector3(-826,0,-767),Vector3(-824,0,-770)],
	"raul":[Vector3(-866,0,-770),Vector3(-865,0,-773),Vector3(-861,0,-773),Vector3(-860,0,-770)],
	"jessica":[Vector3(-778,0,-743),Vector3(-781,0,-742),Vector3(-781,0,-738),Vector3(-778,0,-737)],
	"nadir":[Vector3(-830,0,-723),Vector3(-829,0,-720),Vector3(-825,0,-720),Vector3(-823,0,-723)],
}
const WALK_ENDS := {"livia":Vector3(-823,0,-767),"raul":Vector3(-858,0,-772),"jessica":Vector3(-778,0,-734),"nadir":Vector3(-824,0,-716)}
const VISITOR_POINTS := [Vector3(-880,0,-777),Vector3(-850,0,-784),Vector3(-809,0,-784),Vector3(-765,0,-768),Vector3(-759,0,-815.4),Vector3(-845,0,-707)]

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
