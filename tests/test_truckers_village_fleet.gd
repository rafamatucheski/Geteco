extends "res://tests/test_urban_operations.gd"
const FLEET := preload("res://gameplay/urban_v1/TruckersVillageFleet.gd")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	check(await _initialize_world(),"Main starts for village fleet")
	if not failures.is_empty(): quit(1); return
	world.player.controlled_automatically=true
	world.player.set_physics_process(false)
	world.player.teleport(Vector3(-330,.04,108))
	world.production.region.set_focus(world.player.position)
	var fleet=urban.village_fleet
	for i in 600:
		await physics_frame
		if fleet.cars.size()==FLEET.SPOTS.size(): break
	check(fleet.cars.size()==7,"All seven usable parked vehicles admitted")
	for id in fleet.cars:
		var car=fleet.cars[id]
		check(is_instance_valid(car) and not car.traffic and car.is_in_group("drivable"),id+" is usable parked fleet")
		check(car.global_position.y>-.2 and car.global_position.y<.5,id+" rests on village ground")
		var door: Vector3=car.driver_door_anchor(-1)
		world.player.teleport(door+Vector3.UP*.04)
		await physics_frame
		var option: Dictionary=world.driving._entry_option()
		check(option.get("car")==car,id+" has a clear actual boarding approach")
	var saved: Dictionary=fleet.snapshot()
	check(FLEET.validate_snapshot(saved),"Fleet state validates")
	var before: int=fleet.cars.size()
	check(fleet.restore_snapshot(saved),"Fleet restores its stable identities")
	world.player.teleport(Vector3(-330,.04,108))
	for i in 600:
		await physics_frame
		if fleet.cars.size()==before: break
	var ids:=[]
	for car in session.controller.vehicles:
		if is_instance_valid(car) and not car.is_queued_for_deletion() and car.vehicle_id.begins_with("tonico_parked_"): ids.append(car.vehicle_id)
	check(ids.size()==7,"Restore never duplicates parked cars")
	world.free()
	await process_frame
	print("VILLAGE_FLEET failures=",failures)
	quit(0 if failures.is_empty() else 1)
