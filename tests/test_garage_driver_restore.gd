extends SceneTree
var world
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)
func settle(frames := 5) -> void:
	for i in frames: await physics_frame
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"Main starts")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var original_car = world.driving.car
	check(world.production.no_save,"Never touch user save")
	for place in ["maciota","port_boss_garage"]:
		var center := Vector3(0,.08,1.2) if place == "maciota" else Vector3(0,.08,6)
		var saved := {"version":1,"port_status":"parked","alarm_remaining":-1.0,"police_called":false,"vehicles":{"garage_guest_1":{"archetype":"sport_coupe","region_id":"harbor","place_id":place,"position":[center.x,center.y,center.z],"yaw":0.0,"health":80.0,"paint":"ffffffff","was_driven":true}}}
		check(session.garage_rewards.restore_snapshot(saved),place+" saved car accepted")
		check(await session.enter_place(place,false),place+" safe entry before car materializes")
		await settle(12)
		var car = session.garage_rewards.cars.get("garage_guest_1")
		check(is_instance_valid(car),place+" saved car materializes")
		if not is_instance_valid(car): continue
		check(world.driving.occupied and world.driving.car == car,place+" driver restored through admitted door")
		check(world.camera.locked and world.camera.target == session.anchor,place+" interior camera preserved")
		check(not session.state.can_attack() and session.state.equipped_weapon == "fists",place+" attacks remain disabled")
		check(world.production.vehicle_position_clear(car,car.position,car.rotation.y),place+" full hull collision admission")
		session.garage_rewards.on_location_changed()
		await settle()
		var count := 0
		for vehicle in world.production.vehicles:
			if is_instance_valid(vehicle) and vehicle.vehicle_id == "garage_guest_1": count += 1
		check(count == 1,place+" repeated sync does not duplicate car")
		check(session.garage_rewards.snapshot().vehicles.garage_guest_1.was_driven,place+" seated save retains driver")
		if world.driving.occupied: check(world.driving.leave(),place+" physical disembark")
		car.health = 0
		check(not await session.restore_garage_driver(car),place+" destroyed car cannot board")
		check(await session.leave_place(),place+" physical exit")
		world.driving.car = original_car
		for vehicle in session.garage_rewards.cars.values():
			if is_instance_valid(vehicle): vehicle.queue_free()
		session.garage_rewards.cars.clear()
		await settle()
	world.queue_free()
	await settle(10)
	print("GARAGE_DRIVER_RESTORE ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
