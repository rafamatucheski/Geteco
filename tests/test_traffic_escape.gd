extends SceneTree
const VEHICLE:=preload("res://scripts/Vehicle.gd")
const KIT:=preload("res://tests/dispatch/DispatchTestKit.gd")
const SIGNALS:=preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func route() -> Curve3D:
	var result:=Curve3D.new()
	result.add_point(Vector3(2.25,0,20))
	result.add_point(Vector3(2.25,0,-180))
	result.set_meta("traffic_open",true)
	return result
func car(scene: Node, point: Vector3, path: Curve3D=null) -> CharacterBody3D:
	var result:=VEHICLE.new()
	result.archetype="union_sedan"
	result.position=point
	scene.add_child(result)
	if path!=null:
		result.route=path
		result.route_distance=path.get_closest_offset(point)
		result.traffic=true
		result.set_meta("ambient_traffic",true)
	return result
func floor_scene() -> Node3D:
	var scene:=Node3D.new()
	root.add_child(scene)
	KIT.add_wall(scene,Vector3(0,-.5,-70),Vector3(40,1,250))
	return scene
func seconds(time: float) -> void:
	for frame in int(time*60): await physics_frame
func run() -> void:
	# A stopped police car inside the junction used to suppress all bypasses.
	SIGNALS.configure({"vertices":[Vector3(0,0,-40),Vector3(30,0,-40),Vector3(-30,0,-40),Vector3(0,0,-10),Vector3(0,0,-70)],"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}]}})
	var scene:=floor_scene()
	var police:=car(scene,Vector3(2.25,.08,-43))
	police.set_external_driver(true)
	police.set_meta("dispatch_unit",true)
	var queue:=[]
	for i in 3: queue.append(car(scene,Vector3(2.25,.08,-24+i*9),route()))
	var escaped:=false
	for frame in 2100:
		if "--queue-only" in OS.get_cmdline_user_args() and frame%180==0:
			for vehicle in queue:
				if is_instance_valid(vehicle): print("QUEUE_TRACE position=",vehicle.position," speed=",vehicle.speed," blocked=",vehicle.blocked," signal=",vehicle.junction_wait," wait=",vehicle.traffic_escape.wait if vehicle.traffic_escape!=null else 0," state=",vehicle.get_meta("traffic_escape_state","")," plan=",vehicle.get_meta("traffic_escape_plan_failure",""))
		for vehicle in queue:
			if is_instance_valid(vehicle) and vehicle.get_meta("traffic_escape_state","")=="escaping": escaped=true
		await physics_frame
	var cleared:=0
	for vehicle in queue:
		if not is_instance_valid(vehicle) or vehicle.position.z<-58: cleared+=1
	check(escaped,"civilian panic starts despite the blocked junction")
	check(cleared==3,"whole queue escapes or retires without waiting for police")
	check(police.position.distance_to(Vector3(2.25,.08,-43))<.3,"stationary police car need not move")
	scene.free()
	await physics_frame
	SIGNALS.configure(null)
	if "--queue-only" in OS.get_cmdline_user_args():
		print("TRAFFIC_ESCAPE_QUEUE failures=",failures)
		quit(0 if failures.is_empty() else 1)
		return
	# An ordinary red-light queue never enters panic/retirement.
	scene=floor_scene()
	var lead:=car(scene,Vector3(2.25,.08,-40),route())
	lead.set_physics_process(false)
	lead.speed=0
	lead.junction_wait=true
	lead.blocked=false
	var waiting:=car(scene,Vector3(2.25,.08,-31),route())
	await seconds(27)
	check(is_instance_valid(waiting) and (waiting.traffic_escape==null or not waiting.traffic_escape.active) and waiting.get_meta("traffic_escape_state","")=="","normal signal queue is preserved")
	scene.free()
	await physics_frame
	# Impossible geometry has a finite, visible retirement, without damage/death.
	scene=floor_scene()
	police=car(scene,Vector3(2.25,.08,-40))
	police.set_external_driver(true)
	police.set_meta("dispatch_unit",true)
	KIT.add_wall(scene,Vector3(-1.9,1,-55),Vector3(3.5,2,120))
	KIT.add_wall(scene,Vector3(6.1,1,-55),Vector3(3.5,2,120))
	waiting=car(scene,Vector3(2.25,.08,-32),route())
	await seconds(28)
	check(not is_instance_valid(waiting),"blocked civilian is removed after finite escape attempts")
	check(is_instance_valid(police) and police.health>0,"retirement preserves the stopped police car")
	scene.free()
	await physics_frame
	# Reproduce the service departure that could wait indefinitely in traffic.
	var kit:=KIT.build(self,KIT.single_road(),Vector3(2.25,.1,6))
	kit.controller.set_physics_process(false)
	var cruiser:=preload("res://gameplay/dispatch/DispatchVehicle.gd").new()
	cruiser.position=Vector3(2.25,.08,0)
	kit.scene.add_child(cruiser)
	cruiser.set_meta("dispatch_unit",true)
	var unit=kit.controller._make_unit("police",cruiser,8.0,2.0)
	unit.state="departing"
	unit.crew_remaining=0
	KIT.add_wall(kit.scene,Vector3(2.25,1,-8),Vector3(30,2,1))
	KIT.add_wall(kit.scene,Vector3(2.25,1,4),Vector3(30,2,1))
	var path:=Curve3D.new()
	path.add_point(Vector3(2.25,0,0))
	path.add_point(Vector3(2.25,0,-60))
	path.set_meta("traffic_open",true)
	unit.driver.set_route(path)
	for frame in 3000:
		unit.tick(1.0/60)
		await physics_frame
		if unit.finished: break
	check(unit.finished and unit.end_reason=="departure_escape_removed","departing police cannot retain an impossible blockage forever")
	KIT.teardown(kit)
	await physics_frame
	print("TRAFFIC_ESCAPE failures=",failures)
	quit(0 if failures.is_empty() else 1)
