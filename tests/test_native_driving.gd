extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var car: CharacterBody3D = world.driving.car
	var route: Curve3D = world.production.traffic_routes.route_near(car.position)
	var distance := route.get_closest_offset(car.position)
	var point := route.sample_baked(distance,true)
	var direction := route.sample_baked(distance+1,true)-point
	print("DRIVE_DIAGNOSTIC before=",car.position," point=",point," shape=",car.shape.shape.size," center=",car.shape.position)
	car.place(point+Vector3.UP*.12,atan2(-direction.x,-direction.z))
	print("DRIVE_DIAGNOSTIC placed=",car.position," valid=",world.production.vehicle_position_clear(car,car.position,car.rotation.y))
	for i in 3: await physics_frame
	print("DRIVE_DIAGNOSTIC after=",car.position," floor=",car.is_on_floor())
	var entered := false
	for side in [-1,1]:
		var approach := car.to_global(Vector3(side*(car.half_width+.65),.04,.15))
		print("DRIVE_DIAGNOSTIC door=",approach," clear=",world.session.position_clear(approach))
		world.player.teleport(approach)
		await physics_frame
		if world.driving.interact(): entered=true; break
	print("NATIVE_DRIVING_ENTRY ","PASS" if entered else "FAIL")
	world.free()
	await process_frame
	quit(0 if entered else 1)
