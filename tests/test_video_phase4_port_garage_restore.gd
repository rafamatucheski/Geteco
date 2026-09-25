extends "res://tests/test_garage_driver_restore.gd"
## Existing garage/weapon regression, plus a witness for both restoration anchors.
func check(value: bool, label: String) -> void:
	super.check(value, label)
	if not label.contains("driver restored through admitted door"): return
	var car = world.session.garage_rewards.cars.get("garage_guest_1")
	if not is_instance_valid(car): return
	for side in [-1,1]:
		var old: Vector3 = car.to_global(Vector3(side*(car.half_width+.65),.05,.15))
		var actual: Vector3 = car.driver_door_anchor(side) + car.global_basis.x * float(side) * .11
		var shape := CapsuleShape3D.new()
		shape.radius = .32
		shape.height = 1.7
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 7
		query.exclude = [world.player.get_rid()]
		query.transform = Transform3D(Basis.IDENTITY, old + Vector3.UP*.9)
		query.motion = actual - old
		var sweep: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
		print("GARAGE_ANCHOR ", label, " side=", side, " old=", old, " actual=", actual, " old_clear=", world.session.position_clear(old), " actual_clear=", world.session.position_clear(actual), " sweep=", sweep)
