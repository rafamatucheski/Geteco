extends SceneTree
var failures: Array[String]=[]
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures.append(label); push_error(label)
func settle(count := 4):
	for i in count: await physics_frame
func run():
	var world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var startup_deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec() < startup_deadline:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	var session=world.session
	check(session!=null and session.ready_for_play,"Production session ready")
	if not failures.is_empty(): quit(1); return
	check(world.production.no_save,"Fixture must isolate user save")
	var original=world.driving.car
	var route: Curve3D=world.production.traffic_routes.route_near(original.position)
	var offset: float=route.get_closest_offset(original.position)
	var point: Vector3=route.sample_baked(offset,true)
	var direction: Vector3=route.sample_baked(offset+1,true)-point
	original.collision_layer=0
	original.collision_mask=0
	original.set_physics_process(false)
	original.hide()
	original.remove_from_group("drivable")
	var car=world.production.spawn_vehicle("cobra_boss_ironback",point+Vector3.UP*.15,atan2(-direction.x,-direction.z))
	check(is_instance_valid(car),"Original Ironback admits with native hull")
	if not is_instance_valid(car): world.free(); quit(1); return
	car.vehicle_id="cobra_boss_ironback"
	car.set_meta("garage_reward",true)
	await settle()
	check(await session.restore_garage_driver(car),"Native driver enters via physically free side")
	check(await session.transfer_garage_vehicle("maciota",car,true),"Full original Ironback hull enters Maciota")
	check(session.state.place_id=="maciota" and not session.state.weapons_allowed(),"Vehicle transition preserves garage weapon restriction")
	check(world.camera.locked and world.driving.occupied,"Interior driving keeps fixed camera")
	check(await session.transfer_garage_vehicle("maciota",car,false),"Native vehicle exits through exterior admission pad")
	check(session.state.place_id.is_empty() and session.state.weapons_allowed(),"Exit releases weapons without losing inventory")
	check(await session.transfer_garage_vehicle("port_boss_garage",car,true),"Native vehicle enters boss garage through full hull pad")
	check(await session.transfer_garage_vehicle("port_boss_garage",car,false),"Native vehicle exits boss garage")
	world.free()
	await process_frame
	print("%s garage physical transfers: %d checks"%["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
