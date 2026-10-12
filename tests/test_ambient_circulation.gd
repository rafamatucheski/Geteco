extends SceneTree
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const JOURNEY := preload("res://gameplay/AmbientJourney.gd")
const GRAPH := preload("res://gameplay/NativeTrafficRoutes.gd")
var failures: Array[String] = []
class Production extends RefCounted:
	const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
	var vehicles: Array = []
	var ambient_traffic_routes
	func _is_ambient_traffic(car) -> bool: return is_instance_valid(car) and car.get_meta("ambient_traffic",false)
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene,Vector3(0,-.5,0),Vector3(100,1,180))
	var graph := GRAPH.new()
	graph.configure([{"id":"terminal","width":9.0,"points":PackedVector3Array([Vector3(0,0,60),Vector3(0,0,-60)])}])
	var car := VEHICLE.new()
	car.archetype="union_sedan"
	car.position=Vector3(2.25,.08,-25)
	scene.add_child(car)
	car.route=graph.route_near(car.position,0,Vector3.FORWARD)
	car.route_distance=car.route.get_closest_offset(car.position)
	car.traffic=true
	car.set_meta("ambient_traffic",true)
	var production := Production.new()
	production.vehicles=[car]
	production.ambient_traffic_routes=graph
	var journey := JOURNEY.new()
	var turned := false
	var returning := false
	var max_x := 0.0
	for frame in 1800:
		if frame%15==0: journey.update(production)
		turned = turned or car.has_meta("ambient_next_route")
		returning = returning or (turned and car.global_basis.z.z<-.8 and car.position.z>-30)
		max_x=maxf(max_x,absf(car.position.x))
		await physics_frame
		if returning: break
	check(turned,"open trip creates a physical turnaround")
	check(returning,"vehicle leaves terminal on opposite lane without teleport")
	check(max_x<3.5,"turn remains inside the nine metre road")
	check(car.health>0,"turn preserves vehicle")
	scene.free()
	await physics_frame
	var kit := KIT.build(self,[{"id":"road","width":9.0,"points":PackedVector3Array([Vector3(0,0,90),Vector3(0,0,-90)])}],Vector3(20,.1,-12))
	var service := preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
	service.position=Vector3(2.25,.08,0)
	kit.scene.add_child(service)
	var unit := preload("res://gameplay/dispatch/DispatchUnit.gd").new()
	unit.vehicle=service
	unit.controller=kit.controller
	unit.driver=preload("res://gameplay/dispatch/DispatchDriver.gd").new()
	unit.driver.setup(service,7.0,2.0)
	unit.driver.set_route(kit.routes.route_near(service.position))
	var ready := false
	for frame in 1200:
		ready=unit.stop_planner.tick(unit,Vector3(2.25,0,-12),1.0/60)
		unit.driver.tick(1.0/60)
		await physics_frame
		if ready: break
	check(ready,"service reaches a planned stop")
	check(service.position.x>4.5,"available shoulder is used instead of traffic lane")
	check(not kit.controller.exit_point_at(service,service.position,service.rotation.y).is_empty(),"planned stop retains a safe crew exit")
	var road_route: Curve3D=kit.routes.route_near(service.position,0,-service.global_basis.z)
	var departure: Curve3D=unit.stop_planner.departure_curve(service,road_route)
	check(departure!=null,"service can merge physically from shoulder")
	if departure!=null:
		unit.driver.set_route(departure)
		unit.driver.hold(false)
		for frame in 600:
			unit.driver.tick(1.0/60)
			await physics_frame
		check(absf(service.position.x-2.25)<.8 and service.speed>1,"service rejoins its lane and drives away")
	unit.driver.discard_overtaking("test_end")
	kit.scene.free()
	await physics_frame
	print("AMBIENT_CIRCULATION failures=",failures)
	quit(0 if failures.is_empty() else 1)
