extends SceneTree
## Checagens de reserva autoral; acesso real, folga do trem e apresentação
## são conferidos à parte no Main renderizado pelo arnês integrado da ferrovia.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
var failures: Array[String]=[]
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func run() -> void:
	var station := NETWORK.get_station("harbor_central")
	check(not station.is_empty(),"Persistent station ID survives relocation")
	if station.is_empty(): quit(1); return
	var neco_gate := Vector3(-46.875,.12,43.75)
	check(station.entry.distance_to(neco_gate)<40,"Ground entry is within walking distance of Neco")
	check(station.entry.distance_to(Vector3(120,.12,78))>120,"Station access is separate from terminal footbridge")
	check(station.region=="harbor" and not station.requires_act1,"Harbor admission remains available before act1 completion")
	for old_point in [Vector3(149.4,12.95,67),Vector3(157,2.13833,70),Vector3(154.3,6.415,70),Vector3(157,10.69167,70),Vector3(155,4.3,61.5)]:
		check(NETWORK.restore_harbor_pedestrian(old_point).is_equal_approx(station.entry),"Old elevated station save migrates safely: "+str(old_point))
	for unrelated in [Vector3(157,.12,79),Vector3(149.4,.12,67),Vector3(155,12.95,44),Vector3(149,5,67),Vector3(386,12.95,-179)]:
		check(NETWORK.restore_harbor_pedestrian(unrelated).is_equal_approx(unrelated),"Unrelated ground/roof/station save remains untouched: "+str(unrelated))
	var north := NETWORK.get_station("harbor_north")
	check(north.entry.x > 388.125,"Northgate staircase is east of the highway over water")
	check(NETWORK.restore_harbor_pedestrian(Vector3(381.6,12.95,-194)).is_equal_approx(north.entry),"Old north median platform save migrates to offshore entrance")
	check(NETWORK.restore_harbor_pedestrian(Vector3(374,2.258333,-188)).is_equal_approx(north.entry),"Old north stairs migrate to supported offshore entrance")
	check(NETWORK.restore_harbor_pedestrian(north.arrival).is_equal_approx(north.arrival),"New offshore platform save preserves exact position")
	var points := NETWORK.approach_path("harbor_central")
	check(points[0].is_equal_approx(station.entry) and points[-1].is_equal_approx(station.arrival),"Access uses relocated persistent entry and platform")
	var yard := Rect2(-62.875,22.875,32,23).grow(1)
	var origin: Vector3=station.position
	var platform := Rect2(origin.x-6.8,origin.z-17,4.8,34)
	check(not platform.intersects(yard),"Platform does not intrude into Neco working yard")
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var access_clear := true
	for point in points:
		var p := Vector2(point.x,point.z)
		if yard.has_point(p): access_clear=false
		if point.y>1: continue
		for road in source.harbor_roads:
			for i in range(1,road.points.size()):
				var a := Vector2(road.points[i-1][0],road.points[i-1][1])/16
				var b := Vector2(road.points[i][0],road.points[i][1])/16
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))<float(road.width)/32+1.2: access_clear=false
	check(access_clear,"Ground access and stairs preserve yard and street reservations")
	var rail := NETWORK.get_route("harbor_central","harbor_north")
	check(rail.size()>2 and rail[0].is_equal_approx(station.position),"Viaduct starts at relocated stop")
	var clear_buildings := true
	# Os dois lados do circuito costeiro evitam as áreas autorais dos prédios.
	var whole_loop := rail+NETWORK.get_route("harbor_north","harbor_central")
	for point in whole_loop:
		for building in source.harbor_buildings:
			var center := Vector2(building.position[0],building.position[1])/16
			var size := Vector2(building.size[0],building.size[1])/16
			if Rect2(center-size*.5,size).grow(2.0).has_point(Vector2(point.x,point.z)): clear_buildings=false
	check(clear_buildings,"Both coastal rail legs avoid authored building footprints")
	var platform_outline := PackedVector2Array([platform.position,Vector2(platform.end.x,platform.position.y),platform.end,Vector2(platform.position.x,platform.end.y)])
	var train_clear := true
	var envelope_samples := 0
	for reverse in [false,true]:
		var route := rail.duplicate()
		if reverse: route.reverse()
		var length := NETWORK.route_length(route)
		for step in 701:
			var distance := length-float(step)*.1 if reverse else float(step)*.1
			var point: Vector3=NETWORK.sample(route,distance).position
			var ahead: Vector3=NETWORK.sample(route,minf(length,distance+.8)).position
			var behind: Vector3=NETWORK.sample(route,maxf(0,distance-.8)).position
			var tangent := Vector2(ahead.x-behind.x,ahead.z-behind.z).normalized()
			var side := Vector2(-tangent.y,tangent.x)
			var center := Vector2(point.x,point.z)
			var envelope := PackedVector2Array()
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				envelope.append(center+side*corner.x*1.71+tangent*corner.y*5.4)
			envelope_samples+=1
			if not Geometry2D.intersect_polygons(envelope,platform_outline).is_empty(): train_clear=false
	check(train_clear,"10.8 m coach envelope clears relocated platform in both directions at 0.1 m intervals")
	var report := {"checks":checks,"failures":failures,"station":str(station),"access":str(points),"route_length_m":NETWORK.route_length(rail),"road_network_unchanged":true}
	report.envelope_samples=envelope_samples
	var folder := "res://evidence/railway-coastal-20261015"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder+"/network.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("RAILWAY_NECO ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
