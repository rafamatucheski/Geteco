extends SceneTree

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	create_timer(20).timeout.connect(func(): printerr("EMERGENCY_3D_COVER TIMEOUT"); quit(2))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	root.get_node("WantedManager").set_process(false)
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.position = Vector2(400, 220)
	camera.zoom = Vector2(2, 2)
	var units: Array = []
	await process_frame
	var pool := root.get_node("EmergencyPool")
	for service in ["police", "ambulance", "fire", "coroner"]:
		var car = pool.get_vehicle(service)
		assert(car != null)
		car.set_physics_process(false)
		car.position = Vector2(145 + units.size() * 170, 220)
		car.rotation = 0.0
		car.lights.visible = false
		assert(car.is_3d_vehicle and car.body_model != null)
		assert(car.visual.texture is ViewportTexture)
		assert(car.body_viewport.own_world_3d)
		assert(car.visual_3d.second_headlight != null, "Every service model uses paired headlights")
		for side in [-1.0, 1.0]:
			assert(car.visual_3d.doors[side].extracted_triangles > 0, "Every service has real cab doors")
		units.append(car)
	var police = units[0]
	police.open_crew_cover_door(-1.0)
	police.open_crew_cover_door(1.0)
	await create_timer(0.8).timeout
	assert(police._tactical_doors.size() == 2)
	for side in [-1.0, 1.0]:
		var real_door: Node3D = police.visual_3d.doors[side]
		assert(real_door.extracted_triangles > 0)
		assert(absf(real_door.hinge.rotation.y) > 0.9, "Both real mesh doors must remain open")
		var door: Node2D = police._tactical_doors[side]
		var center := door.to_global(Vector2(-12, 3))
		var normal := door.global_transform.y.normalized()
		var query := PhysicsRayQueryParameters2D.create(center - normal * 15, center + normal * 15, 1)
		var hit: Dictionary = police.get_world_2d().direct_space_state.intersect_ray(query)
		assert(not hit.is_empty() and hit.collider.is_in_group("metal_prop"), "Door physically stops bullet rays")
	var renders: int = police.visual_3d.render_requests
	await create_timer(0.4).timeout
	assert(police.visual_3d.render_requests == renders, "Parked model does not render continuously")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/emergency-3d-cover-review.png")
	police.close_crew_cover_door(-1.0)
	police.close_crew_cover_door(1.0)
	await create_timer(0.7).timeout
	assert(police._tactical_doors.is_empty())
	for side in [-1.0, 1.0]: assert(absf(police.visual_3d.doors[side].hinge.rotation.y) < 0.01)
	police.open_crew_cover_door(-1.0)
	police._deactivate()
	assert(police._tactical_doors.is_empty(), "Pool recycling must release cover bodies")
	for car in units:
		if car != police: car._deactivate()
	scene.queue_free()
	await process_frame
	print("EMERGENCY_3D_COVER PASS")
	quit()
