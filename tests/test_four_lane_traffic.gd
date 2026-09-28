extends "res://tests/test_traffic_unstick.gd"

func run() -> void:
	JUNCTIONS.configure(null)
	var world := Node3D.new()
	root.add_child(world)
	floor_body(world)
	var route := Curve3D.new()
	for z in range(10,-300,-10): route.add_point(Vector3(5.25,0,z))
	route.set_meta("traffic_open",true)
	route.set_meta("lane_index",1)
	route.set_meta("lane_sections",[{"a":Vector3(0,0,10),"b":Vector3(0,0,-300),"width":14.0,"lanes":2}])
	var obstacle := car(world,Vector3(5.25,.1,-40),null)
	var follower := car(world,Vector3(5.25,.1,-25),route)
	var minimum_x := 5.25
	for frame in 1800:
		await physics_frame
		minimum_x=minf(minimum_x,follower.global_position.x)
	check(follower.global_position.z < -55,"Car passes stopped vehicle on four-lane avenue")
	check(minimum_x>0 and minimum_x<2.4,"Overtaking uses adjacent same-direction lane without crossing centre")
	check(absf(follower.global_position.x-5.25)<.5 and follower.bypass_side==0,"Returns to outer lane")
	follower.free(); obstacle.free()
	var behind := car(world,Vector3(1.75,.1,-20),null)
	var waiting := car(world,Vector3(5.25,.1,-25),route)
	waiting.set_physics_process(false)
	waiting.route_distance=35
	await physics_frame
	check(not waiting._try_bypass(),"Occupied adjacent lane behind blocks merging")
	behind.free(); waiting.free()
	var bus:=preload("res://runtime/transit/BiarticulatedBus.gd").new()
	world.add_child(bus)
	bus._apply_poses([Transform3D(Basis.IDENTITY,Vector3(5.25,.04,-80)),Transform3D(Basis.IDENTITY,Vector3(5.25,.04,-72.05)),Transform3D(Basis.IDENTITY,Vector3(5.25,.04,-64.6))],false)
	bus.service_state="exchange"; bus.set_active(true); bus.set_doors(1)
	var passing:=car(world,Vector3(5.25,.1,-51),route)
	var stayed_on_side:=true
	for frame in 2400:
		await physics_frame
		stayed_on_side=stayed_on_side and passing.global_position.x>0
	check(passing.global_position.z < -88,"Car recognizes the actual rear section and passes the stopped biarticulated bus")
	check(stayed_on_side and bus.global_position.is_equal_approx(Vector3(5.25,.04,-80)),"Bus stays at the platform and car keeps its direction of traffic")
	print("FOUR_LANE_TRAFFIC ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
