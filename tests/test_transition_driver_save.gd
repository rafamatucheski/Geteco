extends "res://tests/test_transition_modal_save.gd"
## Blocker is a fixed map solid installed before the loaded Main enters the tree.
## This isolates occupied saved-pose behavior without mocking admission queries.
var saved_car_point := Vector3.ZERO
var add_load_blocker := false
func build(saved := false) -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	if saved:
		world.set_meta("menu_save_path",save_path)
		if add_load_blocker:
			var blocker := StaticBody3D.new()
			blocker.name = "FixtureSolidAtSavedCar"
			blocker.collision_layer = 1
			blocker.collision_mask = 0
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.0,1.8,2.0)
			shape.shape = box
			blocker.add_child(shape)
			world.add_child(blocker)
			blocker.position = saved_car_point+Vector3.UP*.9
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"native Main ready")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="): folder = arg.trim_prefix("--out-dir=")
	add_load_blocker = "--blocked-car" in OS.get_cmdline_user_args()
	if folder.is_empty(): quit(2); return
	save_path = "user://tests/driver-position-%d/progress.json" % Time.get_ticks_usec()
	await build()
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var car = world.driving.car
	var origin: Vector3 = world.player.position
	var pose := Vector3.INF
	for offset in [Vector3(40,0,0),Vector3(-40,0,0),Vector3(0,0,40),Vector3(0,0,-40)]:
		var point: Vector3 = world.production.nearest_road(origin+offset)+Vector3.UP*.12
		world.production.region.prepare_collision_at(point)
		await physics_frame
		if point.distance_to(origin)>20 and world.production.vehicle_position_clear(car,point,0): pose = point; break
	check(pose.is_finite(),"free saved car pose away from checkpoint")
	if not pose.is_finite(): quit(1); return
	car.place(pose,0)
	world.player.teleport(car.to_global(Vector3(car.half_width+.65,.05,.15)))
	for i in 6: await physics_frame
	check(await session.restore_garage_driver(car),"productive boarding completed before save")
	if not world.driving.occupied: world.free(); quit(1); return
	saved_car_point = car.global_position
	world.production.store.path = save_path
	world.production.no_save = false
	check(session.save_game(true),"seated save published to isolated store")
	var snapshot: Dictionary = preload("res://runtime/SaveStore.gd").read_valid(save_path)
	check(snapshot.get("world",{}).get("vehicles",[{}])[0].get("was_driven",false),"disk snapshot retains driven vehicle")
	FileAccess.open(folder.path_join("saved.json"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(save_path))
	world.production.no_save = true
	world.free()
	await process_frame
	await build(true)
	var actual: Vector3 = world.player.global_position
	check(world.production.loaded_save,"fresh Main loads seated save")
	check(actual.distance_to(saved_car_point)<8.0,"restore stays near saved car rather than remote checkpoint")
	check(world.production.vehicle_position_clear(world.driving.car,world.driving.car.position,world.driving.car.rotation.y),"restored car has supported unobstructed hull")
	if add_load_blocker:
		check(not world.driving.occupied,"occupied hull is not admitted as driven")
		check(world.session.position_clear(actual),"fallback foot capsule is on free supported floor")
		check(not world.player.input_locked and world.player.visible,"fallback player is visible and controllable")
	else:
		check(world.driving.occupied and world.driving.car.controlled,"unblocked save restores productive driver")
	var captured: bool = await capture_restored()
	var result := {"checks":checks,"failures":failures,"blocked":add_load_blocker,"saved_car":str(saved_car_point),
		"capture_after_curtain":captured,
		"actual":str(actual),"occupied":world.driving.occupied,"car_position":str(world.driving.car.position),
		"car_hull_clear":world.production.vehicle_position_clear(world.driving.car,world.driving.car.position,world.driving.car.rotation.y),
		"save_path":ProjectSettings.globalize_path(save_path),
		"user_data_dir":OS.get_user_data_dir(),"frames_ms":frames_ms,"scope":"functional rendered load with fixture map obstacle, not steady-state FPS"}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	world.free()
	await process_frame
	print("TRANSITION_DRIVER_SAVE checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
