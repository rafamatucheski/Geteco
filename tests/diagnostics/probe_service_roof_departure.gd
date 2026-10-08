extends "res://tests/test_harbor_service_roofs.gd"
func visit(target: Dictionary) -> bool:
	if not await super.visit(target): return false
	var point: Vector3 = world.session.return_point
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.98)
	query.collision_mask = 1
	query.exclude = [world.player.get_rid()]
	print("RETURN_DIAG point=",point," clear=",world.session.position_clear(point+Vector3.UP*.08)," place=",world.session.state.place_id)
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query,20): print("RETURN_BODY ",hit.collider.get_path())
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.38,point-Vector3.UP*.42,1)
	var ground: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	print("RETURN_GROUND ",ground.get("position","none")," ",ground.collider.get_path() if not ground.is_empty() else "none")
	return check(await world.session.leave_place(),"depart original service after roof return")
