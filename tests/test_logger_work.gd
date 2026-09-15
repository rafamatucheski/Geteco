extends SceneTree
var failures: Array[String] = []
var movie_frame := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ")+message)
	if not value: failures.append(message)
func _run() -> void:
	create_timer(70).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	var player := Node2D.new()
	player.position = Vector2(0,-70)
	player.add_to_group("player")
	world.add_child(player)
	var resident = preload("res://world/mountain_pass/WinterResident.gd").new()
	resident.role = "logger"
	resident.appearance_variant = 0
	world.add_child(resident)
	resident.set_physics_process(false)
	for i in 3: await physics_frame
	var station = resident.work_station
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE*9
	camera.position = Vector2(0,3)
	world.add_child(camera)
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-100,-100),Vector2(100,-100),Vector2(100,100),Vector2(-100,100)])
	ground.color = Color("424c3c")
	ground.z_index = -10
	world.add_child(ground)
	for side in [-1,1]:
		resident._logger_work.stop()
		resident.global_position = station.global_position+Vector2(side*25,0)
		resident.destination = station.global_position+Vector2(side*13,0)
		resident.activity = "walk"
		resident._return_to_work = true
		resident.activity_left = 20
		resident.travel_time = 0
		for i in 600:
			await physics_frame
			resident._physics_process(1.0/60)
			if resident._logger_work.working: break
		check(resident._logger_work.working,"reaches and aligns at side %d"%side)
		check(resident.test_move(resident.transform,station.global_position-resident.global_position),"solid stump blocks crossing from side %d"%side)
		check(station.model.get_parent()==resident.viewport,"wood shares depth with the worker")
		var work = resident._logger_work
		var count: int = station.model.split_count
		work.time = 0
		work.impact_cycle = -1
		work.update(1.64)
		check(station.model.split_count==count,"no impact before contact")
		work.update(.02)
		work.update(.10)
		check(station.model.split_count==count+1,"one impact at contact, no repeated impact during hold")
		var minimum := INF
		var contact_error := 0.0
		var max_reach := 0.0
		var minimum_geometry_gap := INF
		for frame in 193:
			resident.model.work_time = frame/60.0
			resident.model._process(0)
			var pose = resident.model.chop_pose
			minimum = minf(minimum,pose.edge.y-pose.target.y)
			for mesh in pose.tool.get_children():
				var bounds: AABB = mesh.get_aabb()
				for corner in 8:
					var point: Vector3 = station.model.to_local(mesh.to_global(bounds.get_endpoint(corner)))
					if absf(point.x)<.065 and absf(point.z)<.07:
						minimum_geometry_gap = minf(minimum_geometry_gap,point.y-.695)
			for arm in 2:
				max_reach = maxf(max_reach,pose.grips[arm].distance_to(resident.model.limbs[1 if arm==0 else 3].position))
			if frame==99:
				contact_error = pose.edge.distance_to(pose.target)
		check(minimum>=-.0001 and contact_error<.001,"blade stops at the log top throughout a full cycle")
		check(minimum_geometry_gap>=-.001,"actual tool geometry stays outside the wood")
		check(max_reach<=.70,"two hands stay within anatomical reach (%.3f m)"%max_reach)
		if DisplayServer.get_name()!="headless":
			for phase in [0.0,1.25,1.65,2.2]:
				resident.model.work_time = phase
				resident.model._process(0)
				resident.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				for i in 3: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/logger-0913/side%d-phase%.2f.png"%[side,phase])
			if "--motion" in OS.get_cmdline_user_args():
				for frame in 96:
					resident.model.work_time = frame/30.0
					resident.model._process(0)
					resident.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("D:/geteco/artifacts/logger-0913/frame%04d.png"%movie_frame)
					movie_frame += 1
		resident._logger_work.stop()
		check(station.model.get_parent()==station.viewport_3d and station.sprite_3d.visible,"interruption restores the world workpiece")
		resident.global_position += Vector2(side*6,0)
		resident.activity = "work"
		resident._logger_work.update(.1)
		check(not resident.model.work_pose_active and resident.activity=="walk","displacement cancels chopping and requires a new approach")
	# Cross to the other working side using production navigation and collision.
	resident.global_position = station.global_position+Vector2(13,0)
	resident.destination = station.global_position+Vector2(-13,0)
	resident.activity = "walk"
	resident._return_to_work = true
	resident.activity_left = 25
	resident.travel_time = 0
	var clearance := INF
	for i in 720:
		await physics_frame
		resident._physics_process(1.0/60)
		clearance = minf(clearance,resident.global_position.distance_to(station.global_position))
		if resident._logger_work.working: break
	check(resident._logger_work.working and resident.global_position.x<station.global_position.x,"walks around the block to change sides")
	check(clearance>9,"keeps body clear of the wood during the change of side")
	print("LOGGER_WORK failures=",failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
