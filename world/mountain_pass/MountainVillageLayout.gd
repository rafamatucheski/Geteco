extends RefCounted
## Clareiras reservadas antes da floresta; população, acessos e estacionamento
## compartilham estas posições para não colocar troncos nas portas ou vagas.
const POCKETS := [Vector2(6580,-1900),Vector2(7110,-1510),Vector2(6880,-2760)]
const RESIDENTS := [
	[Vector2(5910,700),"LIA","trader",Color("648ea0")],
	[Vector2(6280,665),"RAUL","logger",Color("ae5c43")],
	[Vector2(7500,825),"BENTO","logger",Color("6b7950")],
	[Vector2(8360,795),"INÊS","trader",Color("896b9b")],
	[Vector2(7760,-95),"CAIO","ranger",Color("536c82")],
	[Vector2(6530,-1870),"HELENA","ranger",Color("ba7645")],
	[Vector2(6610,-1855),"OTTO","logger",Color("547b83")],
	[Vector2(7090,-1460),"RUTE","ranger",Color("8b4e55")],
	[Vector2(7160,-1450),"NOÉ","logger",Color("60816a")],
	[Vector2(6900,-2695),"ÍRIS","ranger",Color("5f719e")],
	[Vector2(5870,755),"DORA","visitor",Color("985b71")],
	[Vector2(6225,730),"FELIPE","truck_driver",Color("aa703e")],
	[Vector2(7540,885),"ANA","visitor",Color("527b88")],
	[Vector2(8405,850),"RUI","logger",Color("7c7750")],
	[Vector2(7820,-135),"MILA","visitor",Color("8c6d9c")],
	[Vector2(6650,-1885),"PEDRO","bus_driver",Color("456781")],
	[Vector2(6660,-1810),"LUÍSA","visitor",Color("ab6545")],
	[Vector2(7200,-1560),"BRUNO","truck_driver",Color("957338")],
	[Vector2(7140,-1420),"CECÍLIA","visitor",Color("688959")],
	[Vector2(6830,-2710),"SÉRGIO","visitor",Color("5c7177")],
]
const PARKING := [
	[Vector2(6470,-1910),"polar_van",PI*0.5],
	[Vector2(7215,-1600),"winter_suv_heavy",0.0],
	[Vector2(6970,-2780),"snow_plow_truck",PI*0.5],
]

static func pocket_apron(index: int) -> Rect2:
	return Rect2(POCKETS[index]-Vector2(170,135),Vector2(355,280)) if index == 1 else Rect2(POCKETS[index]-Vector2(180,120),Vector2(360,250))

static func winter_stop_access_curve(road_curve: Curve2D, index: int) -> Curve2D:
	var pocket: Vector2 = POCKETS[index]
	var access := Curve2D.new()
	access.bake_interval = 4.0
	if index != 1:
		access.add_point(road_curve.get_closest_point(pocket))
		access.add_point(pocket)
		return access
	# Join the turning road beside the FRONT courtyard, never under the shelter.
	var start := road_curve.get_closest_point(pocket+Vector2(-80,125))
	var end := pocket+Vector2(100,115)
	var direction := start.direction_to(end)
	var handle := start.distance_to(end)*0.32
	access.add_point(start,Vector2.ZERO,direction*handle)
	access.add_point(end,-Vector2.RIGHT*handle,Vector2.ZERO)
	return access

static func parking_bay(index: int) -> Rect2:
	var size := Vector2(116,60) if index == 1 else Vector2(62,136)
	return Rect2(PARKING[index][0]-size*0.5,size)
const ACCESS_PATHS := [
	[Vector2(5920,390),Vector2(5860,500),Vector2(5860,720),Vector2(5980,720)],
	[Vector2(7385,590),Vector2(7385,815),Vector2(7480,815)],
	[Vector2(8255,500),Vector2(8255,785),Vector2(8350,785)],
	[Vector2(5955,600),Vector2(5955,835),Vector2(6050,835)],
]

static func is_reserved(point: Vector2) -> bool:
	if preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd").is_reserved(point): return true
	for index in POCKETS.size():
		if pocket_apron(index).grow(18).has_point(point): return true
	if Rect2(6850, -2820, 540, 260).has_point(point): return true
	if Rect2(6940, -3020, 240, 240).has_point(point): return true
	if point.distance_to(Geometry2D.get_closest_point_to_segment(point,Vector2(7000,-1350),Vector2(7210,-1395))) < 62: return true
	for resident in RESIDENTS:
		if point.distance_to(resident[0]) < 75: return true
	for path in ACCESS_PATHS:
		for i in range(path.size()-1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,path[i],path[i+1])) < 38: return true
	return false
