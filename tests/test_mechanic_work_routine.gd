extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("MECHANIC ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func run() -> void:
	var place := preload("res://world/maciota/MaciotaPlace.gd").new()
	root.add_child(place)
	place.set_interior_active(true)
	var worker: CharacterBody3D = place.mechanic
	check(not worker.has_method("take_damage") and not worker.has_method("die"),"invulnerable resident has no damage/death path")
	# Percorre a rota inteira com física real; só a bancada física é parada de trabalho.
	var visited := [false,false,false,false]
	var origin: Vector3 = worker.position
	var travelled := 0.0
	var work_frames := 0
	var invalid_work_frames := 0
	var max_hand_error := 0.0
	var hand_errors := [0.0,0.0]
	var max_contact_error := 0.0
	for frame in 1200:
		await physics_frame
		travelled += worker.position.distance_to(origin)
		origin = worker.position
		if worker._at_station(worker.POINTS[worker.phase]): visited[worker.phase] = true
		await process_frame
		if worker.working:
			work_frames += 1
			if worker.phase != 2 or not worker._at_station(worker.POINTS[2]): invalid_work_frames += 1
			max_contact_error = maxf(max_contact_error,worker.tool.global_position.distance_to(place.mechanic_work_contact.global_position))
			var skeleton: Skeleton3D = worker.model.body.skeleton
			var targets: Array = worker._hands()
			for index in 2:
				var bone := skeleton.find_bone("mixamorig_RightHand" if index == 0 else "mixamorig_LeftHand")
				var palm: Vector3 = skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin
				# Imported rig palms must actually follow the contact targets.
				if worker.elapsed > .5:
					var error := palm.distance_to(targets[index])
					hand_errors[index] = maxf(hand_errors[index],error)
					max_hand_error = maxf(max_hand_error,error)
		elif worker.tool.visible or worker._hands() != [null,null]: invalid_work_frames += 1
		if frame % 60 == 0:
			check(worker.position.x > -2.95 and worker.position.x < -.6,"worker stays within the authored service aisle")
			check(worker.position.y > -.04 and worker.position.y < .04,"worker stays on floor")
	print("MECHANIC_ROUTE ",JSON.stringify({"visited":visited,"travelled":travelled,"phase":worker.phase,"position":str(worker.position),"elapsed":worker.elapsed,"blocked":worker.blocked_time,"hand_errors":hand_errors}))
	check(visited[0] and visited[1] and visited[2] and visited[3] and travelled > 4.0,"visits the lift and workbench via the free aisle")
	check(work_frames > 120 and invalid_work_frames == 0,"works only at the real bench, without tools or work poses at idle/waypoints")
	check(max_contact_error < .005,"wrench jaw stays on the authored service nut throughout the stroke")
	check(max_hand_error < .12,"real imported palms reach the part and wrench handle: "+str(max_hand_error))
	var contact: Vector3 = place.mechanic_work_contact.global_position
	var part_bounds: AABB = place.mechanic_workpiece.global_transform*place.mechanic_workpiece.get_aabb()
	check(contact.y > part_bounds.end.y and contact.y-part_bounds.end.y < .08,"work contact sits on the visible engine component")
	check(place.interaction_points.mechanic.distance_to(worker.global_position) < 1.0,"conversation follows worker")
	var ray := PhysicsRayQueryParameters3D.create(contact+Vector3.UP*.3,contact-Vector3.UP*.5,1)
	var physical_part := place.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not physical_part.is_empty() and physical_part.position.y > part_bounds.position.y+.2,"visible work component has physical volume above the bench")
	worker.position = worker.POINTS[2]
	worker.phase = 2
	worker.elapsed = 1.0
	place.mechanic_workpiece.hide()
	await physics_frame
	await process_frame
	check(not worker.working and not worker.tool.visible and worker._hands() == [null,null],"removed/hidden component cannot leave the mechanic working in empty space")
	place.mechanic_workpiece.show()
	# A player-sized solid in the aisle must stop him; no scripted teleport.
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .85
	blocker.add_child(shape)
	place.room.add_child(blocker)
	blocker.position = Vector3(-2.08,0,-1.275)
	worker.position = Vector3(-2.65,0,-1.1)
	worker.phase = 1
	worker.elapsed = 0.0
	worker.blocked_time = 0.0
	for frame in 180: await physics_frame
	check(Vector2(worker.position.x-blocker.position.x,worker.position.z-blocker.position.z).length() >= .57,"resident respects player-sized blocker")
	blocker.queue_free()
	place.set_interior_active(false)
	var stopped: Vector3 = worker.position
	for frame in 10: await physics_frame
	check(worker.position.is_equal_approx(stopped),"empty room stops work and movement")
	place.free()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
