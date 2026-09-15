extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	await process_frame
	var pool := root.get_node("EmergencyPool")
	var states := {}
	for fleet in pool._pool.values():
		for vehicle in fleet:
			states[vehicle] = [vehicle.global_position, vehicle.visible, vehicle.process_mode, vehicle.collision_layer, vehicle.collision_mask]
	await pool.prepare_presentations()
	var ok := true
	for vehicle in states:
		ok = ok and is_instance_valid(vehicle.visual_3d) and is_instance_valid(vehicle.body_model)
		ok = ok and states[vehicle] == [vehicle.global_position, vehicle.visible, vehicle.process_mode, vehicle.collision_layer, vehicle.collision_mask]
		ok = ok and vehicle.visual_3d.wheel_rig.pivots.size() >= 2
	var prepared: Node3D = pool._pool.police[0].body_model
	var dispatched: Node = pool.get_vehicle("police")
	ok = ok and dispatched.body_model == prepared and dispatched.visible
	pool.return_vehicle(dispatched)
	ok = ok and not dispatched.visible and dispatched.process_mode == Node.PROCESS_MODE_DISABLED
	print("EMERGENCY_POOL_PREPARATION count=", states.size(), " preserved_and_reused=", ok)
	quit(0 if ok else 1)
